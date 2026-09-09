/**
 * Whimread feedback 云函数
 *
 * 路由(后缀匹配,网关剥前缀后由 main 入口分发):
 *   POST /api/v1/feedback/submit   用户反馈(可选附带日志)
 *   POST /api/logs/upload          LogReporterService 批量日志上报
 *   GET  /api/v1/feedback/list     管理端列出报告(X-API-TOKEN)
 *   GET  /api/v1/feedback/detail   管理端单条报告 + 附带日志(X-API-TOKEN)
 *   GET  /api/v1/feedback/logs     管理端按 device_id 拉流式日志(X-API-TOKEN)
 *
 * 鉴权:
 *   - submit / upload: verifyDeviceJwt(JWT sub = android_id)
 *   - list / detail / logs: X-API-TOKEN == process.env.PUBLISH_API_TOKEN
 *
 * 入参校验 / 清洗 / 限流抽到 ./lib/validate(脱机可单测)。
 *
 * ⚠️ 不在响应里 echo process.env / event.headers / 上游错误原文;
 *    客户端日志内容 message / stack_trace 已由客户端做长度截断,
 *    服务端再做一次硬上限避免极端滥用。
 */

'use strict';

const { ok, err, handleCors, parseBody, ErrorCodes } = require('./common/errors');
const { getDb } = require('./common/db');
const { verifyDeviceJwt } = require('./common/jwt');
const logger = require('./common/logger');
const v = require('./lib/validate');

// ===== 管理端鉴权 =====
function requireAdmin(event, context) {
    const expected = process.env.PUBLISH_API_TOKEN;
    if (!expected) {
        logger.error(context, 'feedback admin: PUBLISH_API_TOKEN not configured');
        return false;
    }
    const h = event.headers || {};
    const got = h['x-api-token'] || h['X-API-Token'] || h['X-Api-Token'] || '';
    return typeof got === 'string' && got === expected;
}

// ===== 多行 INSERT(直接走 db.raw,绕过 db.js 单 insert) =====
async function bulkInsertLogs(db, rows) {
    const statements = v.buildLogInsertSql(
        rows[0]?.report_id ?? null,
        rows[0]?.device_id,
        rows,
    );
    for (const sql of statements) {
        const { error } = await db.raw(sql);
        if (error) throw error;
    }
}

// ===== 入口分发 =====
exports.main = async (event, context) => {
    const corsResp = handleCors(event);
    if (corsResp) return corsResp;

    const method = event.httpMethod || 'POST';
    const rawPath = (event.path || '').split('?')[0].replace(/\/+$/, '');
    const route = rawPath.split('/').pop() || '';

    try {
        if (method === 'POST' && route === 'submit') return await handleSubmit(event, context);
        if (method === 'POST' && route === 'upload') return await handleUpload(event, context);
        if (method === 'GET'  && route === 'list')   return await handleList(event, context);
        if (method === 'GET'  && route === 'detail') return await handleDetail(event, context);
        if (method === 'GET'  && route === 'logs')   return await handleLogs(event, context);
        return err(404, ErrorCodes.NOT_FOUND, `Unknown route: ${method} ${event.path || ''}`);
    } catch (e) {
        if (e instanceof v.ValidationError) {
            return err(400, ErrorCodes.BAD_REQUEST, e.message);
        }
        logger.error(context, `feedback uncaught: ${e.message}`, { route, method });
        return err(500, ErrorCodes.INTERNAL, 'Internal error');
    }
};

// ===== POST /submit =====
async function handleSubmit(event, context) {
    if (!v.checkBodySize(event)) return err(413, 'PAYLOAD_TOO_LARGE', '请求体过大');

    let claims;
    try {
        claims = await verifyDeviceJwt(event.headers, context);
    } catch (e) {
        return err(401, e.code || ErrorCodes.JWT_INVALID, 'Invalid JWT');
    }
    const androidId = claims.sub;

    if (!v.checkRate(androidId)) return err(429, 'RATE_LIMITED', '提交过于频繁,请稍后再试');

    const body = parseBody(event);
    const kind = v.inSetOr(body.kind, v.VALID_KINDS, 'user_report');
    const category = v.VALID_CATEGORIES.has(body.category) ? body.category : null;
    const title = v.clampStr(body.title, v.MAX_TITLE, { required: true, label: 'title' });
    const description = v.clampStr(body.description, v.MAX_DESCRIPTION, { required: true, label: 'description' });
    const steps = v.clampStr(body.steps, v.MAX_STEPS);
    const contact = v.clampStr(body.contact, v.MAX_CONTACT);
    const appVersion = v.clampStr(body.app_version, v.MAX_APP_VERSION);
    const platform = v.clampStr(body.platform, 20);
    const deviceModel = v.clampStr(body.device_model, v.MAX_DEVICE_MODEL);

    const includeLogs = v.boolOr(body.include_logs, false);
    const rawLogs = Array.isArray(body.attached_logs) ? body.attached_logs : [];
    let cleanedLogs = [];
    if (includeLogs) {
        if (rawLogs.length === 0) throw new v.ValidationError('include_logs=true 时 attached_logs 不能为空');
        if (rawLogs.length > v.MAX_LOG_ENTRIES_PER_REPORT) {
            throw new v.ValidationError(`attached_logs 最多 ${v.MAX_LOG_ENTRIES_PER_REPORT} 条`);
        }
        cleanedLogs = rawLogs.map((e, i) => v.sanitizeLogEntry(e, i));
    }

    const db = getDb(context);

    const insReport = await db.from('feedback_reports').insert({
        device_id: androidId,
        kind,
        category,
        title,
        description,
        steps,
        contact,
        app_version: appVersion,
        platform,
        device_model: deviceModel,
        log_count: cleanedLogs.length,
        status: 'open',
    }).select('id, created_at');
    if (insReport.error) {
        logger.error(context, `feedback submit: insert report failed: ${insReport.error.message}`);
        return err(500, ErrorCodes.INTERNAL, '写入失败');
    }
    const report = insReport.data;
    const reportId = report.id;

    if (cleanedLogs.length > 0) {
        const rows = cleanedLogs.map((l, i) => ({
            report_id: reportId,
            device_id: androidId,
            ts: l.ts,
            level: l.level,
            category: l.category,
            message: l.message,
            stack_trace: l.stack_trace,
            tags: l.tags,
        }));
        try {
            await bulkInsertLogs(db, rows);
        } catch (e) {
            logger.error(context, `feedback submit: insert logs failed: ${e.message || e.code}`);
            return ok({ report_id: reportId, log_count: 0, created_at: report.created_at, logs_written: 0, warning: 'logs_insert_failed' });
        }
    }

    logger.info(context, 'feedback submit ok', {
        android: androidId.slice(0, 8),
        kind,
        report_id: reportId,
        log_count: cleanedLogs.length,
    });
    return ok({
        report_id: reportId,
        log_count: cleanedLogs.length,
        created_at: report.created_at,
    });
}

// ===== POST /upload(LogReporterService 批量上报) =====
async function handleUpload(event, context) {
    if (!v.checkBodySize(event)) return err(413, 'PAYLOAD_TOO_LARGE', '请求体过大');

    let claims;
    try {
        claims = await verifyDeviceJwt(event.headers, context);
    } catch (e) {
        return err(401, e.code || ErrorCodes.JWT_INVALID, 'Invalid JWT');
    }
    const androidId = claims.sub;

    const body = parseBody(event);
    const rawLogs = Array.isArray(body.logs) ? body.logs : [];
    if (rawLogs.length === 0) {
        return err(400, ErrorCodes.BAD_REQUEST, 'logs 数组不能为空');
    }
    if (rawLogs.length > v.MAX_LOG_ENTRIES_PER_BATCH) {
        return err(400, ErrorCodes.BAD_REQUEST, `logs 单批最多 ${v.MAX_LOG_ENTRIES_PER_BATCH} 条`);
    }
    const cleaned = rawLogs.map((e, i) => v.sanitizeLogEntry(e, i));

    const db = getDb(context);
    const rows = cleaned.map((l) => ({
        report_id: null,
        device_id: androidId,
        ts: l.ts,
        level: l.level,
        category: l.category,
        message: l.message,
        stack_trace: l.stack_trace,
        tags: l.tags,
    }));
    try {
        await bulkInsertLogs(db, rows);
    } catch (e) {
        logger.error(context, `feedback upload: insert failed: ${e.message || e.code}`);
        return err(500, ErrorCodes.INTERNAL, '写入失败');
    }
    logger.info(context, 'feedback upload ok', {
        android: androidId.slice(0, 8),
        count: cleaned.length,
    });
    return ok({ accepted: cleaned.length });
}

// ===== GET /list(管理端) =====
async function handleList(event, context) {
    if (!requireAdmin(event, context)) return err(401, 'UNAUTHORIZED', 'Invalid admin token');

    const q = v.parseQuery(event);
    const limit = v.clampInt(q.limit, 1, 100, 20);
    const offset = v.clampInt(q.offset, 0, 10000, 0);

    const db = getDb(context);
    let qb = db.from('feedback_reports').select(
        'id, device_id, kind, category, title, description, steps, contact, app_version, platform, device_model, log_count, status, created_at'
    );
    if (q.kind && v.VALID_KINDS.has(q.kind)) qb = qb.eq('kind', q.kind);
    if (q.status) qb = qb.eq('status', q.status);
    if (q.since) qb = qb.gte('created_at', q.since);
    if (q.until) qb = qb.lte('created_at', q.until);
    qb = qb.order('created_at', { ascending: false }).limit(limit);

    const { data: rows, error } = await qb;
    if (error) {
        logger.error(context, `feedback list: ${error.message}`);
        return err(500, ErrorCodes.INTERNAL, '查询失败');
    }
    return ok({ reports: rows, limit, offset, count: (rows || []).length });
}

// ===== GET /detail?id=N(管理端) =====
async function handleDetail(event, context) {
    if (!requireAdmin(event, context)) return err(401, 'UNAUTHORIZED', 'Invalid admin token');
    const q = v.parseQuery(event);
    const id = parseInt(q.id, 10);
    if (!Number.isFinite(id) || id <= 0) {
        return err(400, ErrorCodes.BAD_REQUEST, 'id 必填且为正整数');
    }
    const db = getDb(context);
    const { data: report, error } = await db.from('feedback_reports').select(
        'id, device_id, kind, category, title, description, steps, contact, app_version, platform, device_model, log_count, status, created_at'
    ).eq('id', id).single();
    if (error) {
        if (error.code === 'NOT_FOUND') return err(404, ErrorCodes.NOT_FOUND, '报告不存在');
        logger.error(context, `feedback detail: ${error.message}`);
        return err(500, ErrorCodes.INTERNAL, '查询失败');
    }

    const { data: logs, error: logErr } = await db.from('feedback_logs').select(
        'id, seq, ts, level, category, message, stack_trace, tags'
    ).eq('report_id', id).order('seq', { ascending: true }).limit(v.MAX_LOG_ENTRIES_PER_REPORT);
    if (logErr) {
        logger.error(context, `feedback detail logs: ${logErr.message}`);
        return err(500, ErrorCodes.INTERNAL, '日志查询失败');
    }
    return ok({ report, logs: logs || [] });
}

// ===== GET /logs?device_id=&since=&until=&level=(管理端,拉流式日志) =====
async function handleLogs(event, context) {
    if (!requireAdmin(event, context)) return err(401, 'UNAUTHORIZED', 'Invalid admin token');
    const q = v.parseQuery(event);
    const deviceId = q.device_id || q.deviceId;
    if (!deviceId) return err(400, ErrorCodes.BAD_REQUEST, 'device_id 必填');
    const limit = v.clampInt(q.limit, 1, 500, 100);

    const db = getDb(context);
    let qb = db.from('feedback_logs').select(
        'id, report_id, device_id, seq, ts, level, category, message, stack_trace, tags, created_at'
    ).eq('device_id', deviceId).is('report_id', null).order('ts', { ascending: false }).limit(limit);
    if (q.since) qb = qb.gte('ts', q.since);
    if (q.until) qb = qb.lte('ts', q.until);
    if (q.level && v.VALID_LEVELS.has(q.level)) qb = qb.eq('level', q.level);

    const { data: rows, error } = await qb;
    if (error) {
        logger.error(context, `feedback logs: ${error.message}`);
        return err(500, ErrorCodes.INTERNAL, '查询失败');
    }
    return ok({ logs: rows || [], count: (rows || []).length, limit });
}
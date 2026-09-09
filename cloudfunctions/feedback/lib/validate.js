/**
 * feedback 云函数 — 入参校验 / 清洗 / 限流(纯函数,脱机可测)
 *
 * 全部常量与 feedback 云函数 index.js 的服务端硬上限对齐,
 * 客户端 FeedbackService 的 cap 需与此保持一致。
 */

'use strict';

// ===== 限制常量 =====
const MAX_BODY_BYTES = 512 * 1024;        // 整个请求 body 上限
const MAX_TITLE = 200;
const MAX_DESCRIPTION = 5000;
const MAX_STEPS = 5000;
const MAX_CONTACT = 200;
const MAX_APP_VERSION = 40;
const MAX_DEVICE_MODEL = 200;
const MAX_LOG_ENTRIES_PER_REPORT = 300;
const MAX_LOG_ENTRIES_PER_BATCH = 50;     // /upload 单次最多
const MAX_LOG_MESSAGE = 500;
const MAX_LOG_STACK = 4000;
const MAX_TAG_LEN = 100;
const MAX_TAGS_PER_ENTRY = 10;

const VALID_KINDS = new Set(['user_report', 'native_crash']);
const VALID_CATEGORIES = new Set(['bug', 'feature', 'usage']);
const VALID_LEVELS = new Set(['debug', 'info', 'warning', 'error']);

// ===== 限流(进程内 LRU,60s / 5 次 / device) =====
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 60_000;
const _rateMap = new Map(); // deviceId -> number[] timestamps

function checkRate(deviceId) {
    const now = Date.now();
    const arr = (_rateMap.get(deviceId) || []).filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
    if (arr.length >= RATE_LIMIT_MAX) {
        _rateMap.set(deviceId, arr); // 保留窗口内历史
        return false;
    }
    arr.push(now);
    _rateMap.set(deviceId, arr);
    return true;
}

/** 测试专用:清空限流窗口 */
function resetRateLimit() {
    _rateMap.clear();
}

class ValidationError extends Error {
    constructor(msg) { super(msg); this.code = 'VALIDATION'; }
}

// ===== 入参清洗 / 截断 =====
function clampStr(v, max, { required = false, label = 'field' } = {}) {
    if (v === undefined || v === null || v === '') {
        if (required) throw new ValidationError(`${label} 不能为空`);
        return null;
    }
    if (typeof v !== 'string') throw new ValidationError(`${label} 必须是字符串`);
    if (v.length > max) v = v.slice(0, max);
    return v;
}

function boolOr(v, dft) {
    return typeof v === 'boolean' ? v : dft;
}

function inSetOr(v, set, dft) {
    return typeof v === 'string' && set.has(v) ? v : dft;
}

// ===== LogEntry 清洗(供 /submit 和 /upload 共用) =====
function sanitizeLogEntry(raw, idx) {
    if (!raw || typeof raw !== 'object') {
        throw new ValidationError(`logs[${idx}] 必须是对象`);
    }
    const level = inSetOr(raw.level, VALID_LEVELS, 'info');
    const ts = typeof raw.timestamp === 'string' && raw.timestamp
        ? raw.timestamp
        : new Date().toISOString();
    const message = clampStr(raw.message, MAX_LOG_MESSAGE, { required: true, label: `logs[${idx}].message` });
    const stack = raw.stack_trace || raw.stackTrace;
    const stackClean = stack ? clampStr(String(stack), MAX_LOG_STACK) : null;
    const category = typeof raw.category === 'string' ? raw.category.slice(0, 40) : null;
    const tags = Array.isArray(raw.tags)
        ? raw.tags.filter((t) => typeof t === 'string').slice(0, MAX_TAGS_PER_ENTRY)
            .map((t) => t.slice(0, MAX_TAG_LEN))
        : null;
    return {
        ts,
        level,
        message,
        stack_trace: stackClean,
        category,
        tags: tags && tags.length ? tags : null,
    };
}

// ===== Body 大小硬上限 =====
function checkBodySize(event) {
    let size = 0;
    if (typeof event.body === 'string') size = event.body.length;
    else if (event.body) size = JSON.stringify(event.body).length;
    return size <= MAX_BODY_BYTES;
}

/**
 * 多行 INSERT 的字面量转义(direct SQL 用,绕过 db.js 的单 insert)。
 * 对象 / 数组不允许直接传入(调用方自行 JSON.stringify)。
 */
function pgLiteral(v) {
    if (v === null || v === undefined) return 'NULL';
    if (typeof v === 'number' && Number.isFinite(v)) return String(v);
    if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE';
    if (typeof v === 'string') return `'${v.replace(/'/g, "''")}'`;
    throw new Error(`pgLiteral unsupported type: ${typeof v}`);
}

/**
 * 批量构造 feedback_logs 多行 INSERT VALUES(direct SQL,绕过 db.js 单 insert)。
 * 返回 SQL 语句数组(每批 50 行)。
 */
function buildLogInsertSql(reportId, deviceId, logs) {
    const CHUNK = 50;
    const statements = [];
    for (let off = 0; off < logs.length; off += CHUNK) {
        const chunk = logs.slice(off, off + CHUNK);
        const tuples = chunk.map((r, i) => {
            const seq = reportId !== null ? off + i : 0;
            return `(${pgLiteral(reportId)}, ${pgLiteral(deviceId)}, ${pgLiteral(seq)}, ${pgLiteral(r.ts)}::timestamptz, ${pgLiteral(r.level)}, ${pgLiteral(r.category)}, ${pgLiteral(r.message)}, ${pgLiteral(r.stack_trace)}, ${r.tags ? pgLiteral(JSON.stringify(r.tags)) + '::jsonb' : 'NULL'}, NOW())`;
        }).join(',');
        statements.push(
            `INSERT INTO feedback_logs (report_id, device_id, seq, ts, level, category, message, stack_trace, tags, created_at) VALUES ${tuples}`,
        );
    }
    return statements;
}

/** 解析 event 上的 query(网关可能在 queryStringParameters 或 path?x=y) */
function parseQuery(event) {
    const out = { ...(event.queryStringParameters || {}) };
    const q = (event.path || '').split('?')[1];
    if (q) {
        for (const pair of q.split('&')) {
            const [k, v] = pair.split('=');
            if (k && !(k in out)) out[decodeURIComponent(k)] = decodeURIComponent(v || '');
        }
    }
    return out;
}

function clampInt(v, lo, hi, dft) {
    const n = parseInt(v, 10);
    if (!Number.isFinite(n)) return dft;
    return Math.min(hi, Math.max(lo, n));
}

module.exports = {
    MAX_BODY_BYTES,
    MAX_TITLE,
    MAX_DESCRIPTION,
    MAX_STEPS,
    MAX_CONTACT,
    MAX_LOG_ENTRIES_PER_REPORT,
    MAX_LOG_ENTRIES_PER_BATCH,
    MAX_LOG_MESSAGE,
    VALID_KINDS,
    VALID_CATEGORIES,
    VALID_LEVELS,
    RATE_LIMIT_MAX,
    RATE_LIMIT_WINDOW_MS,
    checkRate,
    resetRateLimit,
    ValidationError,
    clampStr,
    boolOr,
    inSetOr,
    sanitizeLogEntry,
    checkBodySize,
    pgLiteral,
    buildLogInsertSql,
    parseQuery,
    clampInt,
};
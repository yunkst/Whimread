/**
 * Whimread device-auth 云函数
 *
 * 路由:
 *   POST /api/v1/devices/challenge   申请一次性 challenge nonce
 *   POST /api/v1/devices/register     提交 attestation,获取 JWT
 *   GET  /api/v1/devices/me           查询当前设备额度
 *
 * 来源:[Skill: cloud-functions/SKILL.md] Event Function 形态
 *
 * ⚠️ 已知限制(2026-09-08):register/me 内部 db.from().insert/select 暂时
 * 走 NotImplementedError。CloudBase SDK 3.18.3 暂不支持云函数内调用
 * PG REST API(详见 spec §12)。当前端到端可用:
 *   - challenge (不需要 PG)
 *   - me 鉴权失败路径(无需查 PG)
 *   - register 输入校验路径(无需查 PG)
 *   - 注册成功路径暂返回 503 PG_NOT_AVAILABLE
 */

const crypto = require('crypto');
const { ok, err, handleCors, parseBody, ErrorCodes } = require('./common/errors');
const { getDb } = require('./common/db');
const { signDeviceJwt, verifyDeviceJwt } = require('./common/jwt');
const { grantQuota, REGISTER_BONUS } = require('./common/quota');
const logger = require('./common/logger');
const { verifyAttestation } = require('./lib/attestation');
const { checkStarred, isValidGithubLogin, rateLimitAllow } = require('./lib/github');

const CHALLENGE_TTL_SEC = 120;

exports.main = async (event, context) => {
    const corsResp = handleCors(event);
    if (corsResp) return corsResp;

    const method = event.httpMethod || 'GET';
    const rawPath = (event.path || '').split('?')[0].replace(/\/+$/, '');
    const route = rawPath.split('/').pop() || '';

    try {
        if (method === 'POST' && route === 'challenge') {
            return await handleChallenge(event, context);
        }
        if (method === 'POST' && route === 'register') {
            return await handleRegister(event, context);
        }
        if (method === 'GET' && route === 'me') {
            return await handleMe(event, context);
        }
        if (method === 'POST' && route === 'redeem') {
            return await handleRedeem(event, context);
        }
        return err(404, ErrorCodes.NOT_FOUND, `Unknown route: ${method} ${rawPath}`);
    } catch (e) {
        logger.error(context, `device-auth uncaught: ${e.message}`, { code: e.code });
        // PG SDK 未跑通 → 503(不是内部错误)
        if (e.code === 'NOT_IMPLEMENTED') {
            return err(503, 'PG_NOT_AVAILABLE',
                e.message + ' — 详见 docs/superpowers/specs/2026-09-07-cloudbase-migration-v2-minimal.md §12');
        }
        return err(500, ErrorCodes.INTERNAL, 'Internal error');
    }
};

async function handleChallenge(event, context) {
    const nonce = crypto.randomUUID();
    logger.info(context, 'challenge issued', { nonce_preview: nonce.slice(0, 8) });
    return ok({ nonce, expires_in: CHALLENGE_TTL_SEC });
}

async function handleRegister(event, context) {
    const body = parseBody(event);
    const { android_id, platform, app_version, challenge, certificate_chain_pem } = body;

    if (!android_id || typeof android_id !== 'string' || android_id.length > 64) {
        return err(400, ErrorCodes.BAD_REQUEST, 'android_id required (max 64 chars)');
    }
    if (platform !== 'android') {
        return err(400, ErrorCodes.BAD_REQUEST, 'platform must be "android"');
    }
    if (!challenge || typeof challenge !== 'string') {
        return err(400, ErrorCodes.BAD_REQUEST, 'challenge required');
    }
    if (!Array.isArray(certificate_chain_pem) || certificate_chain_pem.length === 0) {
        return err(400, ErrorCodes.ATTESTATION_FAILED, 'certificate_chain_pem required');
    }

    const att = verifyAttestation(certificate_chain_pem, challenge);
    const attestationVerified = att.trusted;

    const db = getDb(context);

    // 查设备是否已存在
    const { data: existing, error: selectErr } = await db.from('devices')
        .select('android_id, quota_balance, status')
        .eq('android_id', android_id)
        .single();

    // PG SDK 未跑通 → 503
    if (selectErr && selectErr.code === 'NOT_IMPLEMENTED') {
        return err(503, 'PG_NOT_AVAILABLE',
            'PG REST API 调用暂未在 CloudBase SDK 3.18.3 上跑通。' +
            '详见 docs/superpowers/specs/2026-09-07-cloudbase-migration-v2-minimal.md §12');
    }
    if (selectErr && selectErr.code !== 'NOT_FOUND') {
        logger.error(context, `select device failed: ${selectErr.message}`);
        return err(500, ErrorCodes.INTERNAL, 'DB select failed');
    }

    let isNewDevice = false;
    let quotaBalance = 0;

    if (existing) {
        if (existing.status === 'banned') {
            return err(403, ErrorCodes.DEVICE_BANNED, 'Device banned');
        }
        quotaBalance = existing.quota_balance;
        logger.info(context, 'device re-register', { android_id_preview: android_id.slice(0, 8) });
    } else {
        isNewDevice = true;
        const { error: insertErr } = await db.from('devices').insert({
            android_id,
            attestation_cert: att.leafCert,
        });
        if (insertErr) {
            logger.error(context, `insert device failed: ${insertErr.message}`);
            return err(500, ErrorCodes.INTERNAL, 'Failed to register device');
        }
        quotaBalance = REGISTER_BONUS;
        await db.from('quota_changes').insert({
            android_id,
            change_amount: REGISTER_BONUS,
            reason: 'register_bonus',
            balance_after: REGISTER_BONUS,
        });
        logger.info(context, 'device registered', { android_id_preview: android_id.slice(0, 8) });
    }

    await db.from('devices')
        .update({ last_seen_at: new Date().toISOString() })
        .eq('android_id', android_id);

    const { token, expires_at } = await signDeviceJwt(android_id, context);

    return ok({
        device_id: android_id,
        token,
        expires_at: expires_at.toISOString(),
        attestation_verified: attestationVerified,
        quota_balance: quotaBalance,
        is_new_device: isNewDevice,
    });
}

async function handleMe(event, context) {
    let claims;
    try {
        claims = await verifyDeviceJwt(event.headers, context);
    } catch (e) {
        return err(401, e.code || ErrorCodes.JWT_INVALID, 'Invalid JWT');
    }

    const db = getDb(context);
    const { data, error } = await db.from('devices')
        .select('android_id, quota_balance, status, attestation_cert')
        .eq('android_id', claims.sub)
        .single();

    if (error) {
        if (error.code === 'NOT_IMPLEMENTED') {
            return err(503, 'PG_NOT_AVAILABLE', '见 spec §12');
        }
        if (error.code === 'NOT_FOUND' || !data) {
            return err(404, ErrorCodes.DEVICE_NOT_FOUND, 'Device not found');
        }
        return err(500, ErrorCodes.INTERNAL, `DB query failed: ${error.message}`);
    }
    return ok({
        device_id: data.android_id,
        quota_balance: data.quota_balance,
        status: data.status,
        attestation_verified: !!data.attestation_cert,
    });
}

/**
 * POST /api/v1/devices/star/redeem(设备 JWT,规格 §6.2)
 * 错误码与客户端 mapRedeemDioError 一一对应,勿改名。
 */
const STAR_REDEEM_AMOUNT = parseInt(process.env.STAR_REDEEM_AMOUNT || '50', 10);

async function handleRedeem(event, context) {
    let claims;
    try {
        claims = await verifyDeviceJwt(event.headers, context);
    } catch (e) {
        return err(401, e.code || ErrorCodes.JWT_INVALID, 'Invalid JWT');
    }

    const body = parseBody(event);
    const login = String(body.github_login || '').trim();
    if (!isValidGithubLogin(login)) {
        return err(400, 'INVALID_GITHUB_LOGIN', 'GitHub 用户名格式不正确');
    }
    if (!rateLimitAllow(claims.sub)) {
        return err(429, 'STAR_REDEEM_RATE_LIMITED', '兑换请求过于频繁');
    }

    const db = getDb(context);
    const { data: device, error: devErr } = await db.from('devices')
        .select('quota_balance, status')
        .eq('android_id', claims.sub).single();
    if (devErr || !device) return err(404, ErrorCodes.DEVICE_NOT_FOUND, 'Device not found');
    if (device.status === 'banned') return err(403, ErrorCodes.DEVICE_BANNED, 'Device banned');

    // 幂等:同一 GitHub 账号全库仅可兑一次(并发窗口由迁移里的
    // uq_quota_changes_star_login 部分唯一索引兜底)
    const { data: prev } = await db.raw(
        `SELECT id FROM quota_changes
         WHERE reason = 'star_redeem' AND metadata->>'github_login' = '${login.replace(/'/g, "''")}'
         LIMIT 1`);
    if (prev && prev.length > 0) {
        return err(409, 'ALREADY_REDEEMED', '该 GitHub 账号已兑换过');
    }

    // GitHub 校验:失败/未 star 一律不发放(§9 降级路径)
    const gh = await checkStarred(process.env.GITHUB_STAR_REPO, login, { token: process.env.GITHUB_TOKEN });
    if (!gh.ok) {
        logger.error(context, 'github check failed', { status: gh.status, error: gh.error });
        return err(503, 'GITHUB_CHECK_FAILED', 'GitHub 校验暂不可用,请稍后重试');
    }
    if (!gh.starred) {
        return err(400, 'NOT_STARRED', '未检测到 Star');
    }

    // 发额度(与 register_bonus 同模式:先更余额,再落审计流水)
    const amount = STAR_REDEEM_AMOUNT;
    const newBalance = device.quota_balance + amount;
    const { error: updErr } = await db.from('devices')
        .update({ quota_balance: newBalance, updated_at: new Date().toISOString() })
        .eq('android_id', claims.sub);
    if (updErr) return err(500, ErrorCodes.INTERNAL, 'Failed to grant quota');
    const { error: auditErr } = await db.from('quota_changes').insert({
        android_id: claims.sub,
        change_amount: amount,
        reason: 'star_redeem',
        balance_after: newBalance,
        metadata: JSON.stringify({ github_login: login }),
    });
    if (auditErr) {
        // 并发同账号兑换触发 uq_quota_changes_star_login 部分唯一索引。
        // ⚠️ db.js Builder 对错误是返回 {error} 而非 throw,必须判返回值
        logger.error(context, 'redeem audit insert failed', { message: auditErr.message });
        if (String(auditErr.message || '').includes('duplicate key')) {
            return err(409, 'ALREADY_REDEEMED', '该 GitHub 账号已兑换过');
        }
        return err(500, ErrorCodes.INTERNAL, 'Failed to record redeem');
    }

    logger.info(context, 'star redeemed', { github_login: login, amount });
    return ok({ granted: amount, quota_balance: newBalance, github_login: login, message: '兑换成功' });
}

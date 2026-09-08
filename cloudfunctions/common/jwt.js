/**
 * 设备 JWT 签发 / 校验(RS256)
 *
 * 设计:
 * - 私钥存云函数环境变量 DEVICE_JWT_PRIVATE_KEY(部署时通过 `tcb fn config update` 注入)
 * - 公钥对应 DEVICE_JWT_PUBLIC_KEY(校验用,也存环境变量,生产建议挂 KMS)
 * - 算法:RS256(非对称,可对外暴露公钥做离线校验)
 * - 有效期:30 天
 * - payload: { sub: android_id, kind: 'device', jti: uuid }
 * - 持久化:device_jwts 表存 jti + android_id + expires_at + revoked_at,支持撤销
 *
 * 来源:[Skill: cloud-functions/SKILL.md] 不能 echo process.env 到响应。
 */

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { getDb } = require('./db');

const ALGORITHM = 'RS256';
const EXPIRES_IN = '30d';

/**
 * 签发设备 JWT
 *
 * @param {string} androidId 设备唯一 ID
 * @param {object} [context] CloudBase context(可选)
 * @returns {Promise<{token: string, jti: string, expires_at: Date}>}
 */
async function signDeviceJwt(androidId, context) {
    const privateKey = process.env.DEVICE_JWT_PRIVATE_KEY;
    if (!privateKey) throw new Error('DEVICE_JWT_PRIVATE_KEY not configured');

    const jti = crypto.randomUUID();
    const token = jwt.sign(
        { sub: androidId, kind: 'device' },
        privateKey,
        { algorithm: ALGORITHM, expiresIn: EXPIRES_IN, jwtid: jti }
    );

    const decoded = jwt.decode(token);
    const expiresAt = new Date(decoded.exp * 1000);

    // 持久化 jti(支持后续撤销)
    const db = getDb(context);
    const { error } = await db.from('device_jwts').insert({
        jti,
        android_id: androidId,
        issued_at: new Date().toISOString(),
        expires_at: expiresAt.toISOString(),
    });
    if (error) {
        // ⚠️ [Skill]:不能 echo error 详情,只记日志
        throw new Error('JWT_PERSIST_FAILED');
    }

    return { token, jti, expires_at: expiresAt };
}

/**
 * 校验设备 JWT,返回 claims
 *
 * @param {object} headers HTTP headers 对象(CloudBase 网关会把 header 名转小写)
 * @returns {Promise<{sub: string, id: string, exp: number, iat: number}>}
 * @throws {Error} NO_BEARER / JWT_INVALID / JWT_EXPIRED / JWT_REVOKED
 */
async function verifyDeviceJwt(headers, context) {
    // CloudBase HTTP 网关把 header 名转小写,统一走 lowercase 查找
    const authHeader = headers?.authorization || headers?.Authorization || null;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        const err = new Error('NO_BEARER');
        err.code = 'NO_BEARER';
        throw err;
    }
    const token = authHeader.slice(7);

    const publicKey = process.env.DEVICE_JWT_PUBLIC_KEY;
    if (!publicKey) {
        const err = new Error('SERVER_NO_PUBLIC_KEY');
        err.code = 'SERVER_NO_PUBLIC_KEY';
        throw err;
    }

    let decoded;
    try {
        decoded = jwt.verify(token, publicKey, { algorithms: [ALGORITHM] });
    } catch (e) {
        const err = new Error(`JWT_INVALID:${e.message}`);
        err.code = 'JWT_INVALID';
        throw err;
    }

    if (decoded.kind !== 'device') {
        const err = new Error('JWT_NOT_DEVICE');
        err.code = 'JWT_NOT_DEVICE';
        throw err;
    }

    // 查 device_jwts 表确认未撤销
    const db = getDb(context);
    const { data, error } = await db.from('device_jwts')
        .select('revoked_at, expires_at')
        .eq('jti', decoded.jti)
        .single();

    if (error || !data) {
        const err = new Error('JWT_NOT_FOUND');
        err.code = 'JWT_NOT_FOUND';
        throw err;
    }
    if (data.revoked_at) {
        const err = new Error('JWT_REVOKED');
        err.code = 'JWT_REVOKED';
        throw err;
    }
    if (new Date(data.expires_at) < new Date()) {
        const err = new Error('JWT_EXPIRED');
        err.code = 'JWT_EXPIRED';
        throw err;
    }

    return decoded; // { sub: androidId, jti, iat, exp, kind }
}

/**
 * 撤销 JWT(标记 revoked_at)
 *
 * @param {string} jti
 * @returns {Promise<boolean>}
 */
async function revokeDeviceJwt(jti, context) {
    const db = getDb(context);
    const { error } = await db.from('device_jwts')
        .update({ revoked_at: new Date().toISOString() })
        .eq('jti', jti)
        .is('revoked_at', null);
    return !error;
}

module.exports = { signDeviceJwt, verifyDeviceJwt, revokeDeviceJwt };

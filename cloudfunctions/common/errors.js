/**
 * 统一响应工厂 + 错误码常量
 *
 * 设计原则:
 * - 成功响应: { statusCode: 200, headers, body: JSON.stringify(data) }
 * - 失败响应: { statusCode, headers, body: JSON.stringify({ code, message }) }
 * - 不在响应里 echo process.env / event.headers(Skill: sensitive-runtime-data-protection.md)
 */

const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

/**
 * 成功响应
 */
function ok(data, statusCode = 200, extraHeaders = {}) {
    return {
        statusCode,
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS, ...extraHeaders },
        body: JSON.stringify(data),
    };
}

/**
 * 流式响应(SSE)
 */
function sse(text, extraHeaders = {}) {
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Cache-Control': 'no-cache',
            ...CORS_HEADERS,
            ...extraHeaders,
        },
        body: text,
    };
}

/**
 * 失败响应
 *
 * @param {number} statusCode HTTP 状态码
 * @param {string} code 业务错误码(全大写蛇形)
 * @param {string} [message] 给人看的消息(可省略)
 * @param {object} [extra] 额外字段
 */
function err(statusCode, code, message, extra = {}) {
    const body = { code, ...(message ? { message } : {}), ...extra };
    return {
        statusCode,
        headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        body: JSON.stringify(body),
    };
}

/**
 * 处理 OPTIONS 预检请求
 */
function handleCors(event) {
    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 204,
            headers: CORS_HEADERS,
            body: '',
        };
    }
    return null;
}

/**
 * 安全解析 body(string 或 object 都支持)
 */
function parseBody(event) {
    if (!event.body) return {};
    if (typeof event.body === 'object') return event.body;
    try {
        return JSON.parse(event.body);
    } catch (e) {
        return {};
    }
}

// 业务错误码常量
const ErrorCodes = {
    NO_BEARER: 'NO_BEARER',
    JWT_INVALID: 'JWT_INVALID',
    JWT_EXPIRED: 'JWT_EXPIRED',
    JWT_REVOKED: 'JWT_REVOKED',
    JWT_NOT_FOUND: 'JWT_NOT_FOUND',
    QUOTA_EXHAUSTED: 'QUOTA_EXHAUSTED',
    DEVICE_NOT_FOUND: 'DEVICE_NOT_FOUND',
    DEVICE_BANNED: 'DEVICE_BANNED',
    ATTESTATION_FAILED: 'ATTESTATION_FAILED',
    BAD_REQUEST: 'BAD_REQUEST',
    NOT_FOUND: 'NOT_FOUND',
    INTERNAL: 'INTERNAL',
    LLM_UPSTREAM_ERROR: 'LLM_UPSTREAM_ERROR',
    LLM_API_KEY_NOT_CONFIGURED: 'LLM_API_KEY_NOT_CONFIGURED',
};

module.exports = { ok, err, sse, handleCors, parseBody, ErrorCodes };

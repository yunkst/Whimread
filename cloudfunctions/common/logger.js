/**
 * 结构化日志
 *
 * 设计:
 * - 用 context.logger(CloudBase 原生),自动带 request_id
 * - 不打印完整 request body / header(可能含敏感信息)
 * - 只打印 op 名 + 关键字段(android_id、token jti 等)
 */

/**
 * 统一日志入口
 *
 * @param {object} context CloudBase 函数 context(必须)
 * @param {string} level 'info' | 'warn' | 'error' | 'debug'
 * @param {string} message 简短描述(操作名 + 结果)
 * @param {object} [fields] 关键字段(不要传 body / headers)
 */
function log(context, level, message, fields = {}) {
    if (!context || !context.logger) {
        // 单元测试场景:context 不可用,fallback 到 console
        // eslint-disable-next-line no-console
        console[level === 'debug' ? 'log' : level](`[${level}] ${message}`, fields);
        return;
    }
    const logger = context.logger;
    const tag = Object.entries(fields).map(([k, v]) => `${k}=${v}`).join(' ');
    const fullMessage = tag ? `${message} ${tag}` : message;

    switch (level) {
        case 'debug':
            if (logger.debug) logger.debug(fullMessage);
            break;
        case 'info':
            logger.info(fullMessage);
            break;
        case 'warn':
            logger.warn(fullMessage);
            break;
        case 'error':
            logger.error(fullMessage);
            break;
        default:
            logger.info(fullMessage);
    }
}

const info = (context, msg, fields) => log(context, 'info', msg, fields);
const warn = (context, msg, fields) => log(context, 'warn', msg, fields);
const error = (context, msg, fields) => log(context, 'error', msg, fields);
const debug = (context, msg, fields) => log(context, 'debug', msg, fields);

module.exports = { log, info, warn, error, debug };

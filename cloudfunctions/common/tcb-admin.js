/**
 * CloudBase 管理面 TC3 调用封装(ExecutePGSql)
 *
 * 背景:
 *   CloudBase JS SDK 3.18.3 在 Event Function 内调用 PG REST 失败(spec §12.1);
 *   PG REST 网关也不接受 service_role API Key(INVALID_CREDENTIALS)。
 *   可用 admin 路径只有 Tencent Cloud API v3 控制面的 tcb.ExecutePGSql。
 *
 * 关键发现(2026-09-08 探针验证):
 *   SCF 运行时**完整暴露**:
 *     TENCENTCLOUD_SECRETID、TENCENTCLOUD_SECRETKEY、TENCENTCLOUD_SESSIONTOKEN、TENCENTCLOUD_REGION
 *   加上用户注入的 TCB_ENV_ID,就可以签 TC3-HMAC-SHA256 请求直接调 ExecutePGSql,
 *   绕过 PG REST 网关鉴权,以 cloudbase_postgres_pgdb_* 角色执行(拥有 PG 表全部权限,
 *   因为 spec §12.5 grant service_role 已下发)。
 *
 * 安全约束:
 *   - 不要 echo 凭据 / response body 全部内容到日志或响应(skill sensitive-runtime-data-protection)
 *   - 失败时只暴露前 200 字节错误体
 *
 * 性能:
 *   - 每次 invocation 内调用 N 次 executePGSql,签名密钥派生会重复做;不在跨 invocation 间
 *     缓存(SCF 每次冷启动换 SESSIONTOKEN)
 *   - 业务层用 Promise.all 并发多个独立操作来摊销延迟
 */

'use strict';

const crypto = require('crypto');

const TCB_SERVICE = 'tcb';
const TCB_VERSION = '2018-06-08';
const TCB_HOST = `${TCB_SERVICE}.tencentcloudapi.com`;
const TCB_ENDPOINT = `https://${TCB_HOST}`;

function sha256hex(s) {
    return crypto.createHash('sha256').update(s).digest('hex');
}

/**
 * TC3-HMAC-SHA256 签名(腾讯云 API v3 标准流程)
 *
 * 文档:https://cloud.tencent.com/document/api/1724/101843
 */
function tc3Sign(secretId, secretKey, service, region, action, payload, timestamp) {
    const httpRequestMethod = 'POST';
    const canonicalUri = '/';
    const canonicalQueryString = '';
    const ct = 'application/json; charset=utf-8';
    const canonicalHeaders =
 `content-type:${ct}\nhost:${TCB_HOST}\nx-tc-action:${action.toLowerCase()}\nx-tc-region:${region}\n`;
    const signedHeaders = 'content-type;host;x-tc-action;x-tc-region';
    const hashedRequestPayload = sha256hex(payload);

    const canonicalRequest =
 `${httpRequestMethod}\n${canonicalUri}\n${canonicalQueryString}\n` +
 `${canonicalHeaders}\n${signedHeaders}\n${hashedRequestPayload}`;
    const date = new Date(timestamp * 1000).toISOString().slice(0, 10);
    const credentialScope = `${date}/${service}/tc3_request`;
    const stringToSign = `TC3-HMAC-SHA256\n${timestamp}\n${credentialScope}\n` +
 `${sha256hex(canonicalRequest)}`;

    const secretDate = crypto.createHmac('sha256', `TC3${secretKey}`).update(date).digest();
    const secretService = crypto.createHmac('sha256', secretDate).update(service).digest();
    const secretSigning = crypto.createHmac('sha256', secretService).update('tc3_request').digest();
    const signature = crypto.createHmac('sha256', secretSigning).update(stringToSign).digest('hex');

    return {
        authorization: `TC3-HMAC-SHA256 Credential=${secretId}/${credentialScope}, ` +
 `SignedHeaders=${signedHeaders}, Signature=${signature}`,
        date,
    };
}

/**
 * 检查 SCF 凭据 + EnvId 是否齐全,返回缺失列表
 */
function missingCreds() {
    const missing = [];
    if (!process.env.TENCENTCLOUD_SECRETID) missing.push('TENCENTCLOUD_SECRETID');
    if (!process.env.TENCENTCLOUD_SECRETKEY) missing.push('TENCENTCLOUD_SECRETKEY');
    if (!process.env.TCB_ENV_ID) missing.push('TCB_ENV_ID');
    return missing;
}

/**
 * 执行 tcb.ExecutePGSql
 *
 * @param {string} sql 原始 SQL(必须参数化,不要字符串拼接值)
 * @returns {Promise<{rows: any[], fields: string[], rowCount: number, affectedRows: number, executionTimeMs: number, raw: object}>}
 * @throws {Error} code 字段标识失败原因(NO_CREDS / PG_SQL_FAILED / HTTP_ERROR)
 */
async function executePGSql(sql) {
    const missing = missingCreds();
    if (missing.length > 0) {
        const e = new Error(`Missing runtime creds: ${missing.join(', ')}`);
        e.code = 'NO_CREDS';
        throw e;
    }

    const secretId = process.env.TENCENTCLOUD_SECRETID;
    const secretKey = process.env.TENCENTCLOUD_SECRETKEY;
    const sessionToken = process.env.TENCENTCLOUD_SESSIONTOKEN || '';
    const region = process.env.TENCENTCLOUD_REGION || 'ap-shanghai';
    const envId = process.env.TCB_ENV_ID;
    const action = 'ExecutePGSql';

    const payload = JSON.stringify({ EnvId: envId, Sql: sql });
    const timestamp = Math.floor(Date.now() / 1000);
    const { authorization } = tc3Sign(secretId, secretKey, TCB_SERVICE, region, action, payload, timestamp);

    const headers = {
        'Authorization': authorization,
        'Content-Type': 'application/json; charset=utf-8',
        'Host': TCB_HOST,
        'X-TC-Action': action,
        'X-TC-Version': TCB_VERSION,
        'X-TC-Timestamp': timestamp,
        'X-TC-Region': region,
    };
    if (sessionToken) headers['X-TC-Token'] = sessionToken;

    let resp;
    try {
        resp = await fetch(TCB_ENDPOINT, {
            method: 'POST',
            headers,
            body: payload,
        });
    } catch (e) {
        const err = new Error(`ExecutePGSql fetch failed: ${e.message}`);
        err.code = 'HTTP_ERROR';
        throw err;
    }

    const respText = await resp.text();
    let body;
    try {
        body = JSON.parse(respText);
    } catch (e) {
        const err = new Error(`ExecutePGSql non-JSON (HTTP ${resp.status}): ${respText.slice(0, 200)}`);
        err.code = 'HTTP_ERROR';
        throw err;
    }

    if (!resp.ok || body.Response?.Error) {
        const apiErr = body.Response?.Error || body;
        const err = new Error(
            `ExecutePGSql failed: ${apiErr.Code || 'unknown'} ${apiErr.Message || ''}`.trim()
        );
        err.code = 'PG_SQL_FAILED';
        err.pgCode = apiErr.Code;
        err.httpStatus = resp.status;
        throw err;
    }

    const r = body.Response || {};
    // PG 行以 PG 数组字面量字符串返回,例:'["1", "cloudbase_postgres_pgdb_xxx"]'
    // 这里按"字符串数组"原样吐出,业务层用 parseRow 还原
    return {
        rows: Array.isArray(r.Rows) ? r.Rows : [],
        fields: Array.isArray(r.Columns) ? r.Columns : [],
        rowCount: Array.isArray(r.Rows) ? r.Rows.length : 0,
        affectedRows: r.AffectedRows || 0,
        executionTimeMs: r.ExecutionTimeMs || 0,
        raw: r,
    };
}

/**
 * 解析 PG ExecutePGSql 返回的 Row 字符串
 *
 * PG 驱动把行序列化为字符串数组(`["col1_val", "col2_val"]`),
 * 但某些类型(int4 / numeric / bool)走 JSON.stringify 时不带引号,需要混合解析。
 * 简单粗暴:直接 JSON.parse,失败时整体当字符串返回。
 */
function parseRow(rowStr, fields) {
    if (typeof rowStr !== 'string') return rowStr;
    try {
        const arr = JSON.parse(rowStr);
        if (!Array.isArray(arr) || arr.length !== fields.length) return rowStr;
        const obj = {};
        for (let i = 0; i < fields.length; i++) {
            obj[fields[i]] = arr[i];
        }
        return obj;
    } catch {
        return rowStr;
    }
}

/**
 * 把 executePGSql 返回的 rows 转换为字段名 → 值 的对象数组
 */
function rowsToObjects(result) {
    const { rows, fields } = result;
    return rows.map((rowStr) => parseRow(rowStr, fields));
}

module.exports = {
    executePGSql,
    rowsToObjects,
    parseRow,
    // 暴露给单测
    _tc3Sign: tc3Sign,
    _missingCreds: missingCreds,
};
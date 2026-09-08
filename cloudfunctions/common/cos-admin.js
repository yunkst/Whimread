/**
 * CloudBase Storage 上传封装(走 COS 管理面 API,绕开 @cloudbase/node-sdk 在
 * Event Function 内的 storage 模块不通问题,跟 tcb-admin.js 一致的设计思路)。
 *
 * 用途:
app-release 函数 POST /publish 时,把 multipart 收到的 APK buffer 推到
 * CloudBase Storage 对应的 bucket,返回 storage_url(给 Flutter 端下载)。
 *
 * 关键发现(2026-09-08 探针验证):
 *   SCF 运行时**完整暴露**:
 *     TENCENTCLOUD_SECRETID、TENCENTCLOUD_SECRETKEY、TENCENTCLOUD_SESSIONTOKEN、TENCENTCLOUD_REGION
 *   + 用户注入的 TCB_ENV_ID + 目标 bucket,就能用 TC3 签 cos.PutObject 直接
 *   PUT APK 到 CloudBase Storage,无需 server SDK。
 *
 * 鉴权说明:
 *   cos.PutObject 用 SCF 的 SCF_QcsRole / TCB_QcsRole,需 bucket policy 允许
 *   当前 role 写入(或 cos 上设为 public-write 仅限 dev,生产用临时 token)。
 *   当前 whimread-dev 设为「storage ACL = 私有读写」,所以 cos API 需要走
 *   有写权限的 role。本实现直接用 SCF 运行时默认 role,需要先确认 bucket
 *   对 TCB_QcsRole 开了写权限(见 managePermissions 调 storage permission)。
 *
 * 安全约束:
 *   - 不 echo 凭据 / 签名
 *   - 文件 SHA256 由调用方计算并写入 PG,这里只负责上传
 */

'use strict';

const crypto = require('crypto');

const COS_VERSION = '2025-11-12';

function sha256hex(s) {
    return crypto.createHash('sha256').update(s).digest('hex');
}

/**
 * TC3-HMAC-SHA256 签名(COS PutObject)
 *
 * 文档:https://cloud.tencent.com/document/api/436/7753
 */
function tc3SignCos(secretId, secretKey, action, payload, timestamp, opts = {}) {
    const region = opts.region || 'ap-shanghai';
    const host = opts.host; // 如 `<bucket>-<appid>.cos.<region>.myqcloud.com`
    const contentType = opts.contentType || 'application/octet-stream';
    const service = 'cos';
    const httpRequestMethod = opts.method || 'PUT';
    const canonicalUri = opts.canonicalUri || '/';
    const canonicalQueryString = opts.canonicalQueryString || '';

    // 注意: COS PutObject 用 x-tc-action 时,**payload hash 走 x-tc-content-sha256**
    // 而不是 SHA256(payload)(payload 可能很大,无法 inline)
    const payloadHash = opts.payloadSha256 || sha256hex(payload);

    const canonicalHeaders =
 `content-type:${contentType}\nhost:${host}\nx-tc-action:${action.toLowerCase()}\n`;
    const signedHeaders = 'content-type;host;x-tc-action';
    const hashedRequestPayload = payloadHash;

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

    return `TC3-HMAC-SHA256 Credential=${secretId}/${credentialScope}, ` +
 `SignedHeaders=${signedHeaders}, Signature=${signature}`;
}

/**
 * 上传一个对象到 CloudBase Storage
 *
 * @param {object} params
 * @param {string} params.bucket         bucket 名(如 `7768-whimread-dev-d0gm4oi0z3099082d-1256733196`)
 * @param {string} params.appId          env 对应的 AppId(从 env vars 推不出,需要从 DesribeEnvs 拿)
 * @param {string} params.key            对象 key(如 `app-releases/v3.0.0-preview.1/app-arm64-v8a-release.apk`)
 * @param {Buffer} params.body           文件内容
 * @param {string} [params.contentType]  默认 application/octet-stream
 * @returns {Promise<{key: string, url: string, size: number}>}
 * @throws {Error} NO_CREDS / PUT_FAILED / HTTP_ERROR
 */
async function putObject({ bucket, appId, key, body, contentType = 'application/octet-stream' }) {
    const missing = [];
    if (!process.env.TENCENTCLOUD_SECRETID) missing.push('TENCENTCLOUD_SECRETID');
    if (!process.env.TENCENTCLOUD_SECRETKEY) missing.push('TENCENTCLOUD_SECRETKEY');
    if (!appId) missing.push('appId');
    if (!bucket) missing.push('bucket');
    if (!key) missing.push('key');
    if (missing.length > 0) {
        const e = new Error(`putObject missing: ${missing.join(', ')}`);
        e.code = 'NO_CREDS';
        throw e;
    }

    const region = process.env.TENCENTCLOUD_REGION || 'ap-shanghai';
    const sessionToken = process.env.TENCENTCLOUD_SESSIONTOKEN || '';
    const host = `${bucket}-${appId}.cos.${region}.myqcloud.com`;
    const url = `https://${host}/${key.split('/').map(encodeURIComponent).join('/')}`;

    const action = 'PutObject';
    const timestamp = Math.floor(Date.now() / 1000);
    const payloadHash = sha256hex(body);
    const authorization = tc3SignCos(
        process.env.TENCENTCLOUD_SECRETID,
        process.env.TENCENTCLOUD_SECRETKEY,
        action,
        body,
        timestamp,
        { region, host, contentType, payloadSha256: payloadHash, method: 'PUT', canonicalUri: `/${encodeURIComponent(key)}` }
    );

    const headers = {
        'Authorization': authorization,
        'Host': host,
        'Content-Type': contentType,
        'Content-Length': String(body.length),
        'X-TC-Action': action,
        'X-TC-Timestamp': timestamp,
        'X-TC-Version': COS_VERSION,
        'X-TC-RequestUrl': url,
    };
    if (sessionToken) headers['X-TC-Token'] = sessionToken;

    let resp;
    try {
        resp = await fetch(url, {
            method: 'PUT',
            headers,
            body,
        });
    } catch (e) {
        const err = new Error(`putObject fetch failed: ${e.message}`);
        err.code = 'HTTP_ERROR';
        throw err;
    }

    if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        const err = new Error(`putObject failed (HTTP ${resp.status}): ${text.slice(0, 200)}`);
        err.code = 'PUT_FAILED';
        err.httpStatus = resp.status;
        throw err;
    }

    return {
        key,
        url: `https://${host}/${key.split('/').map(encodeURIComponent).join('/')}`,
        size: body.length,
    };
}

/**
 * 生成 COS 预签名 PUT URL(XML API sha1 签名)
 *
 * 用途:CI 先调 /publish/init 拿预签名 URL,再直接 PUT APK 到 COS,
 *      从而绕开 HTTP 网关 6MB body 限制(EXCEED_MAX_PAYLOAD_SIZE),
 *      且 GitHub 侧不需要持有任何腾讯云密钥 —— URL 本身就是限时授权。
 *
 * 签名格式(腾讯云 COS XML API):
 *   https://<bucket>.cos.<region>.myqcloud.com/<key>
 *     ?q-sign-algorithm=sha1&q-ak=<SecretId>&q-sign-time=<t1>;<t2>
 *     &q-key-time=<t1>;<t2>&q-header-list=&q-url-param-list=&q-signature=<sig>
 *
 *   SignKey      = Hex(HMAC-SHA1(SecretKey, KeyTime))
 *   HttpString   = "put\n<UriPathname>\n\n\n"(header/param 列表为空)
 *   StringToSign = "sha1\n<KeyTime>\n<Sha1Hex(HttpString)>\n"
 *   Signature    = Hex(HMAC-SHA1(SignKey, StringToSign))
 *
 * 文档:https://cloud.tencent.com/document/product/436/7778(签名)、7776(预签名 URL)
 *
 * @param {object} p
 * @param {string} p.bucket     bucket 名(如 7768-whimread-dev-xxx-1256733196)
 * @param {string} p.key        对象 key(如 app-releases/v1/app.apk)
 * @param {number} [p.expiresSec] 有效期,默认 1800(30 分钟,足够 100MB 上传)
 * @returns {string} 完整可 PUT 的预签名 URL
 * @throws {Error} NO_CREDS
 */
function signPutUrl({ bucket, key, expiresSec = 1800 }) {
    const secretId = process.env.TENCENTCLOUD_SECRETID;
    const secretKey = process.env.TENCENTCLOUD_SECRETKEY;
    if (!secretId || !secretKey) {
        const e = new Error('Missing TENCENTCLOUD_SECRETID/SECRETKEY');
        e.code = 'NO_CREDS';
        throw e;
    }
    const region = process.env.TENCENTCLOUD_REGION || 'ap-shanghai';
    const host = `${bucket}.cos.${region}.myqcloud.com`;

    // UriPathname:URL 编码但保留 '/'
    const pathname = key.split('/').map(encodeURIComponent).join('/');
    const now = Math.floor(Date.now() / 1000);
    const keyTime = `${now};${now + expiresSec}`;

    const signKey = crypto.createHmac('sha1', secretKey).update(keyTime).digest('hex');
    const httpString = `put\n/${pathname}\n\n\n`;
    const sha1edHttp = crypto.createHash('sha1').update(httpString).digest('hex');
    const stringToSign = `sha1\n${keyTime}\n${sha1edHttp}\n`;
    const signature = crypto.createHmac('sha1', signKey).update(stringToSign).digest('hex');

    const q = [
        'q-sign-algorithm=sha1',
        `q-ak=${encodeURIComponent(secretId)}`,
        `q-sign-time=${keyTime}`,
        `q-key-time=${keyTime}`,
        'q-header-list=',
        'q-url-param-list=',
        `q-signature=${signature}`,
    ].join('&');

    return `https://${host}/${pathname}?${q}`;
}

/**
 * 拼公开读 URL(tcb.qcloud.la CDN 域名,bucket 需开公有读)
 *
 * 实测(2026-09-08):tcb.qcloud.la 匿名 200;cos.myqcloud.com 直链本地网络不通
 */
function publicUrl(bucket, key) {
    return `https://${bucket}.tcb.qcloud.la/${key.split('/').map(encodeURIComponent).join('/')}`;
}

module.exports = {
    signPutUrl,
    publicUrl,
    putObject,
    // 暴露给单测
    _tc3SignCos: tc3SignCos,
    _sha256hex: sha256hex,
};
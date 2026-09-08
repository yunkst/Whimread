/**
 * Whimread app-release 云函数
 *
 * 路由:
 *   GET  /api/v1/app/releases/latest?channel=stable|preview   客户端拉取最新版本
 *   POST /api/admin/app/releases/publish                     GitHub Actions 发布入口(JSON-only)
 *
 * 设计:
 *   - GET 公开,从 PG app_releases + app_release_files 联表读
 *   - POST 需 X-API-TOKEN,接收 JSON,不再走 multipart
 *     (Event Function HTTP body 1MB 限制,APK 90MB 不能 multipart 上传)
 *   - APK 上传由 CI(flutter-release.yml)用 cos-python-sdk-v5 + TC3 签名直接推到
 *     CloudBase Storage,这里只写 PG + 验证 storage_url 可达
 *
 * 数据流(发布):
 *   GitHub Actions:
 *     1. flutter build apk → 3 个 split-per-abi APK
 *     2. sha256sum → APK SHA256
 *     3. cos.PutObject(每个 APK)→ 拿到 storage_key + storage_url
 *     4. POST JSON {version, versionCode, channel, changelog, files:[...]} →
 *        CloudBase app-release /api/admin/app/releases/publish
 *     5. PG:INSERT app_releases + app_release_files,UPDATE 同 channel 旧 active = false
 *
 * 安全:
 *   - POST 需 X-API-TOKEN,值与 GitHub Secret WHIMREAD_BACKEND_TOKEN 同步
 *   - 不 echo process.env / event.headers / 上传文件内容
 */

const { ok, err, handleCors, ErrorCodes } = require('./common/errors');
const { getDb } = require('./common/db');
const {
    initiateMultipartUpload,
    uploadPart,
    completeMultipartUpload,
    publicUrl,
} = require('./common/cos-admin');
const logger = require('./common/logger');

exports.main = async (event, context) => {
    const corsResp = handleCors(event);
    if (corsResp) return corsResp;

    const method = event.httpMethod || 'GET';
    const rawPath = (event.path || '').split('?')[0].replace(/\/+$/, '');
    const route = rawPath.split('/').pop() || '';

    try {
        if (method === 'GET' && route === 'latest') {
            return await handleLatest(event, context);
        }
        if (method === 'POST' && route === 'publish') {
            return await handlePublish(event, context);
        }
        if (method === 'POST' && route === 'init') {
            return await handleInit(event, context);
        }
        if (method === 'POST' && route === 'chunk') {
            return await handleChunk(event, context);
        }
        if (method === 'POST' && route === 'finalize') {
            return await handleFinalize(event, context);
        }
        return err(404, ErrorCodes.NOT_FOUND, `Unknown route: ${method} ${rawPath}`);
    } catch (e) {
        logger.error(context, `app-release uncaught: ${e.message}`, { code: e.code });
        if (e.code === 'NOT_IMPLEMENTED') {
            return err(503, 'PG_NOT_AVAILABLE', e.message);
        }
        return err(500, ErrorCodes.INTERNAL, 'Internal error');
    }
};

// ============================================================
// GET /api/v1/app/releases/latest?channel=stable|preview
// ============================================================
async function handleLatest(event, context) {
    const db = getDb(context);

    const params = event.queryStringParameters || {};
    const channel = (params.channel || 'stable').toLowerCase();
    if (channel !== 'stable' && channel !== 'preview') {
        return err(400, ErrorCodes.BAD_REQUEST, 'channel must be "stable" or "preview"');
    }

    let release = null;
    if (channel === 'preview') {
        const data = await queryLatestActive(db, ['stable', 'preview']);
        release = data[0] || null;
    } else {
        const data = await queryLatestActive(db, ['stable']);
        release = data[0] || null;
    }

    if (!release) {
        logger.warn(context, 'no active release for channel', { channel });
        return ok({
            version: null,
            versionCode: 0,
            channel,
            changelog: '',
            publishedAt: '',
            files: [],
        });
    }

    const fileRows = await queryFiles(db, release.id);

    const files = fileRows.map((f) => ({
        abi: f.abi,
        filename: f.filename,
        size: Number(f.size_bytes),
        sha256: f.sha256,
        url: f.storage_url,
    }));

    logger.info(context, 'app release served', {
        version: release.version,
        build: release.build,
        channel: release.channel,
        files: files.length,
    });

    return ok({
        version: release.version,
        versionCode: release.build,
        channel: release.channel,
        changelog: release.release_notes || '',
        publishedAt: release.published_at,
        files,
    });
}

async function queryLatestActive(db, channels) {
    const { data } = await db.from('app_releases')
        .select('id, version, build, download_url, release_notes, force_update, min_supported_version, published_at, channel')
        .eq('is_active', true)
        .in('channel', channels)
        .order('published_at', { ascending: false })
        .limit(1)
        .single();
    return data ? [data] : [];
}

async function queryFiles(db, releaseId) {
    const { data } = await db.from('app_release_files')
        .select('abi, filename, size_bytes, sha256, storage_url')
        .eq('release_id', Number(releaseId));
    return data || [];
}

// ============================================================
// POST /api/admin/app/releases/publish
// Header: X-API-TOKEN
// Body: JSON
// {
//   "version": "3.0.0-preview.1",
//   "versionCode": 120,
//   "channel": "preview" | "stable",
//   "changelog": "...",
//   "forceUpdate": false,
//   "minSupportedVersion": "2.0.0",
//   "files": [
//     {
//       "abi": "arm64-v8a",
//       "filename": "app-arm64-v8a-release.apk",
//       "size": 93100000,
//       "sha256": "<hex>",
//       "storageKey": "app-releases/3.0.0-preview.1/app-arm64-v8a-release.apk",
//       "storageUrl": "https://<bucket>-<appId>.cos.<region>.myqcloud.com/app-releases/..."
//     }
//   ]
// }
// ============================================================
async function handlePublish(event, context) {
    // 1. token 校验
    const expected = process.env.PUBLISH_API_TOKEN;
    if (!expected) {
        logger.error(context, 'PUBLISH_API_TOKEN not configured');
        return err(500, ErrorCodes.INTERNAL, 'Server misconfigured');
    }
    const got = event.headers?.['x-api-token'] || event.headers?.['X-API-Token'] || '';
    if (got !== expected) {
        logger.warn(context, 'publish token mismatch');
        return err(401, 'UNAUTHORIZED', 'Invalid or missing X-API-TOKEN');
    }

    // 2. 解析 JSON
    const raw = parseBody(event);
    if (!raw || typeof raw !== 'object') {
        return err(400, ErrorCodes.BAD_REQUEST, 'request body must be JSON object');
    }

    // 4. 验证必填字段
    if (!raw.version || !raw.versionCode || !raw.channel) {
        return err(400, ErrorCodes.BAD_REQUEST, 'body.{version, versionCode, channel} required');
    }
    if (!['stable', 'preview'].includes(raw.channel)) {
        return err(400, ErrorCodes.BAD_REQUEST, 'body.channel must be "stable" or "preview"');
    }
    if (!Array.isArray(raw.files) || raw.files.length === 0) {
        return err(400, ErrorCodes.BAD_REQUEST, 'body.files must be non-empty array');
    }

    // 5. 验证每个 file 字段
    const uploadedFiles = [];
    for (const f of raw.files) {
        if (!f.abi || !f.filename || !f.size || !f.sha256 || !f.storageKey || !f.storageUrl) {
            return err(400, ErrorCodes.BAD_REQUEST,
                `each file must have {abi, filename, size, sha256, storageKey, storageUrl}, missing in ${JSON.stringify(f)}`);
        }
        if (!/^[a-f0-9]{64}$/i.test(f.sha256)) {
            return err(400, ErrorCodes.BAD_REQUEST, `sha256 not 64 hex chars: ${f.sha256}`);
        }
        if (typeof f.size !== 'number' || f.size <= 0) {
            return err(400, ErrorCodes.BAD_REQUEST, `size must be positive number: ${f.size}`);
        }
        uploadedFiles.push({
            abi: f.abi,
            filename: f.filename,
            size: Number(f.size),
            sha256: f.sha256.toLowerCase(),
            storageKey: f.storageKey,
            storageUrl: f.storageUrl,
        });
    }

    logger.info(context, 'publish received', {
        version: raw.version,
        channel: raw.channel,
        fileCount: uploadedFiles.length,
    });

    // 6. 写 PG
    const db = getDb(context);

    // 6a. 把同 channel 的旧 active release 全部置 inactive
    const { error: deactivateErr } = await db.from('app_releases')
        .update({ is_active: false })
        .eq('channel', raw.channel)
        .eq('is_active', true);
    if (deactivateErr) {
        logger.error(context, `deactivate old releases failed: ${deactivateErr.message}`);
        return err(500, ErrorCodes.INTERNAL, `deactivate old releases failed`);
    }

    // 6b. 插入新 release
    const { error: insertErr } = await db.from('app_releases')
        .insert({
            version: raw.version,
            build: Number(raw.versionCode),
            download_url: uploadedFiles[0]?.storageUrl || '',
            release_notes: raw.changelog || '',
            force_update: !!raw.forceUpdate,
            min_supported_version: raw.minSupportedVersion || null,
            is_active: true,
            channel: raw.channel,
        });
    if (insertErr) {
        logger.error(context, `insert release failed: ${insertErr.message}`);
        return err(500, ErrorCodes.INTERNAL, `insert release failed: ${insertErr.message}`);
    }

    // 6b2. 用 (version, build, channel) 拿自增 id(这三个字段在 app_releases 上
    // 有 idx_app_releases_version_build 唯一索引,O(1) 查回)
    const { data: idRows, error: idErr } = await db.from('app_releases')
        .select('id')
        .eq('version', raw.version)
        .eq('build', Number(raw.versionCode))
        .eq('channel', raw.channel)
        .limit(1)
        .single();
    if (idErr || !idRows || !idRows.id) {
        logger.error(context, `lookup release id failed: ${idErr?.message}`);
        return err(500, ErrorCodes.INTERNAL, `lookup release id failed`);
    }
    const releaseId = idRows.id;

    // 6c. 插入 file 行
    for (const f of uploadedFiles) {
        const { error: fileInsertErr } = await db.from('app_release_files')
            .insert({
                release_id: Number(releaseId),
                abi: f.abi,
                filename: f.filename,
                size_bytes: f.size,
                sha256: f.sha256,
                storage_key: f.storageKey,
                storage_url: f.storageUrl,
            });
        if (fileInsertErr) {
            logger.error(context, `insert file ${f.abi} failed: ${fileInsertErr.message}`);
            return err(500, ErrorCodes.INTERNAL, `insert file failed: ${fileInsertErr.message}`);
        }
    }

    logger.info(context, 'publish complete', {
        version: raw.version,
        channel: raw.channel,
        releaseId,
        fileCount: uploadedFiles.length,
    });

    return ok({
        releaseId: Number(releaseId),
        version: raw.version,
        channel: raw.channel,
        files: uploadedFiles.map((f) => ({ abi: f.abi, url: f.storageUrl })),
    });
}

// ============================================================
// POST /api/admin/app/releases/chunk
// Header: X-API-TOKEN
// Query: key=<storageKey>&uploadId=<id>&partNumber=<N>
// Body: 原始二进制(≤ 5MB,SCF event 上限 6MB)
// Resp: { etag }
// ============================================================
async function handleChunk(event, context) {
    const expected = process.env.PUBLISH_API_TOKEN;
    if (!expected) return err(500, ErrorCodes.INTERNAL, 'Server misconfigured');
    const got = event.headers?.['x-api-token'] || event.headers?.['X-API-Token'] || '';
    if (got !== expected) {
        return err(401, 'UNAUTHORIZED', 'Invalid or missing X-API-TOKEN');
    }

    const bucket = process.env.STORAGE_BUCKET;
    if (!bucket) return err(500, ErrorCodes.INTERNAL, 'STORAGE_BUCKET not configured');

    // SCF 网关会把 query 拆进 queryStringParameters
    const params = event.queryStringParameters || {};
    const key = params.key;
    const uploadId = params.uploadId;
    const partNumber = parseInt(params.partNumber, 10);
    if (!key || !uploadId || !partNumber || partNumber < 1 || partNumber > 10000) {
        return err(400, ErrorCodes.BAD_REQUEST, 'query {key, uploadId, partNumber} required (1..10000)');
    }

    let bodyBuf;
    if (event.body == null) {
        return err(400, ErrorCodes.BAD_REQUEST, 'empty body');
    }
    bodyBuf = Buffer.isBuffer(event.body)
        ? event.body
        : Buffer.from(event.body, event.isBase64Encoded ? 'base64' : 'utf8');
    if (bodyBuf.length === 0) {
        return err(400, ErrorCodes.BAD_REQUEST, 'empty chunk');
    }
    if (bodyBuf.length > 3 * 1024 * 1024) {
        return err(413, 'PAYLOAD_TOO_LARGE', 'chunk must be <= 3MB');
    }

    let etag;
    try {
        etag = await uploadPart({ bucket, key, uploadId, partNumber, body: bodyBuf });
    } catch (e) {
        logger.error(context, `uploadPart ${partNumber} failed: ${e.message}`, { code: e.code });
        return err(502, 'COS_UPLOAD_FAILED', `part ${partNumber}: ${e.message.slice(0, 200)}`);
    }

    return ok({ partNumber, etag, size: bodyBuf.length });
}

// ============================================================
// POST /api/admin/app/releases/finalize
// Header: X-API-TOKEN
// Body: { key, uploadId, parts: [{partNumber, etag}] }
// Resp: { ok: true }
// ============================================================
async function handleFinalize(event, context) {
    const expected = process.env.PUBLISH_API_TOKEN;
    if (!expected) return err(500, ErrorCodes.INTERNAL, 'Server misconfigured');
    const got = event.headers?.['x-api-token'] || event.headers?.['X-API-Token'] || '';
    if (got !== expected) {
        return err(401, 'UNAUTHORIZED', 'Invalid or missing X-API-TOKEN');
    }

    const bucket = process.env.STORAGE_BUCKET;
    if (!bucket) return err(500, ErrorCodes.INTERNAL, 'STORAGE_BUCKET not configured');

    const raw = parseBody(event);
    if (!raw || !raw.key || !raw.uploadId || !Array.isArray(raw.parts) || raw.parts.length === 0) {
        return err(400, ErrorCodes.BAD_REQUEST, 'body {key, uploadId, parts[]} required');
    }

    try {
        await completeMultipartUpload({
            bucket, key: raw.key, uploadId: raw.uploadId,
            parts: raw.parts.map((p) => ({ partNumber: Number(p.partNumber), etag: p.etag })),
        });
    } catch (e) {
        logger.error(context, `finalize failed: ${e.message}`, { code: e.code });
        return err(502, 'COS_FINALIZE_FAILED', e.message.slice(0, 200));
    }

    logger.info(context, 'finalize ok', { key: raw.key, parts: raw.parts.length });
    return ok({ key: raw.key, publicUrl: publicUrl(bucket, raw.key) });
}

function parseBody(event) {
    if (!event.body) return {};
    if (typeof event.body === 'object') return event.body;
    try {
        return JSON.parse(event.body);
    } catch {
        return null;
    }
}

// ============================================================
// POST /api/admin/app/releases/init
// Header: X-API-TOKEN
// Body: { version, channel, files: [{abi, filename, size, sha256}] }
// Resp: { files: [{abi, filename, storageKey, uploadId}], expiresAt }
//
// 流程(分片上传,零腾讯云密钥在 CI):
//   1. CI 调 /init,云函数对每个 APK 调 COS InitiateMultipartUpload 拿 uploadId
//   2. CI 把 APK 切成 5MB 分片,逐片 POST /chunk?key=...&uploadId=...&partNumber=N
//      (云函数用 SCF runtime STS 凭据调 COS UploadPart)
//   3. CI 调 /finalize 汇总 parts 让 COS 合并
//   4. CI 调 /publish JSON 写 PG
// ============================================================
async function handleInit(event, context) {
    const expected = process.env.PUBLISH_API_TOKEN;
    if (!expected) {
        return err(500, ErrorCodes.INTERNAL, 'Server misconfigured');
    }
    const got = event.headers?.['x-api-token'] || event.headers?.['X-API-Token'] || '';
    if (got !== expected) {
        return err(401, 'UNAUTHORIZED', 'Invalid or missing X-API-TOKEN');
    }

    const raw = parseBody(event);
    if (!raw || !raw.version || !raw.channel || !Array.isArray(raw.files) || raw.files.length === 0) {
        return err(400, ErrorCodes.BAD_REQUEST, 'body {version, channel, files[]} required');
    }
    if (!['stable', 'preview'].includes(raw.channel)) {
        return err(400, ErrorCodes.BAD_REQUEST, 'channel must be stable|preview');
    }

    const bucket = process.env.STORAGE_BUCKET;
    if (!bucket) {
        return err(500, ErrorCodes.INTERNAL, 'STORAGE_BUCKET not configured');
    }

    const files = [];
    try {
        for (const f of raw.files) {
            if (!f.abi || !f.filename) {
                throw new Error('each file must have {abi, filename}');
            }
            const storageKey = `app-releases/${raw.version}/${f.filename}`;
            const uploadId = await initiateMultipartUpload({
                bucket, key: storageKey,
                contentType: 'application/vnd.android.package-archive',
            });
            files.push({
                abi: f.abi,
                filename: f.filename,
                storageKey,
                uploadId,
            });
        }
    } catch (e) {
        logger.error(context, `init multipart failed: ${e.message}`, { code: e.code });
        return err(502, 'COS_INIT_FAILED', e.message.slice(0, 200));
    }

    logger.info(context, 'publish init (multipart)', {
        version: raw.version,
        channel: raw.channel,
        fileCount: files.length,
    });

    return ok({
        version: raw.version,
        channel: raw.channel,
        files,
    });
}
/**
 * Whimread llm-proxy 云函数
 *
 * 路由:POST /v1/chat/completions(OpenAI 兼容)
 *
 * 工作流:
 *   1. 验证设备 JWT → android_id
 *   2. 配额预检:balance >= 1
 *   3. 读环境变量 LLM_BASE_URL / LLM_API_KEY(运营方持有)
 *   4. 转发到上游 LLM,带 Authorization: Bearer LLM_API_KEY
 *   5. 非流式:读 usage.total_tokens → 算 cost → 扣减 + 写 quota_changes
 *   6. 流式:解析最后一个 SSE chunk 的 usage → 扣减
 *   7. 透传响应给前端
 *
 * ⚠️ [Skill: cloud-functions/SKILL.md] 不能 echo process.env / event.headers
 * ⚠️ [判断] Event Function 网关会缓冲整个 body 再返回,流式退化为"伪流式"
 */

const { ok, err, sse, handleCors, parseBody, ErrorCodes } = require('./common/errors');
const { getDb } = require('./common/db');
const { verifyDeviceJwt } = require('./common/jwt');
const { consumeQuota, getQuota, calcCost } = require('./common/quota');
const logger = require('./common/logger');
const { parseLastUsageFromSse } = require('./sse-parser');

exports.main = async (event, context) => {
    const corsResp = handleCors(event);
    if (corsResp) return corsResp;

    const method = event.httpMethod || 'POST';
    // HTTP 网关剥路由前缀(/v1),直调传完整路径 —— 后缀匹配兼容两种
    const rawPath = (event.path || '').split('?')[0].replace(/\/+$/, '');
    const route = rawPath.split('/').pop() || '';

    try {
        if (method === 'POST' && route === 'completions') {
            return await handleChatCompletions(event, context);
        }
        return err(404, ErrorCodes.NOT_FOUND, `Unknown route: ${method} ${rawPath}`);
    } catch (e) {
        logger.error(context, `llm-proxy uncaught: ${e.message}`);
        return err(500, ErrorCodes.INTERNAL, 'Internal error');
    }
};

// ============================================================
// POST /v1/chat/completions
// ============================================================
async function handleChatCompletions(event, context) {
    // 1. 鉴权
    let claims;
    try {
        claims = await verifyDeviceJwt(event.headers, context);
    } catch (e) {
        return err(401, e.code || ErrorCodes.JWT_INVALID, 'Invalid JWT');
    }
    const androidId = claims.sub;

    // 2. 配额预检
    const device = await getQuota(androidId, context);
    if (!device) {
        return err(404, ErrorCodes.DEVICE_NOT_FOUND, 'Device not found');
    }
    if (device.status === 'banned') {
        return err(403, ErrorCodes.DEVICE_BANNED, 'Device banned');
    }
    if (device.quota_balance < 1) {
        return err(402, ErrorCodes.QUOTA_EXHAUSTED, 'Quota exhausted');
    }

    // 3. 读环境变量
    const llmBaseUrl = process.env.LLM_BASE_URL;
    const llmApiKey = process.env.LLM_API_KEY;
    if (!llmBaseUrl || !llmApiKey) {
        logger.error(context, 'LLM env not configured', {
            baseUrlSet: !!llmBaseUrl,
            keySet: !!llmApiKey,
        });
        return err(503, ErrorCodes.LLM_API_KEY_NOT_CONFIGURED, 'LLM not configured');
    }

    // 4. 解析请求体,转发
    const body = parseBody(event);
    const isStream = body.stream === true;
    // ⚠️ 不要把客户的 baseUrl / apiKey 字段传到上游
    const upstreamBody = sanitizeRequestBody(body);
    // 客户端没指定 model 时,用 LLM_DEFAULT_MODEL 兜底
    if (!upstreamBody.model && process.env.LLM_DEFAULT_MODEL) {
        upstreamBody.model = process.env.LLM_DEFAULT_MODEL;
    }

    logger.info(context, 'llm request', {
        android: androidId.slice(0, 8),
        model: upstreamBody.model,
        stream: isStream,
    });

    let upstream;
    try {
        upstream = await fetch(`${llmBaseUrl.replace(/\/+$/, '')}/chat/completions`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${llmApiKey}`,
            },
            body: JSON.stringify(upstreamBody),
        });
    } catch (e) {
        logger.error(context, `LLM upstream fetch failed: ${e.message}`);
        return err(502, ErrorCodes.LLM_UPSTREAM_ERROR, 'Upstream fetch failed');
    }

    if (!upstream.ok) {
        const errText = await upstream.text().catch(() => '');
        // ⚠️ 不 echo errText 全文(可能含敏感信息),只截前 200 字符进日志
        logger.error(context, `LLM upstream status=${upstream.status}`, {
            preview: errText.slice(0, 200),
        });
        return err(upstream.status, ErrorCodes.LLM_UPSTREAM_ERROR, `Upstream returned ${upstream.status}`);
    }

    // 5. 非流式:读 JSON → 扣减
    if (!isStream) {
        const data = await upstream.json();
        const tokens = data.usage?.total_tokens ?? 0;
        const cost = calcCost(tokens);
        const quotaResult = await consumeQuota(androidId, cost, 'llm_call', {
            tokens_used: tokens,
            model: data.model,
        }, context);
        if (!quotaResult.ok) {
            logger.warn(context, `quota consume failed after LLM ok: ${quotaResult.reason}`, {
                android: androidId.slice(0, 8),
            });
        }
        logger.info(context, 'llm response', {
            android: androidId.slice(0, 8),
            tokens,
            cost,
        });
        return ok(data);
    }

    // 6. 流式:读完整 SSE 文本 → 透传 + 末尾扣减
    const sseText = await upstream.text();
    const lastUsage = parseLastUsageFromSse(sseText);
    if (lastUsage) {
        const tokens = lastUsage.total_tokens ?? 0;
        const cost = calcCost(tokens);
        const quotaResult = await consumeQuota(androidId, cost, 'llm_call', {
            tokens_used: tokens,
            model: lastUsage.model,
        }, context);
        if (!quotaResult.ok) {
            logger.warn(context, `quota consume failed after stream LLM: ${quotaResult.reason}`, {
                android: androidId.slice(0, 8),
            });
        }
        logger.info(context, 'llm stream response', {
            android: androidId.slice(0, 8),
            tokens,
            cost,
        });
    } else {
        // 上游没返回 usage(可能不规范),扣 1 额度保底
        logger.warn(context, 'stream response missing usage, charging flat 1 quota', {
            android: androidId.slice(0, 8),
        });
        await consumeQuota(androidId, 1, 'llm_call', { tokens_used: null, model: upstreamBody.model }, context);
    }

    return sse(sseText);
}

/**
 * 清洗请求体:移除可能来自客户端的敏感字段(baseUrl/apiKey 等)
 * 保留 OpenAI 标准字段
 */
function sanitizeRequestBody(body) {
    const {
        model,
        messages,
        temperature,
        top_p,
        n,
        stream,
        stop,
        max_tokens,
        presence_penalty,
        frequency_penalty,
        user,
        tools,
        tool_choice,
        response_format,
        seed,
    } = body;

    const cleaned = {};
    if (model !== undefined) cleaned.model = model;
    if (messages !== undefined) cleaned.messages = messages;
    if (temperature !== undefined) cleaned.temperature = temperature;
    if (top_p !== undefined) cleaned.top_p = top_p;
    if (n !== undefined) cleaned.n = n;
    if (stream !== undefined) cleaned.stream = stream;
    if (stop !== undefined) cleaned.stop = stop;
    if (max_tokens !== undefined) cleaned.max_tokens = max_tokens;
    if (presence_penalty !== undefined) cleaned.presence_penalty = presence_penalty;
    if (frequency_penalty !== undefined) cleaned.frequency_penalty = frequency_penalty;
    if (user !== undefined) cleaned.user = user;
    if (tools !== undefined) cleaned.tools = tools;
    if (tool_choice !== undefined) cleaned.tool_choice = tool_choice;
    if (response_format !== undefined) cleaned.response_format = response_format;
    if (seed !== undefined) cleaned.seed = seed;

    return cleaned;
}

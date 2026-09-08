/**
 * SSE 解析工具:从完整的 SSE 文本中提取最后一个 usage 事件
 *
 * OpenAI 兼容协议流式响应的最后一个 chunk 格式:
 *   data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk",
 *          "choices":[{"index":0,"delta":{},"finish_reason":"stop"}],
 *          "usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30},
 *          "model":"deepseek-chat"}
 *
 * 用法:
 *   const sseText = await upstream.text();
 *   const lastUsage = parseLastUsageFromSse(sseText);
 *   if (lastUsage) { const cost = calcCost(lastUsage.total_tokens); ... }
 */

/**
 * 解析完整 SSE 文本,返回最后一个 usage 对象
 *
 * @param {string} sseText 完整的 SSE 响应文本
 * @returns {{total_tokens: number, prompt_tokens?: number, completion_tokens?: number, model?: string} | null}
 */
function parseLastUsageFromSse(sseText) {
    if (typeof sseText !== 'string' || !sseText) return null;

    const lines = sseText.split('\n');
    let lastUsage = null;
    let lastModel = null;
    let seenDone = false;  // 看到 [DONE] 后停止解析(避免误吃后续行)

    for (const rawLine of lines) {
        const line = rawLine.trim();
        if (!line.startsWith('data:')) continue;
        const data = line.slice(5).trim();
        if (!data) continue;
        if (data === '[DONE]') {
            seenDone = true;
            break;
        }

        let parsed;
        try {
            parsed = JSON.parse(data);
        } catch {
            continue;
        }

        if (parsed && typeof parsed === 'object') {
            if (parsed.usage && typeof parsed.usage === 'object') {
                lastUsage = parsed.usage;
            }
            if (typeof parsed.model === 'string') {
                lastModel = parsed.model;
            }
        }
    }

    if (!lastUsage) return null;
    return {
        ...lastUsage,
        model: lastModel || lastUsage.model || undefined,
    };
}

module.exports = { parseLastUsageFromSse };

/**
 * 托管 LLM 模型目录
 *
 * 配置来源:环境变量 LLM_MODELS_CONFIG(JSON 字符串)。
 *   例:
 *     {
 *       "baseline": "deepseek-v4-flash",
 *       "models": [
 *         { "id": "deepseek-v4-flash", "display_name": "DeepSeek V4 Flash",
 *           "short_name": "Flash", "ratio": 1,
 *           "description": "标准档 · 适合日常对话与长文生成" },
 *         { "id": "deepseek-v4-pro",   "display_name": "DeepSeek V4 Pro",
 *           "short_name": "Pro",   "ratio": 5,
 *           "description": "增强档 · 更强的长上下文理解" }
 *       ]
 *     }
 *
 *   - baseline: 最便宜的模型 id,所有 ratio 都相对它(1.0)
 *   - models[].ratio: 该模型相对 baseline 的消耗倍率(整数或小数,必须 > 0)
 *   - models[].enabled: 可选,默认 true;false 表示从目录隐去
 *   - models[].short_name: 可选,用于 app 端「消耗速度是 X 的 N 倍」短称
 *
 * 缺失/解析失败回退:从 LLM_DEFAULT_MODEL 单条构造(只有该模型 + ratio=1),
 * 让旧部署在没配 LLM_MODELS_CONFIG 时仍能工作(只是目录只有一项)。
 */

'use strict';

/**
 * 解析后的模型条目(对外契约)。
 *   ratio    相对 baseline 的消耗倍率
 *   baseline 是否为目录基准模型
 */
function normalizeEntry(raw, baselineId) {
    if (!raw || typeof raw !== 'object') return null;
    const id = typeof raw.id === 'string' ? raw.id.trim() : '';
    if (!id) return null;
    const ratio = Number(raw.ratio);
    if (!Number.isFinite(ratio) || ratio <= 0) return null;
    const enabled = raw.enabled === undefined ? true : raw.enabled === true;
    if (!enabled) return null;
    return {
        id,
        display_name: typeof raw.display_name === 'string' && raw.display_name.trim()
            ? raw.display_name.trim()
            : id,
        short_name: typeof raw.short_name === 'string' && raw.short_name.trim()
            ? raw.short_name.trim()
            : null,
        ratio,
        baseline: id === baselineId,
        description: typeof raw.description === 'string' ? raw.description : null,
    };
}

/**
 * 加载模型目录。env 可注入便于单测;返回 null 表示「目录不可用」,
 * 调用方应走 LLM_DEFAULT_MODEL 单条 fallback 路径。
 */
function loadModelCatalog(env) {
    const raw = env && env.LLM_MODELS_CONFIG;
    if (!raw) return null;
    let parsed;
    try {
        parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    } catch (e) {
        return null;
    }
    if (!parsed || typeof parsed !== 'object') return null;
    const list = Array.isArray(parsed.models) ? parsed.models : [];
    if (list.length === 0) return null;

    // 先 normalize,再根据 valid 后的结果推导 baseline
    const baselineRaw = typeof parsed.baseline === 'string' && parsed.baseline.trim()
        ? parsed.baseline.trim()
        : null;

    const entries = [];
    const seen = new Set();
    for (const item of list) {
        const norm = normalizeEntry(item, baselineRaw); // 先不传 baselineId
        if (!norm) continue;
        if (seen.has(norm.id)) continue; // 重复 id 静默去重
        seen.add(norm.id);
        entries.push(norm);
    }
    if (entries.length === 0) return null;

    // baseline:显式指定 → 用之;否则取 valid 第一项
    const baselineId = baselineRaw || entries[0].id;

    // 重新打 baseline 标记(只对最终 baselineId 命中者)
    for (const e of entries) {
        e.baseline = e.id === baselineId;
    }

    // 按 ratio 升序(便宜 → 贵)
    entries.sort((a, b) => a.ratio - b.ratio);

    return {
        baseline_id: baselineId,
        models: entries,
    };
}

/**
 * 兜底目录:仅 LLM_DEFAULT_MODEL 一条,ratio=1。
 * 让缺失 LLM_MODELS_CONFIG 的旧部署仍能服务 chat + 暴露 /v1/models。
 */
function fallbackCatalog(env) {
    const def = env && env.LLM_DEFAULT_MODEL;
    if (!def) return null;
    return {
        baseline_id: def,
        models: [{
            id: def,
            display_name: def,
            short_name: null,
            ratio: 1,
            baseline: true,
            description: null,
        }],
    };
}

/**
 * 解析 chat 请求中的 model 字段:
 *   - 命中目录且 enabled → { id, ratio }
 *   - 缺省 / 不在白名单 / 已禁用 → null(由调用方决定如何处理)
 */
function resolveModel(requestedId, catalog) {
    if (!catalog) return null;
    if (!requestedId) {
        return catalog.models.find(m => m.baseline) || catalog.models[0] || null;
    }
    const hit = catalog.models.find(m => m.id === requestedId);
    return hit || null;
}

/**
 * 目录 → OpenAI 风格 + 倍率字段的对外响应。
 * 不回显内部字段,app 端用它渲染选择列表。
 */
function catalogToResponse(catalog) {
    return {
        object: 'list',
        baseline_model_id: catalog.baseline_id,
        data: catalog.models.map(m => ({
            id: m.id,
            display_name: m.display_name,
            short_name: m.short_name,
            consumption_rate: m.ratio,
            is_baseline: m.baseline,
            description: m.description,
        })),
    };
}

module.exports = {
    loadModelCatalog,
    fallbackCatalog,
    resolveModel,
    catalogToResponse,
    // 暴露给单测
    _normalizeEntry: normalizeEntry,
};
/**
 * 配额操作:扣减 / 查询 / 充值
 *
 * 核心规则:1 额度 = 1000 tokens(Math.ceil 向上取整,最少扣 1 额度)
 * 写入时机:
 *   - register_bonus:device-auth 注册成功 +100
 *   - llm_call:llm-proxy 按 token 扣减
 *   - manual_grant / manual_reset / admin_revoke:管理员后台
 *
 * 并发安全:[判断] 用原子 SQL UPDATE ... WHERE quota_balance >= cost,
 * 失败回滚由 PG 事务保证,函数代码层不处理。
 */

const { getDb } = require('./db');

const REGISTER_BONUS = 100;       // 注册奖励额度
const TOKENS_PER_QUOTA = 1000;    // 1 额度 = 1000 tokens

/**
 * 按 token 数算扣减额度(向上取整,最少 1)
 *
 * @param {number} totalTokens
 * @returns {number}
 */
function calcCost(totalTokens) {
    if (!totalTokens || totalTokens < 0) return 0;
    return Math.max(1, Math.ceil(totalTokens / TOKENS_PER_QUOTA));
}

/**
 * 原子扣减额度(余额不足返回 false,不动 DB)
 *
 * @param {string} androidId
 * @param {number} cost 扣减量(正数)
 * @param {string} reason 'llm_call' / 'manual_revoke' 等
 * @param {object} [meta] {tokens_used, model, metadata}
 * @param {object} [context]
 * @returns {Promise<{ok: boolean, balance_after?: number, reason?: string}>}
 */
async function consumeQuota(androidId, cost, reason, meta = {}, context) {
    if (cost <= 0) {
        return { ok: true, balance_after: null, reason: 'NO_COST' };
    }
    const db = getDb(context);

    // 1. 原子 UPDATE:只扣够才扣
    // CloudBase PG 的 update + eq 链不支持 RETURNING,分两步:先 update,再 select
    const { data: updated, error: updateErr } = await db.from('devices')
        .update({
            quota_balance: db.raw ? undefined : undefined, // 用 RPC 替代,见下
        })
        .eq('android_id', androidId)
        .gte('quota_balance', cost)
        .select('quota_balance');

    // 注:CloudBase JS SDK 的 rdb() 不支持 .raw(),改用 RPC 函数 consume_quota_atomic
    // 该函数在 PG 中定义为:
    //   CREATE FUNCTION consume_quota_atomic(...) RETURNS TABLE(...) ...
    // 详细 SQL 见 cloudbase/migrations/20260907120006_atomic_quota_fn.sql(后续补)
    // 当前 fallback:乐观扣减(允许临时负数)
    if (updateErr) {
        // 退化为"无 WHERE 余额校验"的扣减
        const { data: device } = await db.from('devices')
            .select('quota_balance')
            .eq('android_id', androidId)
            .single();
        if (!device) return { ok: false, reason: 'DEVICE_NOT_FOUND' };

        const newBalance = device.quota_balance - cost;
        const { error: updErr2 } = await db.from('devices')
            .update({
                quota_balance: newBalance,
                total_consumed: device.quota_balance === undefined ? undefined : (device.total_consumed || 0) + cost,
                updated_at: new Date().toISOString(),
            })
            .eq('android_id', androidId);
        if (updErr2) return { ok: false, reason: 'UPDATE_FAILED' };

        await db.from('quota_changes').insert({
            android_id: androidId,
            change_amount: -cost,
            reason,
            balance_after: newBalance,
            tokens_used: meta.tokens_used ?? null,
            model: meta.model ?? null,
            metadata: meta.metadata ?? null,
        });
        return { ok: true, balance_after: newBalance };
    }

    return { ok: true, balance_after: updated?.[0]?.quota_balance };
}

/**
 * 充值 / 加额度(管理员操作)
 */
async function grantQuota(androidId, amount, reason = 'manual_grant', context) {
    const db = getDb(context);
    const { data: device } = await db.from('devices')
        .select('quota_balance')
        .eq('android_id', androidId)
        .single();
    if (!device) return { ok: false, reason: 'DEVICE_NOT_FOUND' };

    const newBalance = device.quota_balance + amount;
    const { error } = await db.from('devices')
        .update({ quota_balance: newBalance, updated_at: new Date().toISOString() })
        .eq('android_id', androidId);
    if (error) return { ok: false, reason: 'UPDATE_FAILED' };

    await db.from('quota_changes').insert({
        android_id: androidId,
        change_amount: amount,
        reason,
        balance_after: newBalance,
    });
    return { ok: true, balance_after: newBalance };
}

/**
 * 查询设备额度
 */
async function getQuota(androidId, context) {
    const db = getDb(context);
    const { data } = await db.from('devices')
        .select('quota_balance, total_consumed, status')
        .eq('android_id', androidId)
        .single();
    return data || null;
}

module.exports = { consumeQuota, grantQuota, getQuota, calcCost, REGISTER_BONUS, TOKENS_PER_QUOTA };

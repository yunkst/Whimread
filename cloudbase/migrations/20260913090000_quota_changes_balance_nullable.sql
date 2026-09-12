-- 20260913090000_quota_changes_balance_nullable.sql
--
-- 放开 quota_changes.balance_after 的 NOT NULL 约束
--
-- 背景:star 兑换采用「审计先行门闸」——先 INSERT 审计占位行(balance_after
-- 未知传 NULL)形成 uq_quota_changes_star_login 并发门闸,加钱成功后再回填
-- balance_after(见 device-auth/fn.ts handleRedeem)。建表时该列 NOT NULL,
-- 占位插入必然违反约束 → 兑换恒 500「Failed to record redeem」。
-- 单测 fake db 无列约束,从未暴露。2026-09-13 真库联调(yunkst)发现。
--
-- 其他路径(llm_call/manual_grant/manual_reset)先算后写,均传数字,不受影响。

ALTER TABLE quota_changes ALTER COLUMN balance_after DROP NOT NULL;

-- down migration(回滚用;执行前需确认无 balance_after IS NULL 的占位行)
-- UPDATE quota_changes SET balance_after = 0 WHERE balance_after IS NULL;
-- ALTER TABLE quota_changes ALTER COLUMN balance_after SET NOT NULL;

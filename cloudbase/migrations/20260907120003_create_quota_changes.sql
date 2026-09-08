-- 配额变更日志
-- 用途:审计每次额度变动(充值、扣减、管理员调整)
-- 写入时机:device-auth 注册奖励 + llm-proxy 按 token 扣减 + 手动调整

CREATE TABLE quota_changes (
    id BIGSERIAL PRIMARY KEY,
    android_id VARCHAR(64) NOT NULL,
    change_amount INTEGER NOT NULL,
    reason VARCHAR(50) NOT NULL,
    balance_after INTEGER NOT NULL,
    tokens_used INTEGER,
    model VARCHAR(100),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT quota_changes_reason_check CHECK (
        reason IN ('register_bonus', 'llm_call', 'manual_grant', 'manual_reset', 'admin_revoke')
    )
);

CREATE INDEX idx_quota_changes_android_id ON quota_changes(android_id);
CREATE INDEX idx_quota_changes_created_at ON quota_changes(created_at);
CREATE INDEX idx_quota_changes_reason ON quota_changes(reason, created_at);

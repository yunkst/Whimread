-- 设备表(主表)
-- 用途:存储 Whimread 客户端设备身份 + 额度余额
-- 主键:android_id(Android SSAID,同签名重装不变)

CREATE TABLE devices (
    android_id VARCHAR(64) PRIMARY KEY,
    attestation_cert TEXT,
    quota_balance INTEGER NOT NULL DEFAULT 100,
    total_consumed INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT devices_status_check CHECK (status IN ('active', 'banned'))
);

CREATE INDEX idx_devices_status ON devices(status);
CREATE INDEX idx_devices_last_seen ON devices(last_seen_at);

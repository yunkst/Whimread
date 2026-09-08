-- 设备 JWT 表
-- 用途:存证每个签发的 JWT,支持撤销 + 过期清理
-- 主键:jti(JWT ID,UUID)

CREATE TABLE device_jwts (
    jti VARCHAR(64) PRIMARY KEY,
    android_id VARCHAR(64) NOT NULL REFERENCES devices(android_id) ON DELETE CASCADE,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT device_jwts_expiry_check CHECK (expires_at > issued_at)
);

-- 按 android_id 查某设备的活跃 JWT
CREATE INDEX idx_device_jwts_android_id ON device_jwts(android_id);

-- 部分索引:只索引未撤销的 JWT,加速 token 校验
CREATE INDEX idx_device_jwts_active ON device_jwts(expires_at) WHERE revoked_at IS NULL;

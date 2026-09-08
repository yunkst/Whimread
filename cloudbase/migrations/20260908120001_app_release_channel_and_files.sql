-- 20260908120001_app_release_channel_and_files.sql
--
-- 扩展 app_releases 以支持双通道发布(stable / preview)
-- 与多架构 APK 列表,匹配 spec §4.2 + BackendRelease 文件 JSON 契约。
--
-- 背景:
  --  -- v1 schema 只有一个 is_active=true 的 active release 行,Flutter 端
  --    BackendReleaseService 期望返回 channel + files: [{abi, size, sha256, url}]
  --  -- spec §6.2 的迁移(20260907120004)没考虑 channel 区分,也没考虑多 APK
  --  -- 现在 CloudBase 函数增加 POST /publish,接收 multipart form 写入
--
-- 数据迁移策略(从老 schema 升级):
  --  -- 现有 1 行(若有)默认 channel=stable,is_active=true 保留语义
  --  -- 不强制 backfill files,因为老 schema 只有单一 download_url
--
-- 不破坏现有数据:
  --  -- ALTER TABLE ... ADD COLUMN IF NOT EXISTS(可重入)
  --  -- CREATE TABLE IF NOT EXISTS

-- ============================================================
-- 1. 扩展 app_releases 表:加 channel + release_notes HTML/MD 兼容字段
-- ============================================================

ALTER TABLE app_releases
    ADD COLUMN IF NOT EXISTS channel VARCHAR(10) NOT NULL DEFAULT 'stable';

-- channel 必须是 stable / preview 之一(数据库层强约束)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'app_releases_channel_check'
    ) THEN
        ALTER TABLE app_releases
            ADD CONSTRAINT app_releases_channel_check
            CHECK (channel IN ('stable', 'preview'));
    END IF;
END $$;

-- 加索引加速 GET /latest?channel=X 查询
-- (active 行按 published_at 倒序、且限定 channel)
DROP INDEX IF EXISTS idx_app_releases_active;
CREATE INDEX idx_app_releases_active
    ON app_releases(is_active, channel, published_at DESC)
    WHERE is_active = TRUE;

-- ============================================================
-- 2. 关联表 app_release_files:每个 release 行对应多个 APK(arm64-v8a /
--    armeabi-v7a / x86_64)
-- ============================================================

CREATE TABLE IF NOT EXISTS app_release_files (
    id BIGSERIAL PRIMARY KEY,
    release_id BIGINT NOT NULL REFERENCES app_releases(id) ON DELETE CASCADE,
    abi VARCHAR(20) NOT NULL,                  -- arm64-v8a / armeabi-v7a / x86_64
    filename VARCHAR(255) NOT NULL,
    size_bytes BIGINT NOT NULL CHECK (size_bytes > 0),
    sha256 CHAR(64) NOT NULL,                  -- hex SHA-256
    storage_key TEXT NOT NULL,                 -- CloudBase Storage 内的 object key
    storage_url TEXT NOT NULL,                 -- 公开下载 URL(拼 COS 域名)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- 同 release 内不允许重复 abi(防止重复上传覆盖遗漏)
    CONSTRAINT app_release_files_abi_unique UNIQUE (release_id, abi)
);

CREATE INDEX IF NOT EXISTS idx_app_release_files_release
    ON app_release_files(release_id);

-- ============================================================
-- 3. 注释
-- ============================================================

COMMENT ON COLUMN app_releases.channel IS 'stable | preview,通道隔离,stable 不返回预览版';
COMMENT ON TABLE app_release_files IS '一个 release 行对应的多个 ABI APK 文件,存 CloudBase Storage';

-- ============================================================
-- 4. down migration(回滚用)
-- ============================================================

-- DROP TABLE IF EXISTS app_release_files;
-- DROP INDEX IF EXISTS idx_app_releases_active;
-- ALTER TABLE app_releases DROP CONSTRAINT IF EXISTS app_releases_channel_check;
-- ALTER TABLE app_releases DROP COLUMN IF EXISTS channel;
-- CREATE INDEX idx_app_releases_active ON app_releases(is_active, published_at DESC);
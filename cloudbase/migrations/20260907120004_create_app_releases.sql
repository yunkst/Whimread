-- APP 版本发布表
-- 用途:存储 APP 最新版本信息,Flutter 启动时拉取,做更新提示
-- 数据流:管理员手动 insert 一行 is_active=true(老行自动 is_active=false)

CREATE TABLE app_releases (
    id BIGSERIAL PRIMARY KEY,
    version VARCHAR(20) NOT NULL,
    build INTEGER NOT NULL,
    download_url TEXT NOT NULL,
    release_notes TEXT,
    force_update BOOLEAN NOT NULL DEFAULT FALSE,
    min_supported_version VARCHAR(20),
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT app_releases_build_positive CHECK (build > 0)
);

-- 只索引活跃版本,加速 /latest 查询
CREATE INDEX idx_app_releases_active ON app_releases(is_active, published_at DESC);

-- 强制 version + build 联合唯一
CREATE UNIQUE INDEX idx_app_releases_version_build ON app_releases(version, build);

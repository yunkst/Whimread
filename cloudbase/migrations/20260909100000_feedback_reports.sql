-- 20260909100000_feedback_reports.sql
--
-- 问题反馈 + 日志上报持久化表,匹配 feedback 云函数:
--   - POST /api/v1/feedback/submit  → feedback_reports(+ 附带 feedback_logs)
--   - POST /api/logs/upload         → feedback_logs(流式批量, report_id 为 NULL)
--   - GET  /api/v1/feedback/list|detail|logs(管理端拉取)
--
-- 设计:
--   - 报告与日志分表:单个报告可附带 300 条日志,独立表 + ON DELETE CASCADE
--   - feedback_logs.report_id 为 NULL 表示 LogReporterService 批量上报的
--     流式日志(非报告附带),按 device_id + ts 检索
--   - 滥用限流由云函数内存 LRU 实现(device_id + 60s 窗口),不落表
--   - 留存策略:建议定期清理 90 天前的 feedback_logs(清理任务另行安排)

-- ============================================================
-- 1. feedback_reports(用户问题报告)
-- ============================================================

CREATE TABLE IF NOT EXISTS feedback_reports (
    id BIGSERIAL PRIMARY KEY,
    device_id TEXT NOT NULL,                          -- android_id(JWT sub)
    kind VARCHAR(20) NOT NULL DEFAULT 'user_report',  -- user_report | native_crash
    category VARCHAR(20),                             -- bug | feature | usage(UI 分类,可空)
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    steps TEXT,                                       -- 复现步骤(可选)
    contact TEXT,                                     -- 联系方式(可选)
    app_version VARCHAR(40),                          -- x.y.z+build
    platform VARCHAR(20),                             -- android
    device_model TEXT,                                -- 厂商 型号 (Android x, SDK y)
    log_count INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'open',       -- open | triaged | closed
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_reports_created_at
    ON feedback_reports(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_reports_device
    ON feedback_reports(device_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'feedback_reports_kind_check'
    ) THEN
        ALTER TABLE feedback_reports
            ADD CONSTRAINT feedback_reports_kind_check
            CHECK (kind IN ('user_report', 'native_crash'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'feedback_reports_status_check'
    ) THEN
        ALTER TABLE feedback_reports
            ADD CONSTRAINT feedback_reports_status_check
            CHECK (status IN ('open', 'triaged', 'closed'));
    END IF;
END $$;

-- ============================================================
-- 2. feedback_logs(报告附带日志 + 流式批量日志共用)
-- ============================================================

CREATE TABLE IF NOT EXISTS feedback_logs (
    id BIGSERIAL PRIMARY KEY,
    report_id BIGINT REFERENCES feedback_reports(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    seq INTEGER NOT NULL DEFAULT 0,                   -- 报告内顺序(0-based)
    ts TIMESTAMPTZ NOT NULL,
    level VARCHAR(10) NOT NULL,                       -- debug | info | warning | error
    category VARCHAR(40),
    message TEXT NOT NULL,
    stack_trace TEXT,
    tags JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_logs_report
    ON feedback_logs(report_id, seq);
CREATE INDEX IF NOT EXISTS idx_feedback_logs_device_ts
    ON feedback_logs(device_id, ts DESC);

-- ============================================================
-- 3. 注释
-- ============================================================

COMMENT ON TABLE feedback_reports IS '用户问题报告(反馈表单提交 / native 崩溃上报)';
COMMENT ON TABLE feedback_logs IS '日志条目:report_id 非空 = 报告附带;为空 = LogReporterService 批量上报';

-- ============================================================
-- 4. down migration(回滚用)
-- ============================================================

-- DROP TABLE IF EXISTS feedback_logs;
-- DROP TABLE IF EXISTS feedback_reports;

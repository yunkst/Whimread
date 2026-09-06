-- 多书架功能数据库迁移脚本
-- 版本: v3 -> v4
-- 说明: 添加书架管理功能，支持多书架分类

-- 1. 创建书架表
CREATE TABLE IF NOT EXISTS bookshelves (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    sort_order INTEGER DEFAULT 0,
    icon TEXT DEFAULT 'book',
    color INTEGER DEFAULT 0xFF2196F3,
    is_system INTEGER DEFAULT 0  -- 是否为系统书架（0=用户创建，1=系统书架）
);

-- 2. 创建小说-书架关联表
CREATE TABLE IF NOT EXISTS novel_bookshelves (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    novel_url TEXT NOT NULL,
    bookshelf_id INTEGER NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (novel_url) REFERENCES novels(url) ON DELETE CASCADE,
    FOREIGN KEY (bookshelf_id) REFERENCES bookshelves(id) ON DELETE CASCADE,
    UNIQUE(novel_url, bookshelf_id)
);

-- 3. 创建索引
CREATE INDEX IF NOT EXISTS idx_novel_bookshelf_url ON novel_bookshelves(novel_url);
CREATE INDEX IF NOT EXISTS idx_bookshelf_id ON novel_bookshelves(bookshelf_id);

-- 4. 插入系统书架
-- 注意：使用 INSERT OR IGNORE 避免重复插入
INSERT OR IGNORE INTO bookshelves (id, name, created_at, sort_order, is_system)
VALUES
    (1, '全部小说', strftime('%s', 'now'), 0, 1),
    (2, '我的收藏', strftime('%s', 'now'), 1, 1);

-- 5. 数据迁移：将现有书籍关联到"我的收藏"书架
INSERT OR IGNORE INTO novel_bookshelves (novel_url, bookshelf_id, created_at)
SELECT url, 2, strftime('%s', 'now')
FROM novels
WHERE is_in_bookshelf = 1;

-- 6. 更新数据库版本标记
-- 注意：这个需要在应用代码中完成，这里只是数据准备

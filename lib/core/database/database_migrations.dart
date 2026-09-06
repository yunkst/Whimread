import 'package:sqflite/sqflite.dart';
import '../../services/logger_service.dart';

/// 数据库迁移逻辑单例
///
/// 职责：
/// - 提供 v1 基础表创建逻辑
/// - 提供 v1 → v21 完整迁移逻辑
/// - 两个逻辑均由 DatabaseConnection 和 TestDatabaseSetup 共享调用
///
/// 设计原则：单一数据源，避免迁移逻辑重复维护
class DatabaseMigrations {
  /// 当前数据库版本
  static const int currentVersion = 39;

  /// ========== v1 基础表创建 ==========
  /// 新安装时调用，与 _onUpgrade(1) 共同构建完整数据库

  /// 创建 v1 基础表
  ///
  /// 仅创建最早版本的核心字段，不含后续迁移添加的字段。
  /// 创建完成后会调用 [upgradeFromV1] 将数据库升级到最新版本。
  static Future<void> createV1Tables(Database db) async {
    // 小说表（v1，包含完整字段）
    // lastReadChapter/lastReadTime 用于阅读进度追踪
    // aiAccompanimentEnabled/aiInfoNotificationEnabled 用于AI伴读设置
    await db.execute('''
    CREATE TABLE bookshelf (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      url TEXT NOT NULL UNIQUE,
      coverUrl TEXT,
      description TEXT,
      backgroundSetting TEXT,
      addedAt INTEGER NOT NULL,
      lastReadChapter INTEGER DEFAULT 0,
      lastReadTime INTEGER,
      aiAccompanimentEnabled INTEGER DEFAULT 0,
      aiInfoNotificationEnabled INTEGER DEFAULT 0
    )
  ''');

    // 章节缓存表（v1，最小字段集）
    // isAccompanied 字段在 v18 迁移中添加
    await db.execute('''
    CREATE TABLE chapter_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      novelUrl TEXT NOT NULL,
      chapterUrl TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      chapterIndex INTEGER,
      cachedAt INTEGER NOT NULL
    )
  ''');

    // 小说章节列表缓存表（v1，最小字段集）
    // isUserInserted/insertedAt 在 v2 添加
    // isAccompanied/readAt 在 v18 添加
    await db.execute('''
    CREATE TABLE novel_chapters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      novelUrl TEXT NOT NULL,
      chapterUrl TEXT NOT NULL,
      title TEXT NOT NULL,
      chapterIndex INTEGER,
      UNIQUE(novelUrl, chapterUrl)
    )
  ''');

    // 人物表（v1，无扩展字段）
    await db.execute('''
    CREATE TABLE characters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      novelUrl TEXT NOT NULL,
      name TEXT NOT NULL,
      age INTEGER,
      gender TEXT,
      occupation TEXT,
      personality TEXT,
      bodyType TEXT,
      clothingStyle TEXT,
      appearanceFeatures TEXT,
      backgroundStory TEXT,
      createdAt INTEGER NOT NULL,
      UNIQUE(novelUrl, name)
    )
  ''');

    // 场景插图表（v1，有 task_id）
    await db.execute('''
    CREATE TABLE scene_illustrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      novel_url TEXT NOT NULL,
      chapter_id TEXT NOT NULL,
      task_id TEXT NOT NULL UNIQUE,
      content TEXT NOT NULL,
      roles TEXT NOT NULL,
      image_count INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      images TEXT DEFAULT '',
      prompts TEXT,
      created_at TEXT NOT NULL,
      completed_at TEXT
    )
  ''');

    // 索引（v1）
    await db.execute('''
    CREATE INDEX idx_chapter_cache_chapter_url ON chapter_cache(chapterUrl)
  ''');
    await db.execute('''
    CREATE INDEX idx_chapter_cache_novel_url ON chapter_cache(novelUrl)
  ''');
    await db.execute('''
    CREATE INDEX idx_novel_chapters_novel_url ON novel_chapters(novelUrl)
  ''');

    _log('v1 基础表创建完成');
  }

  /// ========== 数据库升级逻辑 ==========
  /// 从指定版本升级到 [toVersion]

  /// 执行数据库升级
  ///
  /// 核心方法：执行从 [fromVersion] 到 [toVersion] 的所有迁移。
  /// 入口：
  /// - 新安装：fromVersion=1
  /// - 版本升级：由 sqflite 的 onUpgrade 回调传入
  static Future<void> upgrade(
      Database db, int fromVersion, int toVersion) async {
    final startTime = DateTime.now();

    // 执行每个版本的迁移
    for (int version = fromVersion + 1; version <= toVersion; version++) {
      _log('开始迁移 v${version - 1} → v$version...');
      await _migrateToVersion(db, version);
      _log('迁移完成 v$version');
    }

    final duration = DateTime.now().difference(startTime);
    _log('数据库升级成功: v$fromVersion → v$toVersion, 耗时${duration.inMilliseconds}ms');
  }

  /// 升级到指定版本
  ///
  /// 每个版本一个迁移块，版本号对应数据库 schema 版本。
  /// 迁移使用 `IF NOT EXISTS` / `IF NOT EXISTS` 等安全写法，
  /// 确保在已有表/字段时不报错。
  static Future<void> _migrateToVersion(Database db, int version) async {
    switch (version) {
      // ========== 版本 2：用户插入章节标记 ==========
      case 2:
        await _addColumnIfNotExists(
            db, 'novel_chapters', 'isUserInserted', 'INTEGER DEFAULT 0');
        await _addColumnIfNotExists(
            db, 'novel_chapters', 'insertedAt', 'INTEGER');
        break;

      // ========== 版本 3：背景设定字段（v1 已包含，此迁移安全跳过）==========
      case 3:
        await _addColumnIfNotExists(
            db, 'bookshelf', 'backgroundSetting', 'TEXT');
        break;

      // ========== 版本 4：人物表（重建，带完整字段） ==========
      case 4:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS characters (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          novelUrl TEXT NOT NULL,
          name TEXT NOT NULL,
          age INTEGER,
          gender TEXT,
          occupation TEXT,
          personality TEXT,
          bodyType TEXT,
          clothingStyle TEXT,
          appearanceFeatures TEXT,
          backgroundStory TEXT,
          facePrompts TEXT,
          bodyPrompts TEXT,
          cachedImageUrl TEXT,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER,
          UNIQUE(novelUrl, name)
        )
      ''');
        // Bug fix: IF NOT EXISTS 不会给 v1 已存在的 characters 表加 updatedAt
        // 必须用 ALTER TABLE 显式补列（已有表走 _addColumnIfNotExists 分支）
        await _addColumnIfNotExists(db, 'characters', 'updatedAt', 'INTEGER');
        break;

      // ========== 版本 5：提示词字段 ==========
      case 5:
        await _addColumnIfNotExists(
            db, 'characters', 'facePrompts', 'TEXT');
        await _addColumnIfNotExists(
            db, 'characters', 'bodyPrompts', 'TEXT');
        break;

      // ========== 版本 6：缓存图片URL ==========
      case 6:
        await _addColumnIfNotExists(
            db, 'characters', 'cachedImageUrl', 'TEXT');
        break;

      // ========== 版本 7：场景插图表 ==========
      case 7:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS scene_illustrations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          novel_url TEXT NOT NULL,
          chapter_id TEXT NOT NULL,
          task_id TEXT NOT NULL UNIQUE,
          content TEXT NOT NULL,
          roles TEXT NOT NULL,
          image_count INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          images TEXT DEFAULT '',
          prompts TEXT,
          created_at TEXT NOT NULL,
          completed_at TEXT
        )
      ''');
        break;

      // ========== 版本 8：修复场景插图表（添加 task_id） ==========
      case 8:
        final tableInfo =
            await db.rawQuery("PRAGMA table_info(scene_illustrations)");
        final hasTaskId =
            tableInfo.any((column) => column['name'] == 'task_id');

        if (!hasTaskId) {
          await db.execute('DROP TABLE IF EXISTS scene_illustrations');
          await db.execute('''
          CREATE TABLE scene_illustrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            novel_url TEXT NOT NULL,
            chapter_id TEXT NOT NULL,
            task_id TEXT NOT NULL UNIQUE,
            content TEXT NOT NULL,
            roles TEXT NOT NULL,
            image_count INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            images TEXT DEFAULT '',
            prompts TEXT,
            created_at TEXT NOT NULL,
            completed_at TEXT
          )
        ''');
          _log('数据库 v8: 重新创建 scene_illustrations 表，添加 task_id 字段');
        }
        break;

      // ========== 版本 9：大纲表 ==========
      case 9:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS outlines (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          novel_url TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        break;

      // ========== 版本 10：聊天场景表 ==========
      case 10:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_scenes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER
        )
      ''');
        await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_chat_scenes_title ON chat_scenes(title)
      ''');
        break;

      // ========== 版本 11：章节已读时间戳 ==========
      case 11:
        await _addColumnIfNotExists(
            db, 'novel_chapters', 'readAt', 'INTEGER');
        break;

      // ========== 版本 12：角色别名字段 ==========
      case 12:
        await _addColumnIfNotExists(
            db, 'characters', 'aliases', "TEXT DEFAULT '[]'");
        break;

      // ========== 版本 13：角色关系表 ==========
      case 13:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS character_relationships (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_character_id INTEGER NOT NULL,
          target_character_id INTEGER NOT NULL,
          relationship_type TEXT NOT NULL,
          description TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER,
          FOREIGN KEY (source_character_id) REFERENCES characters(id) ON DELETE CASCADE,
          FOREIGN KEY (target_character_id) REFERENCES characters(id) ON DELETE CASCADE,
          UNIQUE(source_character_id, target_character_id, relationship_type)
        )
      ''');
        await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_relationships_source ON character_relationships(source_character_id)
      ''');
        await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_relationships_target ON character_relationships(target_character_id)
      ''');
        break;

      // ========== 版本 14：AI伴读设置 ==========
      case 14:
        await _addColumnIfNotExists(
            db, 'bookshelf', 'aiAccompanimentEnabled', 'INTEGER DEFAULT 0');
        await _addColumnIfNotExists(
            db, 'bookshelf', 'aiInfoNotificationEnabled', 'INTEGER DEFAULT 0');
        break;

      // ========== 版本 15：章节伴读标记 ==========
      case 15:
        await _addColumnIfNotExists(
            db, 'chapter_cache', 'ai_accompanied', 'INTEGER DEFAULT 0');
        break;

      // ========== 版本 16：多书架功能 ==========
      case 16:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS bookshelves (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          sort_order INTEGER DEFAULT 0,
          icon TEXT DEFAULT 'book',
          color INTEGER DEFAULT 0xFF2196F3,
          is_system INTEGER DEFAULT 0
        )
      ''');
        await db.execute('''
        CREATE TABLE IF NOT EXISTS novel_bookshelves (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          novel_url TEXT NOT NULL,
          bookshelf_id INTEGER NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          FOREIGN KEY (novel_url) REFERENCES bookshelf(url) ON DELETE CASCADE,
          FOREIGN KEY (bookshelf_id) REFERENCES bookshelves(id) ON DELETE CASCADE,
          UNIQUE(novel_url, bookshelf_id)
        )
      ''');
        await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_novel_bookshelf_url ON novel_bookshelves(novel_url)
      ''');
        await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_bookshelf_id ON novel_bookshelves(bookshelf_id)
      ''');
        await db.execute('''
        INSERT OR IGNORE INTO bookshelves (id, name, created_at, sort_order, is_system)
        VALUES
          (1, '全部小说', strftime('%s', 'now'), 0, 1),
          (2, '我的收藏', strftime('%s', 'now'), 1, 1)
      ''');
        // 仅在 novel_bookshelves 为空时迁移现有书籍到"我的收藏"
        // 避免重复执行时覆盖用户手动移除的关联
        final existingLinks = await db.rawQuery(
            'SELECT COUNT(*) as count FROM novel_bookshelves');
        final linkCount = existingLinks.first['count'] as int? ?? 0;
        if (linkCount == 0) {
          await db.execute('''
          INSERT OR IGNORE INTO novel_bookshelves (novel_url, bookshelf_id, created_at)
          SELECT url, 2, strftime('%s', 'now')
          FROM bookshelf
          WHERE url IS NOT NULL
        ''');
        }
        break;

      // ========== 版本 17：修复人物表字段 ==========
      case 17:
        await _addColumnIfNotExists(
            db, 'characters', 'facePrompts', 'TEXT');
        await _addColumnIfNotExists(
            db, 'characters', 'bodyPrompts', 'TEXT');
        await _addColumnIfNotExists(
            db, 'characters', 'cachedImageUrl', 'TEXT');
        break;

      // ========== 版本 18：AI伴读标记字段标准化 ==========
      case 18:
        await _addColumnIfNotExists(
            db, 'chapter_cache', 'isAccompanied', 'INTEGER DEFAULT 0');
        await _addColumnIfNotExists(
            db, 'novel_chapters', 'isAccompanied', 'INTEGER DEFAULT 0');
        break;

      // ========== 版本 19：字段重命名 ai_accompanied → isAccompanied ==========
      case 19:
        await _renameColumnIfExists(
          db,
          'chapter_cache',
          'ai_accompanied',
          'isAccompanied',
          'INTEGER DEFAULT 0',
        );
        await _renameColumnIfExists(
          db,
          'novel_chapters',
          'ai_accompanied',
          'isAccompanied',
          'INTEGER DEFAULT 0',
        );
        break;

      // ========== 版本 20：novels 视图 ==========
      case 20:
        await db.execute('''
        CREATE VIEW IF NOT EXISTS novels AS
        SELECT
          id,
          title,
          author,
          url,
          coverUrl,
          description,
          backgroundSetting,
          addedAt,
          lastReadChapter,
          lastReadTime,
          aiAccompanimentEnabled,
          aiInfoNotificationEnabled
        FROM bookshelf
      ''');
        break;

      // ========== 版本 21：性能优化索引 ==========
      case 21:
        await _createIndexIfNotExists(
            db, 'idx_chapter_cache_chapter_url', 'chapter_cache', 'chapterUrl');
        await _createIndexIfNotExists(
            db, 'idx_chapter_cache_novel_url', 'chapter_cache', 'novelUrl');
        await _createIndexIfNotExists(
            db, 'idx_novel_chapters_novel_url', 'novel_chapters', 'novelUrl');
        await _createIndexIfNotExists(
            db, 'idx_novel_chapters_chapter_url', 'novel_chapters', 'chapterUrl');
        break;

      // ========== 版本 22：用户提示词历史记录表 ==========
      case 22:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS prompt_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          prompt_text TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          tag_group_ids TEXT
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_prompt_history_updated_at', 'prompt_history', 'updated_at');
        break;

      // ========== 版本 23：提示词标签分类 + 标签表 ==========
      case 23:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS prompt_tag_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        await db.execute('''
        CREATE TABLE IF NOT EXISTS prompt_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          prompt_text TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_prompt_tags_category_id', 'prompt_tags', 'category_id');
        break;

      // ========== 版本 24：移除 prompt_tags 的 UNIQUE(category_id, name) 约束 ==========
      case 24:
        // SQLite 不支持直接删除约束，需要重建表
        await db.execute('''
        CREATE TABLE prompt_tags_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          prompt_text TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        await db.execute('''
        INSERT INTO prompt_tags_new (id, category_id, name, prompt_text, sort_order, created_at, updated_at)
        SELECT id, category_id, name, prompt_text, sort_order, created_at, updated_at
        FROM prompt_tags
      ''');
        await db.execute('DROP TABLE prompt_tags');
        await db.execute('ALTER TABLE prompt_tags_new RENAME TO prompt_tags');
        await _createIndexIfNotExists(
            db, 'idx_prompt_tags_category_id', 'prompt_tags', 'category_id');
        break;

      // ========== 版本 25：站点提取脚本表 ==========
      case 25:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS site_scripts (
          id TEXT PRIMARY KEY,
          domain TEXT NOT NULL,
          url_pattern TEXT NOT NULL DEFAULT '',
          chapter_list_js TEXT NOT NULL,
          chapter_content_js TEXT NOT NULL,
          sample_url TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          last_used_at INTEGER NOT NULL,
          use_count INTEGER NOT NULL DEFAULT 0,
          verified INTEGER NOT NULL DEFAULT 0
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_site_scripts_domain', 'site_scripts', 'domain');
        break;

      // ========== 版本 26：prompt_history 关联标签快照 ==========
      case 26:
        await _addColumnIfNotExists(
            db, 'prompt_history', 'tag_group_ids', 'TEXT');
        _log('迁移 v25 → v26: 添加 prompt_history.tag_group_ids 列');
        break;

      // ========== 版本 27：Agent 场景经验记忆表 ==========
      case 27:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS agent_memory (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scenario_id TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_agent_memory_scenario', 'agent_memory', 'scenario_id');
        _log('迁移 v26 → v27: 创建 agent_memory 表');
        break;

      // ========== 版本 28：prompt_tags 加 reason 列 + prompt_tag_history 表 ==========
      case 28:
        await _addColumnIfNotExists(
            db, 'prompt_tags', 'reason', 'TEXT NOT NULL DEFAULT \'\'');
        await db.execute('''
        CREATE TABLE IF NOT EXISTS prompt_tag_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tag_id INTEGER NOT NULL,
          novel_url TEXT NOT NULL,
          change_type TEXT NOT NULL,
          old_value TEXT,
          new_value TEXT NOT NULL,
          reason TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (tag_id) REFERENCES prompt_tags(id) ON DELETE CASCADE
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_tag_history_tag_id', 'prompt_tag_history', 'tag_id');
        _log('迁移 v27 → v28: prompt_tags 加 reason 列 + 创建 prompt_tag_history 表');
        break;

      case 29:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS llm_configs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          api_url TEXT NOT NULL,
          api_key TEXT NOT NULL,
          model TEXT NOT NULL DEFAULT '',
          is_default INTEGER NOT NULL DEFAULT 0,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_llm_configs_sort', 'llm_configs', 'sort_order');
        _log('迁移 v28 → v29: 创建 llm_configs 表');
        break;

      // ========== 版本 30：章节版本历史表 ==========
      case 30:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS chapter_versions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          chapterUrl TEXT NOT NULL,
          content TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'edit',
          createdAt INTEGER NOT NULL,
          contentLength INTEGER NOT NULL DEFAULT 0
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_chapter_versions_chapter_url', 'chapter_versions', 'chapterUrl');
        await _createIndexIfNotExists(
            db, 'idx_chapter_versions_created_at', 'chapter_versions', 'createdAt');
        _log('迁移 v29 → v30: 创建 chapter_versions 表');
        break;

      // ========== 版本 31：AI 对话会话历史 ==========
      // chat_sessions + chat_messages 两表 + 外键 CASCADE。
      // SQLite 默认关闭 foreign_keys，迁移自开启以让 FK CASCADE 在所有入口生效
      // （生产连接由 DatabaseConnection._initDatabase 末尾开启；测试走本迁移）。
      case 31:
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          scenarioId TEXT NOT NULL,
          title TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          currentNovelId INTEGER,
          currentNovelTitle TEXT
        )
      ''');
        await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sessionId INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          segmentsJson TEXT NOT NULL DEFAULT '[]',
          timestamp INTEGER NOT NULL,
          orderIndex INTEGER NOT NULL,
          FOREIGN KEY (sessionId) REFERENCES chat_sessions(id) ON DELETE CASCADE
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_chat_sessions_scenario_updated', 'chat_sessions', 'scenarioId');
        // sessions 按 (scenarioId, updatedAt DESC) 列出，建复合索引
        await _createIndexIfNotExists(
            db, 'idx_chat_sessions_scenario_updated_desc', 'chat_sessions', 'scenarioId, updatedAt DESC');
        await _createIndexIfNotExists(
            db, 'idx_chat_messages_session', 'chat_messages', 'sessionId');
        // messages 按 (sessionId, orderIndex ASC) 取出，建复合索引
        await _createIndexIfNotExists(
            db, 'idx_chat_messages_session_order', 'chat_messages', 'sessionId, orderIndex ASC');
        _log('迁移 v30 → v31: 创建 chat_sessions + chat_messages 表（含外键 CASCADE）');
        break;

      // ========== 版本 32：chat_messages 改存完整 agent message ==========
      // 破坏性迁移：旧数据（segmentsJson / orderIndex）直接丢弃，不做兼容。
      // 设计变更：DB 直接存 agent 内部 ChatMessage（含 role:'tool' / role:'system' 压缩提示 /
      //   toolCalls / toolCallId / agentMsgIndex），hydrate 时 1:1 还原，不再从 UI 视角重建。
      // 解决：跨会话续聊工具结果丢失、压缩后无法重建、_buildHistoryAndOwners 对齐漂移。
      case 32:
        // foreign_keys 由 v31 的 PRAGMA（同连接内已开启）或 _onConfigure 负责开启。
        // 旧表结构不兼容（缺 toolCallsJson/toolCallId/agentMsgIndex，多 segmentsJson/orderIndex），
        // 直接 DROP + CREATE 重建。旧会话消息全部清空，chat_sessions 行保留。
        await db.execute('DROP TABLE IF EXISTS chat_messages');
        await db.execute('''
        CREATE TABLE IF NOT EXISTS chat_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sessionId INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          toolCallsJson TEXT,
          toolCallId TEXT,
          timestamp INTEGER NOT NULL,
          agentMsgIndex INTEGER NOT NULL,
          FOREIGN KEY (sessionId) REFERENCES chat_sessions(id) ON DELETE CASCADE
        )
      ''');
        // 按 (sessionId, agentMsgIndex ASC) 还原 agent 内部消息顺序。
        // 复用 v31 的索引名 idx_chat_messages_session_order（指向新列 agentMsgIndex），
        // 这样幂等重跑 v1→v32 时，v31 的 _createIndexIfNotExists 查到同名索引已存在而跳过，
        // 不会因表已无 orderIndex 列而报错。
        await _createIndexIfNotExists(
            db, 'idx_chat_messages_session_order', 'chat_messages', 'sessionId, agentMsgIndex ASC');
        _log('迁移 v31 → v32: 重建 chat_messages 表（存完整 agent message，旧消息清空）');
        break;

      // ========== 版本 33：无 schema 变更，有意跳过 ==========

      // ========== 版本 34：统一媒体代理器 ==========
      // 新建 media_items 表（统一管理 AI 生成图/视频 + 用户上传的本地映射）：
      //   - mediaId：统一句柄。AI 生成 = backend task_id；用户上传 = app 本地生成 id。
      //   - kind：'image' | 'video'。source：'text2img' | 'image_to_video' | 'local_upload'。
      //   - localOnly=1 表示用户上传、不可回源、不可被"清空可回源缓存"批量删除。
      // characters 加 avatarMediaId 列（角色头像迁移到 mediaId 体系）；旧 cachedImageUrl
      // 保留兼容，展示层优先读 avatarMediaId、为空时回退 cachedImageUrl，不在迁移中搬文件。
      // 删除废弃的 scene_illustrations 死表（service/repository/widget 早已删除）。
      case 34:
        await db.execute('''
        CREATE TABLE IF NOT EXISTS media_items (
          mediaId TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          source TEXT NOT NULL,
          prompt TEXT,
          modelName TEXT,
          createdAt INTEGER NOT NULL,
          lastAccessedAt INTEGER NOT NULL,
          localBytes INTEGER NOT NULL DEFAULT 0,
          localOnly INTEGER NOT NULL DEFAULT 0
        )
      ''');
        await _createIndexIfNotExists(
            db, 'idx_media_items_kind', 'media_items', 'kind');
        await _createIndexIfNotExists(
            db, 'idx_media_items_last_access', 'media_items', 'lastAccessedAt');
        await _addColumnIfNotExists(db, 'characters', 'avatarMediaId', 'TEXT');
        await db.execute('DROP TABLE IF EXISTS scene_illustrations');
        _log('迁移 v33 → v34: 新建 media_items 表，characters 加 avatarMediaId 列，删除 scene_illustrations 死表');
        break;

      // ========== 版本 35：人物关系图重设计 ==========
      // character_relationships 重建为区间模型(旧表从未被 UI 使用,空表):
      //   - relation_type 存 RelationType 枚举名(替代旧自由文本 relationship_type)
      //   - strength(1-5)/ start_chapter / end_chapter / novel_url
      //   - UNIQUE(source, target, relation_type, start_chapter)
      // characters 加 firstAppearanceChapter(登场章节,0-based,空=§0)。
      case 35:
        await db.execute('DROP TABLE IF EXISTS character_relationships');
        await db.execute('''
        CREATE TABLE character_relationships (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_character_id INTEGER NOT NULL,
          target_character_id INTEGER NOT NULL,
          relation_type TEXT NOT NULL,
          strength INTEGER NOT NULL DEFAULT 3,
          start_chapter INTEGER NOT NULL,
          end_chapter INTEGER,
          description TEXT,
          novel_url TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER,
          FOREIGN KEY (source_character_id) REFERENCES characters(id) ON DELETE CASCADE,
          FOREIGN KEY (target_character_id) REFERENCES characters(id) ON DELETE CASCADE,
          UNIQUE(source_character_id, target_character_id, relation_type, start_chapter)
        )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_rel_source ON character_relationships(source_character_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_rel_target ON character_relationships(target_character_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_rel_novel_chapter ON character_relationships(novel_url, start_chapter, end_chapter)');
        await _addColumnIfNotExists(
            db, 'characters', 'firstAppearanceChapter', 'INTEGER');
        _log('迁移 v34 → v35: 重建 character_relationships 为区间模型, characters 加 firstAppearanceChapter');
        break;

      // ========== 版本 36：小说封面媒体化 ==========
      // bookshelf 加 coverMediaId 列（小说封面迁移到 mediaId 体系）：
      //   - 存 create_images / create_image_to_video 返回的 mediaId
      //   - 由 set_novel_cover 工具写入，NovelCover 命中时走 MediaView 渲染
      // 旧 coverUrl 列保留不动（历史遗留，2026-07-08 爬虫移除后基本为 null）。
      case 36:
        await _addColumnIfNotExists(db, 'bookshelf', 'coverMediaId', 'TEXT');
        _log('迁移 v35 → v36: bookshelf 加 coverMediaId 列');
        break;

      // ========== 版本 37：site_scripts 加 ocr 列（字体反爬 OCR 标记） ==========
      // ocr=1 表示该站点提取器需要 OCR 后处理（番茄小说等 PUA 字体反爬）。
      // 默认 0，所有现有提取器自动是非 OCR 模式，零破坏。
      // 由 save_script 落库时写入；HeadlessWebView service 读取决定是否走 OCR 还原。
      case 37:
        await _addColumnIfNotExists(
            db, 'site_scripts', 'ocr', 'INTEGER NOT NULL DEFAULT 0');
        _log('迁移 v36 → v37: site_scripts 加 ocr 列');
        break;

      // ========== 版本 38：删除 webview 模型下载表 ==========
      // webview 浏览器不再支持下载模型到 /app/models，删除整张表。
      // 已有的 in-flight 任务一并清理（功能不可用，旧任务无意义保留）。
      case 38:
        await db.execute('DROP TABLE IF EXISTS model_download_tasks');
        _log('迁移 v37 → v38: 删除 model_download_tasks 表');
        break;

      // ========== 版本 39：site_scripts 拆 ocr 为两列 ==========
      // 番茄等字体反爬站点，目录页 title/chapter.title 是正常汉字（无 PUA），
      // 正文页 content 才有 PUA。单一 ocr 列被 save_script 分次保存时互相覆盖，
      // 导致 ChapterListService 对正常目录页白跑 OCR、或 ContentService 漏跑 OCR。
      // 拆成 chapter_list_ocr / chapter_content_ocr 两列，各自独立标记。
      // 旧 ocr 列保留不读不写（SQLite < 3.35 不支持 DROP COLUMN，Android < 12 风险）。
      case 39:
        await _addColumnIfNotExists(
            db, 'site_scripts', 'chapter_list_ocr', 'INTEGER NOT NULL DEFAULT 0');
        await _addColumnIfNotExists(db, 'site_scripts', 'chapter_content_ocr',
            'INTEGER NOT NULL DEFAULT 0');
        _log('迁移 v38 → v39: site_scripts 加 chapter_list_ocr / chapter_content_ocr 两列');
        break;
    }
  }

  // ========== 辅助方法 ==========

  /// 修复数据库：重新执行 v1→currentVersion 所有迁移
  ///
  /// 非破坏性操作，仅补全缺失的表/列/索引，不会删除现有数据。
  /// 适用于数据库损坏、缺少表或列的修复场景。
  /// 因为所有迁移都是幂等的，可以安全地重复执行。
  static Future<void> repair(Database db) async {
    _log('开始数据库修复（检查并补全缺失的表/列/索引）...');
    await upgrade(db, 1, currentVersion);
    _log('数据库修复完成');
  }

  /// 安全添加列（如果不存在）
  static Future<void> _addColumnIfNotExists(
      Database db, String table, String column, String type) async {
    try {
      final columns = await db.rawQuery("PRAGMA table_info($table)");
      final hasColumn = columns.any((c) => c['name'] == column);
      if (!hasColumn) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      }
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        '添加列失败: $table.$column - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['migration', 'add_column', 'failed'],
      );
      rethrow;
    }
  }

  /// 安全创建索引（如果不存在）
  ///
  /// [columnExpr] 是索引的列表达式，直接拼入 `ON table(...)`：
  /// - 单列：`'scenarioId'`（向后兼容旧调用）
  /// - 复合列：`'scenarioId, updatedAt DESC'`（不带外层括号，模板会加）
  static Future<void> _createIndexIfNotExists(
      Database db, String indexName, String table, String columnExpr) async {
    try {
      final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name = ?",
          [indexName]);
      if (indexes.isEmpty) {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS $indexName ON $table($columnExpr)');
      }
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        '创建索引失败: $indexName on $table.$columnExpr - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['migration', 'create_index', 'failed'],
      );
      rethrow;
    }
  }

  /// 安全重命名字段（如果旧字段存在且新字段不存在）
  ///
  /// SQLite 不支持直接重命名列，使用重建表的方式实现。
  /// 重建时通过 `PRAGMA table_info` 还原每列的类型 / NOT NULL / 默认值 /
  /// 主键约束，避免旧实现只取列名导致约束丢失（PRIMARY KEY、NOT NULL、
  /// UNIQUE、DEFAULT 全部丢失，重建后的表是"裸列"）。
  static Future<void> _renameColumnIfExists(
    Database db,
    String table,
    String oldColumn,
    String newColumn,
    String newColumnType,
  ) async {
    try {
      // 检查旧字段是否存在，新字段是否不存在
      final tableInfo = await db.rawQuery("PRAGMA table_info($table)");
      final hasOldColumn = tableInfo.any((c) => c['name'] == oldColumn);
      final hasNewColumn = tableInfo.any((c) => c['name'] == newColumn);

      if (!hasOldColumn || hasNewColumn) return;

      // 还原每列的完整定义（列名 + 类型 + 约束），其中目标列替换为新名/新类型。
      final newColumnDefs = <String>[];
      for (final col in tableInfo) {
        final name = col['name'] as String;
        if (name == oldColumn) {
          newColumnDefs.add(_buildColumnDef(newColumn, newColumnType));
        } else {
          newColumnDefs.add(_buildColumnDef(
            name,
            _reconstructColumnDef(col),
          ));
        }
      }

      // 旧列名顺序用于 INSERT ... SELECT * 的列对齐
      final oldColumnList =
          tableInfo.map((c) => c['name'] as String).join(', ');

      await db.execute('''
        CREATE TABLE ${table}_new (
          ${newColumnDefs.join(',\n          ')}
        )
      ''');

      await db.execute('''
        INSERT INTO ${table}_new ($oldColumnList)
        SELECT $oldColumnList FROM $table
      ''');

      await db.execute('DROP TABLE $table');
      await db.execute('ALTER TABLE ${table}_new RENAME TO $table');

      _log('数据库迁移: 重命名 $table.$oldColumn → $newColumn');
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        '重命名字段失败: $table.$oldColumn → $newColumn - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['migration', 'rename_column', 'failed'],
      );
      rethrow;
    }
  }

  /// 从 `PRAGMA table_info` 单行还原列定义字符串（类型 + 约束）。
  ///
  /// `PRAGMA table_info` 每行含 cid/name/type/notnull/dflt_value/pk。
  /// 注意：UNIQUE / 外键等表级约束不在 table_info 中，重建表会丢失它们，
  /// 因此本方法仅还原 PRIMARY KEY / NOT NULL / DEFAULT —— 对内部迁移
  /// 够用；涉及复杂约束的表不应走列重命名路径。
  static String _reconstructColumnDef(Map<String, Object?> col) {
    final type = (col['type'] as String?)?.trim();
    final typePart = (type == null || type.isEmpty) ? '' : type;
    final notNull = (col['notnull'] as int?) == 1;
    final dflt = col['dflt_value'] as String?;
    final pk = (col['pk'] as int?) ?? 0;

    final parts = <String>[typePart];
    if (pk > 0) parts.add('PRIMARY KEY AUTOINCREMENT');
    if (notNull) parts.add('NOT NULL');
    if (dflt != null) parts.add('DEFAULT $dflt');

    // parts[0] 可能是空串（无类型列），过滤后 join
    final def = parts.where((s) => s.isNotEmpty).join(' ');
    return def.isEmpty ? '' : def;
  }

  /// 拼接 "列名 列定义"，空定义时仅返回列名。
  static String _buildColumnDef(String name, String def) {
    return def.isEmpty ? name : '$name $def';
  }

  /// 记录日志（统一使用 LoggerService）
  static void _log(String message) {
    try {
      LoggerService.instance.i(
        message,
        category: LogCategory.database,
        tags: ['migration'],
      );
    } catch (_) {
      // LoggerService 未初始化时静默忽略
    }
  }
}

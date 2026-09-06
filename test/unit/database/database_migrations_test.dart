/// DatabaseMigrations 单元测试 — 真实 SQLite 内存数据库
///
/// 验证数据库迁移逻辑的完整性和幂等性：
/// - createV1Tables 创建正确的基础表结构
/// - upgrade 逐版本迁移 v1→v25
/// - 幂等性：重复执行 upgrade 不报错
/// - repair 能补全缺失的表/列/索引
/// - 关键迁移逻辑验证（v2, v4, v16, v19, v24）
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/database/database_migrations_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:novel_app/core/database/database_migrations.dart';

void main() {
  // 初始化 FFI
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// 创建空数据库（不执行任何迁移）
  Future<Database> createEmptyDb() async {
    return await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );
  }

  group('DatabaseMigrations', () {
    group('createV1Tables', () {
      test('应创建所有 v1 基础表', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);

        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
        final tableNames = tables.map((t) => t['name'] as String).toSet();

        expect(tableNames.contains('bookshelf'), isTrue);
        expect(tableNames.contains('chapter_cache'), isTrue);
        expect(tableNames.contains('novel_chapters'), isTrue);
        expect(tableNames.contains('characters'), isTrue);
        expect(tableNames.contains('scene_illustrations'), isTrue);

        await db.close();
      });

      test('应创建 v1 索引', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);

        final indexes = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name");
        final indexNames = indexes.map((i) => i['name'] as String).toSet();

        expect(indexNames.contains('idx_chapter_cache_chapter_url'), isTrue);
        expect(indexNames.contains('idx_chapter_cache_novel_url'), isTrue);
        expect(indexNames.contains('idx_novel_chapters_novel_url'), isTrue);

        await db.close();
      });

      test('bookshelf 表应包含 v1 基础字段', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);

        final columns = await db.rawQuery("PRAGMA table_info(bookshelf)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();

        expect(columnNames.contains('id'), isTrue);
        expect(columnNames.contains('title'), isTrue);
        expect(columnNames.contains('author'), isTrue);
        expect(columnNames.contains('url'), isTrue);
        expect(columnNames.contains('coverUrl'), isTrue);
        expect(columnNames.contains('description'), isTrue);
        expect(columnNames.contains('addedAt'), isTrue);

        await db.close();
      });

      test('chapter_cache 表应包含 v1 基础字段', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);

        final columns = await db.rawQuery("PRAGMA table_info(chapter_cache)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();

        expect(columnNames.contains('id'), isTrue);
        expect(columnNames.contains('novelUrl'), isTrue);
        expect(columnNames.contains('chapterUrl'), isTrue);
        expect(columnNames.contains('title'), isTrue);
        expect(columnNames.contains('content'), isTrue);
        expect(columnNames.contains('chapterIndex'), isTrue);
        expect(columnNames.contains('cachedAt'), isTrue);

        await db.close();
      });

      test('characters 表应包含 v1 基础字段', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);

        final columns = await db.rawQuery("PRAGMA table_info(characters)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();

        expect(columnNames.contains('id'), isTrue);
        expect(columnNames.contains('novelUrl'), isTrue);
        expect(columnNames.contains('name'), isTrue);
        expect(columnNames.contains('age'), isTrue);
        expect(columnNames.contains('gender'), isTrue);
        expect(columnNames.contains('personality'), isTrue);
        expect(columnNames.contains('createdAt'), isTrue);

        await db.close();
      });
    });

    group('upgrade 完整迁移 v1→最新', () {
      test('从 v1 升级到最新版本应成功', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

        // 验证所有表都存在
        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
        final tableNames = tables.map((t) => t['name'] as String).toSet();

        final expectedTables = [
          'bookshelf',
          'chapter_cache',
          'novel_chapters',
          'characters',
          'media_items',
          'outlines',
          'chat_scenes',
          'character_relationships',
          'bookshelves',
          'novel_bookshelves',
          'prompt_history',
          'prompt_tag_categories',
          'prompt_tags',
          'site_scripts',
          'chapter_versions',
        ];

        for (final table in expectedTables) {
          expect(tableNames.contains(table), isTrue,
              reason: '表 $table 应该存在');
        }

        // v34 删除了 scene_illustrations 死表
        expect(tableNames.contains('scene_illustrations'), isFalse,
            reason: 'scene_illustrations 在 v34 已被删除');

        await db.close();
      });

      test('升级后 novels 视图应存在', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

        final views = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='view' AND name='novels'");
        expect(views.isNotEmpty, isTrue);

        await db.close();
      });
    });

    group('幂等性', () {
      test('重复执行 upgrade 不应报错', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);

        // 第一次升级
        await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

        // 第二次升级（模拟重复执行）
        await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

        // 不应抛出异常，到这里即通过
        await db.close();
      });

      test('重复执行 createV1Tables 可通过 upgrade 再次执行', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        // upgrade 可以安全重复执行（所有迁移步骤都是幂等的）
        await DatabaseMigrations.upgrade(db, 1, 4);

        // 不应抛出异常
        await db.close();
      });

      test('repair 应可安全重复执行', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

        // 第一次 repair
        await DatabaseMigrations.repair(db);
        // 第二次 repair
        await DatabaseMigrations.repair(db);

        // 不应抛出异常
        await db.close();
      });
    });

    group('关键迁移逻辑', () {
      group('v2 — 用户插入章节字段', () {
        test('应添加 isUserInserted 和 insertedAt 列', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 2);

          final columns =
              await db.rawQuery("PRAGMA table_info(novel_chapters)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();

          expect(columnNames.contains('isUserInserted'), isTrue);
          expect(columnNames.contains('insertedAt'), isTrue);

          await db.close();
        });
      });

      group('v4 — 角色表重建', () {
        test('应通过 ALTER TABLE 添加 updatedAt 列', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 4);

          final columns = await db.rawQuery("PRAGMA table_info(characters)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();

          // v4 通过 _addColumnIfNotExists 添加 updatedAt
          expect(columnNames.contains('updatedAt'), isTrue);

          await db.close();
        });

        test('升级到 v5 应添加 facePrompts 和 bodyPrompts', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 5);

          final columns = await db.rawQuery("PRAGMA table_info(characters)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();

          expect(columnNames.contains('facePrompts'), isTrue);
          expect(columnNames.contains('bodyPrompts'), isTrue);

          await db.close();
        });
      });

      group('v11 — 章节已读时间戳', () {
        test('应添加 readAt 列', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 11);

          final columns =
              await db.rawQuery("PRAGMA table_info(novel_chapters)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();

          expect(columnNames.contains('readAt'), isTrue);

          await db.close();
        });
      });

      group('v16 — 多书架功能', () {
        test('应创建 bookshelves 和 novel_bookshelves 表', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 16);

          final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
          final tableNames = tables.map((t) => t['name'] as String).toSet();

          expect(tableNames.contains('bookshelves'), isTrue);
          expect(tableNames.contains('novel_bookshelves'), isTrue);

          await db.close();
        });

        test('应插入默认书架数据（全部小说、我的收藏）', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 16);

          final result =
              await db.rawQuery('SELECT * FROM bookshelves ORDER BY id');
          expect(result.length, 2);
          expect(result[0]['name'], '全部小说');
          expect(result[0]['is_system'], 1);
          expect(result[1]['name'], '我的收藏');
          expect(result[1]['is_system'], 1);

          await db.close();
        });

        test('重复执行 v16 迁移不应重复插入默认书架', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 16);

          // 模拟重复执行 v16
          await DatabaseMigrations.upgrade(db, 1, 16);

          final result =
              await db.rawQuery('SELECT * FROM bookshelves ORDER BY id');
          expect(result.length, 2);

          await db.close();
        });
      });

      group('v18 — AI伴读标记字段', () {
        test('应添加 isAccompanied 列到 chapter_cache 和 novel_chapters',
            () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 18);

          var columns = await db.rawQuery("PRAGMA table_info(chapter_cache)");
          var columnNames = columns.map((c) => c['name'] as String).toSet();
          expect(columnNames.contains('isAccompanied'), isTrue);

          columns = await db.rawQuery("PRAGMA table_info(novel_chapters)");
          columnNames = columns.map((c) => c['name'] as String).toSet();
          expect(columnNames.contains('isAccompanied'), isTrue);

          await db.close();
        });
      });

      group('v19 — 字段重命名 ai_accompanied → isAccompanied', () {
        test('从 v15 升级到 v19 应保留 isAccompanied 字段', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 15);

          // 先插入测试数据（v15 有 ai_accompanied 字段）
          await db.execute('''
            INSERT INTO chapter_cache (novelUrl, chapterUrl, title, content, chapterIndex, cachedAt, ai_accompanied)
            VALUES ('test_url', 'ch1', '测试章节', '内容', 0, 1234567890, 1)
          ''');

          // 升级到 v19（v18 添加 isAccompanied，v19 检测到新列已存在则跳过重命名）
          await DatabaseMigrations.upgrade(db, 15, 19);

          // 验证字段 isAccompanied 存在
          final columns =
              await db.rawQuery("PRAGMA table_info(chapter_cache)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();
          expect(columnNames.contains('isAccompanied'), isTrue);

          // 验证原数据仍存在（保留 ai_accompanied=1 的记录）
          final result = await db.rawQuery(
              'SELECT novelUrl, ai_accompanied FROM chapter_cache');
          expect(result.length, 1);
          expect(result.first['novelUrl'], 'test_url');

          await db.close();
        });

        test('v18 添加 isAccompanied 列（默认值为 0）', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 18);

          // 验证 isAccompanied 列已添加到 chapter_cache
          final columns =
              await db.rawQuery("PRAGMA table_info(chapter_cache)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();
          expect(columnNames.contains('isAccompanied'), isTrue);

          await db.close();
        });
      });

      group('v22 — 提示词历史表', () {
        test('应创建 prompt_history 表', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 22);

          final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
          final tableNames = tables.map((t) => t['name'] as String).toSet();
          expect(tableNames.contains('prompt_history'), isTrue);

          await db.close();
        });
      });

      group('v23 — 提示词标签分类和标签表', () {
        test('应创建 prompt_tag_categories 和 prompt_tags 表', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 23);

          final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
          final tableNames = tables.map((t) => t['name'] as String).toSet();
          expect(tableNames.contains('prompt_tag_categories'), isTrue);
          expect(tableNames.contains('prompt_tags'), isTrue);

          await db.close();
        });
      });

      group('v24 — 移除 prompt_tags UNIQUE 约束', () {
        test('升级到 v24 后应允许同 category_id 下同名标签', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 24);

          // 插入同 category_id 下同名标签（v24 应允许）
          final now = DateTime.now().millisecondsSinceEpoch;
          await db.execute('''
            INSERT INTO prompt_tags (category_id, name, prompt_text, sort_order, created_at, updated_at)
            VALUES (1, '测试标签', '提示词1', 0, $now, $now)
          ''');
          await db.execute('''
            INSERT INTO prompt_tags (category_id, name, prompt_text, sort_order, created_at, updated_at)
            VALUES (1, '测试标签', '提示词2', 1, $now, $now)
          ''');

          final result =
              await db.rawQuery('SELECT COUNT(*) as count FROM prompt_tags');
          expect(result.first['count'], 2);

          await db.close();
        });
      });

      group('v25 — 站点脚本表', () {
        test('应创建 site_scripts 表', () async {
          final db = await createEmptyDb();
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, 25);

          final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
          final tableNames = tables.map((t) => t['name'] as String).toSet();
          expect(tableNames.contains('site_scripts'), isTrue);

          final columns =
              await db.rawQuery("PRAGMA table_info(site_scripts)");
          final columnNames = columns.map((c) => c['name'] as String).toSet();
          expect(columnNames.contains('id'), isTrue);
          expect(columnNames.contains('domain'), isTrue);
          expect(columnNames.contains('chapter_list_js'), isTrue);
          expect(columnNames.contains('chapter_content_js'), isTrue);

          await db.close();
        });
      });
    });

    group('repair 修复功能', () {
      test('repair 应补全缺失的表', () async {
        final db = await createEmptyDb();
        // 只创建 v1 基础表，不执行升级
        await DatabaseMigrations.createV1Tables(db);

        // repair 应补全所有缺失的表
        await DatabaseMigrations.repair(db);

        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
        final tableNames = tables.map((t) => t['name'] as String).toSet();

        expect(tableNames.contains('outlines'), isTrue);
        expect(tableNames.contains('chat_scenes'), isTrue);
        expect(tableNames.contains('character_relationships'), isTrue);
        expect(tableNames.contains('bookshelves'), isTrue);

        await db.close();
      });
    });

    group('currentVersion', () {
      test('currentVersion 应为 DatabaseMigrations.currentVersion', () {
        // 不锁死具体值，只保证可读且不低于当前已知版本（避免每次升版本都改这里）。
        expect(DatabaseMigrations.currentVersion, greaterThanOrEqualTo(37));
      });
    });

    group('v26 — prompt_history 标签快照列', () {
      test('prompt_history 表应包含 tag_group_ids 列', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

        final columns =
            await db.rawQuery("PRAGMA table_info(prompt_history)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();

        expect(columnNames.contains('tag_group_ids'), isTrue,
            reason: 'v26 迁移应添加 tag_group_ids 列');

        await db.close();
      });

      test('从 v25 升级到 v26 应添加 tag_group_ids 列', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 25); // 先到 v25

        // 确认 v25 时没有新列（或未执行 v26 迁移）
        await DatabaseMigrations.upgrade(db, 25, 26); // 只执行 v25→v26

        final columns =
            await db.rawQuery("PRAGMA table_info(prompt_history)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        expect(columnNames.contains('tag_group_ids'), isTrue);

        await db.close();
      });
    });

    group('v30 — 章节版本历史表', () {
      test('应创建 chapter_versions 表', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 30);

        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
        final tableNames = tables.map((t) => t['name'] as String).toSet();
        expect(tableNames.contains('chapter_versions'), isTrue);

        await db.close();
      });

      test('chapter_versions 表应包含正确字段', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 30);

        final columns =
            await db.rawQuery("PRAGMA table_info(chapter_versions)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();

        expect(columnNames.contains('id'), isTrue);
        expect(columnNames.contains('chapterUrl'), isTrue);
        expect(columnNames.contains('content'), isTrue);
        expect(columnNames.contains('source'), isTrue);
        expect(columnNames.contains('createdAt'), isTrue);
        expect(columnNames.contains('contentLength'), isTrue);

        await db.close();
      });

      test('应创建索引', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 30);

        final indexes = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_chapter_versions%'");
        final indexNames = indexes.map((i) => i['name'] as String).toSet();

        expect(indexNames.contains('idx_chapter_versions_chapter_url'), isTrue);
        expect(indexNames.contains('idx_chapter_versions_created_at'), isTrue);

        await db.close();
      });
    });

    group('v31 — AI 对话会话历史', () {
      test('应创建 chat_sessions 和 chat_messages 两张表', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 31);

        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'");
        final tableNames = tables.map((t) => t['name'] as String).toSet();

        expect(tableNames.contains('chat_sessions'), isTrue);
        expect(tableNames.contains('chat_messages'), isTrue);

        await db.close();
      });

      test('chat_sessions 应包含完整字段', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 31);

        final columns = await db.rawQuery('PRAGMA table_info(chat_sessions)');
        final columnNames = columns.map((c) => c['name'] as String).toSet();

        expect(columnNames.contains('id'), isTrue);
        expect(columnNames.contains('scenarioId'), isTrue);
        expect(columnNames.contains('title'), isTrue);
        expect(columnNames.contains('createdAt'), isTrue);
        expect(columnNames.contains('updatedAt'), isTrue);
        expect(columnNames.contains('currentNovelId'), isTrue);
        expect(columnNames.contains('currentNovelTitle'), isTrue);

        await db.close();
      });

      test('chat_messages 应包含完整字段 + FK 到 chat_sessions', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 31);

        final columns = await db.rawQuery('PRAGMA table_info(chat_messages)');
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        expect(columnNames.contains('id'), isTrue);
        expect(columnNames.contains('sessionId'), isTrue);
        expect(columnNames.contains('role'), isTrue);
        expect(columnNames.contains('content'), isTrue);
        expect(columnNames.contains('segmentsJson'), isTrue);
        expect(columnNames.contains('timestamp'), isTrue);
        expect(columnNames.contains('orderIndex'), isTrue);

        // FK 应指向 chat_sessions.id 且启用 CASCADE
        final fks = await db.rawQuery('PRAGMA foreign_key_list(chat_messages)');
        expect(fks, isNotEmpty);
        final fk = fks.first;
        expect(fk['table'], 'chat_sessions');
        expect(fk['from'], 'sessionId');
        expect((fk['on_delete']?.toString() ?? '').toLowerCase().contains('cascade'), isTrue);

        await db.close();
      });

      test('应创建会话列表和消息顺序索引', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 31);

        final indexes = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_chat_%'");
        final indexNames = indexes.map((i) => i['name'] as String).toSet();
        expect(indexNames.contains('idx_chat_sessions_scenario_updated'), isTrue);
        expect(indexNames.contains('idx_chat_messages_session'), isTrue);
        expect(
            indexNames.contains('idx_chat_sessions_scenario_updated_desc'),
            isTrue);
        expect(indexNames.contains('idx_chat_messages_session_order'), isTrue);

        await db.close();
      });

      test('PRAGMA foreign_keys 已被打开迁移自身开启', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 31);
        final r = await db.rawQuery('PRAGMA foreign_keys');
        // PRAGMA foreign_keys 返回 0/1 列
        expect(r.first.values.first, 1);
        await db.close();
      });
    });

    group('v32 — chat_messages 统一历史模型', () {
      test('升级到 v32 后 chat_messages 含新列且无 segmentsJson/orderIndex', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 32);

        final columns = await db.rawQuery('PRAGMA table_info(chat_messages)');
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        expect(columnNames.contains('id'), isTrue);
        expect(columnNames.contains('sessionId'), isTrue);
        expect(columnNames.contains('role'), isTrue);
        expect(columnNames.contains('content'), isTrue);
        expect(columnNames.contains('toolCallsJson'), isTrue);
        expect(columnNames.contains('toolCallId'), isTrue);
        expect(columnNames.contains('agentMsgIndex'), isTrue);
        // 旧列已被 DROP 重建移除
        expect(columnNames.contains('segmentsJson'), isFalse);
        expect(columnNames.contains('orderIndex'), isFalse);

        // FK 仍指向 chat_sessions 且 CASCADE
        final fks = await db.rawQuery('PRAGMA foreign_key_list(chat_messages)');
        expect(fks, isNotEmpty);
        final fk = fks.first;
        expect(fk['table'], 'chat_sessions');
        expect(
            (fk['on_delete']?.toString() ?? '').toLowerCase().contains('cascade'),
            isTrue);

        await db.close();
      });

      test('v31 → v32 迁移丢弃旧消息行（破坏性迁移）', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 31);
        // 在 v31 表里塞一条旧格式数据
        await db.insert('chat_sessions', {
          'scenarioId': 'writing',
          'title': '旧会话',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
        await db.insert('chat_messages', {
          'sessionId': 1,
          'role': 'user',
          'content': '旧消息',
          'segmentsJson': '[]',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'orderIndex': 0,
        });
        // 升级到 v32：DROP + CREATE
        await DatabaseMigrations.upgrade(db, 31, 32);
        final cnt = await db.rawQuery(
            'SELECT COUNT(*) AS c FROM chat_messages WHERE sessionId = 1');
        expect((cnt.first['c'] as int?) ?? 0, 0);
        await db.close();
      });

      test('幂等：v1→v32 反复执行不报错', () async {
        final db = await createEmptyDb();
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, 32);
        // 再跑一次全量，v31 建基于 orderIndex 的索引已被 v32 同名索引覆盖，不应报错
        await DatabaseMigrations.upgrade(db, 1, 32);
        final cnt = await db.rawQuery(
            "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='index' AND name='idx_chat_messages_session_order'");
        expect((cnt.first['c'] as int?) ?? 0, 1);
        await db.close();
      });
    });
  });
}

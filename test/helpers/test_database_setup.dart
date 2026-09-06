import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:novel_app/core/database/database_migrations.dart';

/// 测试数据库设置工具
///
/// 提供内存数据库创建和初始化功能，用于集成测试。
/// 复用 DatabaseMigrations 的迁移逻辑，确保测试数据库结构与生产环境完全一致。
class TestDatabaseSetup {
  static bool _initialized = false;

  /// 初始化测试数据库工厂
  static void init() {
    if (!_initialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _initialized = true;
    }
  }

  /// 创建内存数据库并初始化表结构
  ///
  /// 复用 DatabaseMigrations 的迁移逻辑：
  /// 1. 调用 DatabaseMigrations.createV1Tables(db) 创建 v1 基础表
  /// 2. 调用 DatabaseMigrations.upgrade(db, 1, 21) 执行所有迁移
  /// 确保测试环境与生产环境的数据库结构完全一致。
  static Future<Database> createInMemoryDatabase() async {
    init();

    final db = await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );

    await DatabaseMigrations.createV1Tables(db);
    await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

    return db;
  }

  /// 清空所有表数据（保留表结构）
  ///
  /// 清理顺序：先清带 FK 引用子表，再清被引用表，避免 FK CASCADE 误删。
  static Future<void> clearAllTables(Database db) async {
    // 先关 FK，避免清 sessions 时 CASCADE 删 messages 触发 warning 噪音
    await db.delete('chat_messages');
    await db.delete('chat_sessions');
    await db.delete('bookshelf');
    await db.delete('chapter_cache');
    await db.delete('novel_chapters');
    await db.delete('characters');
    await db.delete('media_items');
    await db.delete('bookshelves');
    await db.delete('novel_bookshelves');
    await db.delete('character_relationships');
    await db.delete('outlines');
    await db.delete('chat_scenes');
    await db.delete('prompt_history');
    await db.delete('prompt_tag_history');
    await db.delete('prompt_tags');
    await db.delete('prompt_tag_categories');
    await db.delete('site_scripts');
    await db.delete('agent_memory');
    await db.delete('llm_configs');
    await db.delete('chapter_versions');
  }

  /// 统计表中的记录数（用于调试）
  static Future<Map<String, int>> getTableStats(Database db) async {
    final tables = [
      'bookshelf',
      'chapter_cache',
      'novel_chapters',
      'characters',
      'media_items',
      'bookshelves',
      'novel_bookshelves',
      'character_relationships',
      'outlines',
      'chat_scenes',
      'prompt_history',
      'prompt_tag_history',
      'prompt_tags',
      'prompt_tag_categories',
      'site_scripts',
      'agent_memory',
      'llm_configs',
      'chapter_versions',
      'chat_sessions',
      'chat_messages',
    ];

    final stats = <String, int>{};
    for (final table in tables) {
      final result =
          await db.rawQuery('SELECT COUNT(*) as count FROM $table');
      stats[table] = result.first['count'] as int? ?? 0;
    }

    return stats;
  }

  /// 验证数据库结构是否完整
  ///
  /// 返回所有缺失的表名列表，如果为空则表示结构完整
  static Future<List<String>> validateSchema(Database db) async {
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
      'prompt_tag_history',
      'prompt_tags',
      'prompt_tag_categories',
      'site_scripts',
      'agent_memory',
      'llm_configs',
      'chapter_versions',
      'chat_sessions',
      'chat_messages',
    ];

    final existingTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'");
    final existingTableNames =
        existingTables.map((r) => r['name'] as String).toSet();

    return expectedTables
        .where((table) => !existingTableNames.contains(table))
        .toList();
  }
}
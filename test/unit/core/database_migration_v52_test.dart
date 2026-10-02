/// v52 迁移测试：新建 text_games 表（文字游戏）
///
/// 验证：
/// - 升级路径 v51 → v52：表和索引被创建
/// - 新装路径：游戏行可正常写入并按 chatSessionId 查询、按 lastPlayedAt 排序
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openAtVersion(int version) => openDatabase(
        inMemoryDatabasePath,
        version: version,
        singleInstance: false,
        onCreate: (db, v) async {
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, v);
        },
      );

  test('升级路径 v51 → v52：text_games 表和索引被创建', () async {
    final db = await openAtVersion(51);

    final tablesBefore = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='text_games'");
    expect(tablesBefore, isEmpty, reason: 'v51 不应存在 text_games 表');

    await DatabaseMigrations.upgrade(db, 51, DatabaseMigrations.currentVersion);

    final tablesAfter = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='text_games'");
    expect(tablesAfter, hasLength(1));

    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_text_games_session'");
    expect(indexes, hasLength(1));
    await db.close();
  });

  test('新装路径：游戏行可写入、按 chatSessionId 查询、按 lastPlayedAt 排序', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert('text_games', {
      'title': '游戏A',
      'sourceType': 'novel',
      'sourceNovelId': 1,
      'settingsJson': '{"worldview":"修仙世界"}',
      'status': 'active',
      'chatSessionId': 11,
      'lastPlayedAt': now - 1000,
      'createdAt': now,
      'updatedAt': now,
    });
    await db.insert('text_games', {
      'title': '游戏B',
      'sourceType': 'custom',
      'settingsJson': '{"worldview":"都市"}',
      'status': 'active',
      'chatSessionId': 12,
      'lastPlayedAt': now,
      'createdAt': now,
      'updatedAt': now,
    });
    // 从未游玩过的游戏排最后（COALESCE 回退 createdAt）
    await db.insert('text_games', {
      'title': '游戏C',
      'sourceType': 'custom',
      'settingsJson': '{}',
      'status': 'active',
      'chatSessionId': 13,
      'createdAt': now - 5000,
      'updatedAt': now - 5000,
    });

    final rows = await db.query('text_games',
        orderBy: 'COALESCE(lastPlayedAt, createdAt) DESC, createdAt DESC');
    expect(rows.map((r) => r['title']), ['游戏B', '游戏A', '游戏C']);

    final bySession = await db.query('text_games',
        where: 'chatSessionId = ?', whereArgs: [12]);
    expect(bySession, hasLength(1));
    expect(bySession.first['sourceNovelId'], isNull);
    await db.close();
  });
}

/// v50 迁移测试：新建 character_images 表（角色图集）
///
/// 验证：
/// - 升级路径 v49 → v50：表和索引被创建
/// - 新装路径：图集条目可正常写入并按 characterId + sort 查询
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

  test('升级路径 v49 → v50：character_images 表和索引被创建', () async {
    final db = await openAtVersion(49);

    final tablesBefore = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='character_images'");
    expect(tablesBefore, isEmpty, reason: 'v49 不应存在 character_images 表');

    await DatabaseMigrations.upgrade(db, 49, DatabaseMigrations.currentVersion);

    final tablesAfter = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='character_images'");
    expect(tablesAfter, hasLength(1));

    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_character_images_character'");
    expect(indexes, hasLength(1));
    await db.close();
  });

  test('新装路径：图集条目可写入并按 characterId 查询、按 sort 排序', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert('character_images', {
      'characterId': 1,
      'mediaId': 'local_a',
      'sort': 1,
      'createdAt': now,
    });
    await db.insert('character_images', {
      'characterId': 1,
      'mediaId': 'local_b',
      'sort': 0,
      'createdAt': now,
    });
    await db.insert('character_images', {
      'characterId': 2,
      'mediaId': 'local_c',
      'sort': 0,
      'createdAt': now,
    });

    final rowsOf1 = await db.query('character_images',
        where: 'characterId = ?',
        whereArgs: [1],
        orderBy: 'sort ASC, id ASC');
    expect(rowsOf1.map((r) => r['mediaId']), ['local_b', 'local_a']);

    final rowsOf2 = await db.query('character_images',
        where: 'characterId = ?', whereArgs: [2]);
    expect(rowsOf2, hasLength(1));
    await db.close();
  });
}

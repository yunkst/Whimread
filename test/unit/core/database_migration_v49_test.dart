/// v49 迁移测试：bookshelf 加 lastReadAnchor 列（章内阅读位置锚点）
///
/// 验证：
/// - 升级路径 v48 → v49：lastReadAnchor 列被添加
/// - 存量行默认 NULL（无锚点 = 不恢复，兼容旧数据语义）
/// - 新装路径：锚点 JSON 可正常写入并按列读回
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

  test('升级路径 v48 → v49：bookshelf 的 lastReadAnchor 列被添加', () async {
    final db = await openAtVersion(48);

    final columnsBefore = await db.rawQuery("PRAGMA table_info(bookshelf)");
    final namesBefore = columnsBefore.map((c) => c['name']).toSet();
    expect(namesBefore, isNot(contains('lastReadAnchor')),
        reason: 'v48 不应存在 lastReadAnchor');

    await DatabaseMigrations.upgrade(db, 48, DatabaseMigrations.currentVersion);

    final columnsAfter = await db.rawQuery("PRAGMA table_info(bookshelf)");
    final namesAfter = columnsAfter.map((c) => c['name']).toSet();
    expect(namesAfter, contains('lastReadAnchor'));
    await db.close();
  });

  test('升级路径：存量书架行 lastReadAnchor 默认 NULL', () async {
    final db = await openAtVersion(48);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('bookshelf', {
      'title': '旧书',
      'author': '作者',
      'url': 'https://example.com/book/1',
      'addedAt': now,
      'lastReadChapter': 3,
      'lastReadTime': now,
    });

    await DatabaseMigrations.upgrade(db, 48, DatabaseMigrations.currentVersion);

    final rows = await db.query('bookshelf');
    expect(rows.single['lastReadAnchor'], isNull);
    expect(rows.single['lastReadChapter'], 3);
    await db.close();
  });

  test('新装路径：lastReadAnchor JSON 写入后可按列读回', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;
    const anchorJson =
        '{"u":"https://example.com/book/1#ch9","p":42,"r":"0.350"}';

    await db.insert('bookshelf', {
      'title': '新书',
      'author': '作者',
      'url': 'https://example.com/book/1',
      'addedAt': now,
      'lastReadAnchor': anchorJson,
    });

    final rows = await db.query(
      'bookshelf',
      columns: ['lastReadAnchor'],
      where: 'url = ?',
      whereArgs: ['https://example.com/book/1'],
    );
    expect(rows.single['lastReadAnchor'], anchorJson);
    await db.close();
  });
}

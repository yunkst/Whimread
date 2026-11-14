/// v58 迁移测试：bookshelf 加番外三列（isSideStory/anchorNovelUrl/anchorChapterUrl）
///
/// 验证：
/// - 升级路径 v57 → v58：三列被创建，存量行默认值语义正确（主线行 isSideStory=0）
/// - 新装路径：番外行三列可写入并读回
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

  Future<Set<String>> bookshelfColumns(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(bookshelf)');
    return rows.map((r) => r['name'] as String).toSet();
  }

  test('升级路径 v57 → v58：三列被创建', () async {
    final db = await openAtVersion(57);

    final before = await bookshelfColumns(db);
    expect(before.contains('isSideStory'), isFalse,
        reason: 'v57 不应存在 isSideStory 列');
    expect(before.contains('anchorNovelUrl'), isFalse);
    expect(before.contains('anchorChapterUrl'), isFalse);

    await DatabaseMigrations.upgrade(db, 57, DatabaseMigrations.currentVersion);

    final after = await bookshelfColumns(db);
    expect(after, containsAll(
        ['isSideStory', 'anchorNovelUrl', 'anchorChapterUrl']));
    await db.close();
  });

  test('升级路径：存量主线行默认 isSideStory=0，锚点列为 null', () async {
    final db = await openAtVersion(57);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('bookshelf', {
      'title': '存量主线',
      'author': '作者',
      'url': 'https://example.com/old',
      'addedAt': now,
    });

    await DatabaseMigrations.upgrade(db, 57, DatabaseMigrations.currentVersion);

    final rows = await db.query(
      'bookshelf',
      where: 'url = ?',
      whereArgs: ['https://example.com/old'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['isSideStory'], 0,
        reason: '存量行必须是主线（isSideStory=0），保证书架过滤不误伤');
    expect(rows.single['anchorNovelUrl'], isNull);
    expect(rows.single['anchorChapterUrl'], isNull);
    await db.close();
  });

  test('新装路径：番外行三列可写入并读回', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;

    // 主线 + 挂在主线某章的番外
    await db.insert('bookshelf', {
      'title': '主线小说',
      'author': '作者',
      'url': 'https://example.com/main',
      'addedAt': now,
    });
    final sideStoryId = await db.insert('bookshelf', {
      'title': '闺蜜往事',
      'author': '作者',
      'url': 'custom://sidestory/$now',
      'addedAt': now,
      'isSideStory': 1,
      'anchorNovelUrl': 'https://example.com/main',
      'anchorChapterUrl': 'https://example.com/main#ch12',
    });

    final sideStory =
        await db.query('bookshelf', where: 'id = ?', whereArgs: [sideStoryId]);
    expect(sideStory.single['isSideStory'], 1);
    expect(sideStory.single['anchorNovelUrl'], 'https://example.com/main');
    expect(sideStory.single['anchorChapterUrl'], 'https://example.com/main#ch12');

    // 主线行不受影响
    final main = await db.query(
      'bookshelf',
      where: 'url = ?',
      whereArgs: ['https://example.com/main'],
    );
    expect(main.single['isSideStory'], 0);
    await db.close();
  });
}

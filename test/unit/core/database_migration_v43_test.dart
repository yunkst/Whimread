/// v43 迁移测试：重建 novels 视图覆盖 bookshelf 所有列
///
/// 背景：v20 创建的 novels 视图列清单固定，v36 给 bookshelf 加 coverMediaId
/// 后视图未重建，导致 novel_repository.getNovels() 读到的 coverMediaId 恒为 null。
/// v43 用 SELECT * FROM bookshelf 重建视图，并把「视图列 = 表列」固化为回归测试，
/// 防止未来给 bookshelf 加列时再次漂移。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;

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

  /// 取视图/表的列名集合
  Future<Set<String>> columnNames(Database db, String name) async {
    final cols = await db.rawQuery('PRAGMA table_info($name)');
    return cols.map((c) => c['name'] as String).toSet();
  }

  test('v43 后 novels 视图列与 bookshelf 表列完全一致（防漂移）', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final viewCols = await columnNames(db, 'novels');
    final tableCols = await columnNames(db, 'bookshelf');
    expect(viewCols, tableCols);
    await db.close();
  });

  test('新装路径：coverMediaId 经 novels 视图可读', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('bookshelf', {
      'title': '测试小说',
      'author': '作者',
      'url': 'https://example.com/book/1',
      'addedAt': now,
      'coverMediaId': 'media-abc',
    });

    final rows = await db.query('novels');
    expect(rows, hasLength(1));
    expect(rows.first['coverMediaId'], 'media-abc');
    await db.close();
  });

  test('升级路径 v42 → v43：旧视图缺列被重建修复', () async {
    final db = await openAtVersion(42);

    // 确认 v42 时视图确实缺 coverMediaId（回归前提）
    final v42Cols = await columnNames(db, 'novels');
    expect(v42Cols.contains('coverMediaId'), isFalse);

    await DatabaseMigrations.upgrade(db, 42, DatabaseMigrations.currentVersion);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('bookshelf', {
      'title': '升级小说',
      'author': '作者',
      'url': 'https://example.com/book/2',
      'addedAt': now,
      'coverMediaId': 'media-xyz',
    });

    final rows = await db.query('novels');
    expect(rows, hasLength(1));
    expect(rows.first['coverMediaId'], 'media-xyz');
    await db.close();
  });

  test('currentVersion >= 43（v43 novels 视图迁移已包含）', () {
    expect(DatabaseMigrations.currentVersion, greaterThanOrEqualTo(43));
  });

  test('NovelRepository.getNovels 能读到 coverMediaId（实际消费方）', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);
    final repo = NovelRepository(dbConnection: DatabaseConnection.forTesting(db));

    await repo.addToBookshelf(Novel(
      title: '仓储层小说',
      author: '作者',
      url: 'https://example.com/book/3',
      coverMediaId: 'media-repo',
    ));

    final novels = await repo.getNovels();
    expect(novels, hasLength(1));
    expect(novels.first.coverMediaId, 'media-repo');
    await db.close();
  });
}

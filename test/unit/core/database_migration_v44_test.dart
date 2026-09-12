/// v44 迁移测试：创建 paragraph_annotations 表（段落标注）
///
/// 验证：
/// - 升级路径 v43 → v44：表被创建（v43 时不存在）
/// - 新装路径：UNIQUE(chapterUrl, paragraphIndex) 约束生效（同段落仅一条）
/// - 章节级索引存在
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_migrations.dart';
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

  Map<String, dynamic> row({
    String novelUrl = 'https://example.com/book/1',
    String chapterUrl = 'https://example.com/book/1/chapter/1',
    int paragraphIndex = 0,
  }) =>
      {
        'novelUrl': novelUrl,
        'chapterUrl': chapterUrl,
        'paragraphIndex': paragraphIndex,
        'paragraphPreview': '段落预览',
        'content': '标注内容',
        'createdAt': 1000,
        'updatedAt': 1000,
      };

  test('升级路径 v43 → v44：paragraph_annotations 表被创建', () async {
    final db = await openAtVersion(43);

    // 回归前提：v43 时表不存在
    final tablesBefore = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'paragraph_annotations'",
    );
    expect(tablesBefore, isEmpty);

    await DatabaseMigrations.upgrade(db, 43, DatabaseMigrations.currentVersion);

    final tablesAfter = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'paragraph_annotations'",
    );
    expect(tablesAfter, hasLength(1));
    await db.close();
  });

  test('新装路径：UNIQUE(chapterUrl, paragraphIndex) 约束生效', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);

    await db.insert('paragraph_annotations', row());
    // 同章节同段落重复插入应触发 UNIQUE 约束
    expect(
      () => db.insert('paragraph_annotations', row()),
      throwsA(anything),
    );
    // 不同段落可插入
    await db.insert('paragraph_annotations', row(paragraphIndex: 1));

    final rows = await db.query('paragraph_annotations');
    expect(rows, hasLength(2));
    await db.close();
  });

  test('新装路径：章节级索引存在', () async {
    final db = await openAtVersion(DatabaseMigrations.currentVersion);

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND tbl_name = 'paragraph_annotations' AND name IS NOT NULL",
    );
    final names = indexes.map((r) => r['name'] as String).toSet();
    expect(names, contains('idx_paragraph_annotations_chapter'));
    await db.close();
  });
}

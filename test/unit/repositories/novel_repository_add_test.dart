/// NovelRepository.addToBookshelf 冲突语义测试
///
/// 2026-09 审查 P1:旧实现用 ConflictAlgorithm.replace,URL 已存在时
/// SQLite 删旧插新,lastReadChapter/lastReadTime/coverMediaId 全部静默清空;
/// 同名书(createNovel 用 url=title)会互相顶掉。
/// 新契约:冲突时刷新元数据、保留阅读进度,返回既有行 id。
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

  Future<({Database db, NovelRepository repo})> create() async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
      onCreate: (db, v) async {
        await DatabaseMigrations.createV1Tables(db);
        await DatabaseMigrations.upgrade(db, 1, v);
      },
    );
    return (
      db: db,
      repo: NovelRepository(dbConnection: DatabaseConnection.forTesting(db)),
    );
  }

  Novel novel(String url, {String? coverMediaId}) => Novel(
        title: '测试书',
        author: '作者',
        url: url,
        coverMediaId: coverMediaId,
      );

  test('新书正常插入,返回自增 id', () async {
    final (:db, :repo) = await create();
    final id = await repo.addToBookshelf(novel('https://x.com/book/1'));
    expect(id, greaterThan(0));
    await db.close();
  });

  test('重复添加同 URL:阅读进度与封面媒体保留,元数据刷新', () async {
    final (:db, :repo) = await create();
    final id1 = await repo.addToBookshelf(novel('https://x.com/book/1'));

    // 模拟已有阅读进度与生成过的封面媒体
    await db.update(
      'bookshelf',
      {'lastReadChapter': 42, 'lastReadTime': 1234567890, 'coverMediaId': 'media-old'},
      where: 'id = ?',
      whereArgs: [id1],
    );

    final id2 = await repo.addToBookshelf(Novel(
      title: '测试书(更新)',
      author: '新作者',
      url: 'https://x.com/book/1',
      description: '新简介',
    ));

    expect(id2, id1, reason: '冲突时应返回既有行 id');

    final novels = await repo.getNovels();
    expect(novels, hasLength(1));
    expect(novels.first.title, '测试书(更新)');
    expect(novels.first.author, '新作者');
    expect(novels.first.description, '新简介');
    expect(novels.first.lastReadChapterIndex, 42,
        reason: '阅读进度不得被清空');
    expect(novels.first.coverMediaId, 'media-old',
        reason: '旧封面媒体不得被清成 null');
    await db.close();
  });

  test('重复添加且新值带 coverMediaId 时才覆盖', () async {
    final (:db, :repo) = await create();
    final id = await repo.addToBookshelf(novel('https://x.com/book/2'));
    await db.update('bookshelf', {'coverMediaId': 'media-a'},
        where: 'id = ?', whereArgs: [id]);

    // 不带 coverMediaId 的重复添加 → 保留
    await repo.addToBookshelf(Novel(
        title: '测试书', author: '作者', url: 'https://x.com/book/2'));
    var row = (await repo.getNovels()).first;
    expect(row.coverMediaId, 'media-a');

    // 带新 coverMediaId 的重复添加 → 覆盖
    await repo.addToBookshelf(Novel(
        title: '测试书', author: '作者', url: 'https://x.com/book/2',
        coverMediaId: 'media-b'));
    row = (await repo.getNovels()).first;
    expect(row.coverMediaId, 'media-b');
    await db.close();
  });

  test('createNovel 同名书不再互相顶掉(阅读进度保留)', () async {
    final (:db, :repo) = await create();
    await repo.createNovel(title: '同名书', author: 'a');
    // createNovel 返回的 Novel 是本地构造不带 id,按 url 定位行
    final rows1 = await db.query('bookshelf',
        where: 'url = ?', whereArgs: ['同名书'], limit: 1);
    final id1 = rows1.first['id'] as int;
    await db.update(
      'bookshelf',
      {'lastReadChapter': 7},
      where: 'id = ?',
      whereArgs: [id1],
    );

    final n2 = await repo.createNovel(title: '同名书', author: 'b');
    expect(n2.url, '同名书', reason: 'createNovel 的 url=title 语义保持不变');

    final novels = await repo.getNovels();
    expect(novels, hasLength(1), reason: '同名书只占一行,不再删旧插新');
    expect(novels.first.author, 'b');
    expect(novels.first.lastReadChapterIndex, 7);
    await db.close();
  });
}

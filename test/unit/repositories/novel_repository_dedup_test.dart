/// NovelRepository 书架去重（归一化 URL）测试
///
/// 场景背景：手动添加存浏览器当前页 URL，书架同步存页面提取的 href，
/// 同一本书常见 URL 机械差异（协议/大小写/尾部斜杠/锚点/默认端口）。
/// 契约：
/// - isInBookshelf 变体命中 → true
/// - addToBookshelf 变体命中 → 不新增行，刷新既有行元数据，返回既有 id，
///   阅读进度字段不触碰
/// - findExistingBookshelfUrl 返回已存原始 URL（后续写键必须沿用）
/// - custom:// 原创标识不受归一化影响
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath, Sqflite;

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

  Novel novel(String url, {String? title}) => Novel(
        title: title ?? '测试书',
        author: '作者',
        url: url,
      );

  Future<int> rowCount(Database db) async {
    final result = await db.query('bookshelf', columns: ['COUNT(*) as c']);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  group('findExistingBookshelfUrl', () {
    test('URL 完全一致 → 返回原文', () async {
      final (:db, :repo) = await create();
      await repo.addToBookshelf(novel('https://a.com/book/1'));
      expect(
        await repo.findExistingBookshelfUrl('https://a.com/book/1'),
        'https://a.com/book/1',
      );
      await db.close();
    });

    test('机械变体（尾部斜杠/协议/大小写/锚点）→ 返回已存原文', () async {
      final (:db, :repo) = await create();
      await repo.addToBookshelf(novel('https://www.a.com/book/1'));

      expect(
        await repo.findExistingBookshelfUrl('http://www.a.com/book/1/'),
        'https://www.a.com/book/1',
      );
      expect(
        await repo.findExistingBookshelfUrl('https://WWW.A.com/book/1#top'),
        'https://www.a.com/book/1',
      );
      await db.close();
    });

    test('不同书 URL → null', () async {
      final (:db, :repo) = await create();
      await repo.addToBookshelf(novel('https://a.com/book/1'));
      expect(
        await repo.findExistingBookshelfUrl('https://a.com/book/2'),
        isNull,
      );
      await db.close();
    });
  });

  group('isInBookshelf 归一化兜底', () {
    test('变体 URL 命中 → true', () async {
      final (:db, :repo) = await create();
      await repo.addToBookshelf(novel('https://a.com/book/1'));
      expect(await repo.isInBookshelf('https://a.com/book/1/'), isTrue);
      expect(await repo.isInBookshelf('http://a.com/book/1'), isTrue);
      await db.close();
    });
  });

  group('addToBookshelf 变体去重', () {
    test('变体 URL 添加 → 不新增行，返回既有 id，进度保留，元数据刷新', () async {
      final (:db, :repo) = await create();
      final id1 = await repo.addToBookshelf(novel('https://a.com/book/1'));

      // 模拟已有阅读进度
      await db.update(
        'bookshelf',
        {'lastReadChapter': 42, 'lastReadTime': 1234567890},
        where: 'id = ?',
        whereArgs: [id1],
      );

      final id2 = await repo.addToBookshelf(
        novel('http://a.com/book/1/', title: '测试书(更新)'),
      );

      expect(id2, id1);
      expect(await rowCount(db), 1);

      final rows = await db.query(
        'bookshelf',
        where: 'id = ?',
        whereArgs: [id1],
      );
      expect(rows.single['title'], '测试书(更新)');
      // 阅读进度不触碰
      expect(rows.single['lastReadChapter'], 42);
      expect(rows.single['lastReadTime'], 1234567890);
      await db.close();
    });

    test('custom:// 原创标识不受归一化影响，不同 custom URL 各自成行', () async {
      final (:db, :repo) = await create();
      await repo.addToBookshelf(novel('custom://custom_novel_a'));
      await repo.addToBookshelf(novel('custom://custom_novel_b'));
      expect(await rowCount(db), 2);
      // 同一 custom URL 重复添加仍走既有行刷新
      final id = await repo.addToBookshelf(novel('custom://custom_novel_a'));
      expect(await rowCount(db), 2);
      expect(id, greaterThan(0));
      await db.close();
    });
  });

  group('addToBookshelf 封面保留语义', () {
    test('重复添加带封面 → coverUrl 更新', () async {
      final (:db, :repo) = await create();
      await repo.addToBookshelf(novel('https://a.com/book/1'));
      await repo.addToBookshelf(Novel(
        title: '测试书',
        author: '作者',
        url: 'https://a.com/book/1',
        coverUrl: 'https://a.com/img/new.jpg',
      ));

      final rows = await db.query('bookshelf');
      expect(rows.single['coverUrl'], 'https://a.com/img/new.jpg');
      await db.close();
    });

    test('重复添加无封面（旧脚本同步）→ 已有 coverUrl 保留不被抹掉', () async {
      final (:db, :repo) = await create();
      await repo.addToBookshelf(Novel(
        title: '测试书',
        author: '作者',
        url: 'https://a.com/book/1',
        coverUrl: 'https://a.com/img/old.jpg',
      ));

      // 无封面槽位的同步再来一次（coverUrl 为 null）
      await repo.addToBookshelf(novel('https://a.com/book/1'));
      final rows = await db.query('bookshelf');
      expect(rows.single['coverUrl'], 'https://a.com/img/old.jpg');

      // 空白串同样视为"无新值"
      await repo.addToBookshelf(Novel(
        title: '测试书',
        author: '作者',
        url: 'https://a.com/book/1',
        coverUrl: '   ',
      ));
      final rows2 = await db.query('bookshelf');
      expect(rows2.single['coverUrl'], 'https://a.com/img/old.jpg');
      await db.close();
    });
  });
}

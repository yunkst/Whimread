import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/models/bookshelf.dart';
import 'package:novel_app/repositories/bookshelf_repository.dart';
import 'package:novel_app/core/database/database_connection.dart';
import '../../helpers/test_database_setup.dart' as test_db;

/// 书架按"小说来源"派生的过滤逻辑测试。
///
/// 新设计：书架由小说 URL 派生——
/// - 全部：bookshelf 表全部行
/// - 原创：`custom://` 前缀
/// - 联网：非 `custom://` 前缀，**按 URL host 再拆分来源站点**
///
/// 旧"用户自定义书架"的关联表（novel_bookshelves）不再参与查询。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late BookshelfRepository repo;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    repo = BookshelfRepository(dbConnection: DatabaseConnection.forTesting(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedNovel({
    required String url,
    String title = '测试书',
    int? lastReadTime,
  }) async {
    await db.insert('bookshelf', {
      'url': url,
      'title': title,
      'author': '作者',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
      if (lastReadTime != null) 'lastReadTime': lastReadTime,
    });
  }

  group('getBookshelves', () {
    test('返回三档系统书架（全部/原创/联网），顺序固定', () async {
      final shelves = await repo.getBookshelves();
      expect(shelves.map((s) => s.kind).toList(), [
        BookshelfKind.all,
        BookshelfKind.original,
        BookshelfKind.online,
      ]);
    });
  });

  group('getNovelsByBookshelf', () {
    test('全部：返回所有小说（含原创与联网）', () async {
      await seedNovel(url: 'custom://custom_novel_1', title: '原创书');
      await seedNovel(url: 'https://example.com/n1', title: '联网书');

      final novels =
          await repo.getNovelsByBookshelf(BookshelfKind.all);
      expect(novels, hasLength(2));
      expect(novels.map((n) => n.title), containsAll(['原创书', '联网书']));
    });

    test('原创：仅 custom:// 前缀的小说', () async {
      await seedNovel(url: 'custom://custom_novel_1', title: '原创书');
      await seedNovel(url: 'https://example.com/n1', title: '联网书');

      final novels =
          await repo.getNovelsByBookshelf(BookshelfKind.original);
      expect(novels, hasLength(1));
      expect(novels.single.title, '原创书');
      expect(novels.single.url.startsWith('custom://'), isTrue);
    });

    test('联网（聚合）：仅非 custom:// 前缀的小说（含所有站点）', () async {
      await seedNovel(url: 'custom://custom_novel_1', title: '原创书');
      await seedNovel(url: 'https://example.com/n1', title: '联网书A');
      await seedNovel(url: 'http://other.com/n2', title: '联网书B');

      final novels =
          await repo.getNovelsByBookshelf(BookshelfKind.online);
      expect(novels, hasLength(2));
      expect(novels.map((n) => n.title), containsAll(['联网书A', '联网书B']));
    });

    test('空书架返回空列表', () async {
      for (final kind in BookshelfKind.values) {
        final novels = await repo.getNovelsByBookshelf(kind);
        expect(novels, isEmpty, reason: 'kind=$kind 应为空');
      }
    });
  });

  group('getNovelsBySourceDomain', () {
    test('按 URL host 过滤站点书架', () async {
      await seedNovel(url: 'custom://custom_novel_1', title: '原创书');
      await seedNovel(url: 'https://www.example.com/n1', title: 'A站书');
      await seedNovel(url: 'https://www.example.com/n2', title: 'A站书2');
      await seedNovel(url: 'https://other.com/n3', title: 'B站书');

      final novels =
          await repo.getNovelsBySourceDomain('www.example.com');
      expect(novels, hasLength(2));
      expect(novels.map((n) => n.title), containsAll(['A站书', 'A站书2']));
    });

    test('host 大小写归一化匹配', () async {
      await seedNovel(url: 'https://WWW.Example.COM/n1', title: '大写host书');

      final novels =
          await repo.getNovelsBySourceDomain('www.example.com');
      expect(novels, hasLength(1));
    });

    test('原创与无 host 的 URL 不落入站点书架', () async {
      await seedNovel(url: 'custom://custom_novel_1', title: '原创书');
      await seedNovel(url: 'https://www.example.com/n1', title: 'A站书');

      expect(await repo.getNovelsBySourceDomain('custom_novel_1'), isEmpty);
      expect(await repo.getNovelsBySourceDomain('不存在的站点'), isEmpty);
    });

    test('空书架返回空列表', () async {
      expect(await repo.getNovelsBySourceDomain('www.example.com'), isEmpty);
    });
  });

  group('getOnlineSourceDomains', () {
    test('返回有藏书的站点 host 去重列表', () async {
      await seedNovel(url: 'custom://custom_novel_1');
      await seedNovel(url: 'https://www.example.com/n1');
      await seedNovel(url: 'https://www.example.com/n2');
      await seedNovel(url: 'http://other.com/n3');

      final domains = await repo.getOnlineSourceDomains();
      expect(domains, containsAll(['www.example.com', 'other.com']));
      expect(domains, hasLength(2));
    });

    test('按最近活跃降序排列（最近阅读的站点在前）', () async {
      await seedNovel(
        url: 'https://old.com/n1',
        lastReadTime: 1000,
      );
      await seedNovel(
        url: 'https://recent.com/n2',
        lastReadTime: 2000,
      );

      final domains = await repo.getOnlineSourceDomains();
      expect(domains, ['recent.com', 'old.com']);
    });

    test('无法解析 host 的联网小说不产生站点', () async {
      await seedNovel(url: 'not-a-valid-url');
      await seedNovel(url: 'https://www.example.com/n1');

      final domains = await repo.getOnlineSourceDomains();
      expect(domains, ['www.example.com']);
    });

    test('空书架返回空列表', () async {
      expect(await repo.getOnlineSourceDomains(), isEmpty);
    });
  });

  group('getNovelCountByBookshelf', () {
    test('按来源派生计数', () async {
      await seedNovel(url: 'custom://custom_novel_1');
      await seedNovel(url: 'custom://custom_novel_2');
      await seedNovel(url: 'https://example.com/n1');

      expect(await repo.getNovelCountByBookshelf(BookshelfKind.all), 3);
      expect(
          await repo.getNovelCountByBookshelf(BookshelfKind.original), 2);
      expect(
          await repo.getNovelCountByBookshelf(BookshelfKind.online), 1);
    });

    test('空书架计数为 0', () async {
      expect(await repo.getNovelCountByBookshelf(BookshelfKind.all), 0);
    });
  });
}

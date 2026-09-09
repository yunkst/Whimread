import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/models/bookshelf.dart';
import 'package:novel_app/repositories/bookshelf_repository.dart';
import 'package:novel_app/core/database/database_connection.dart';
import '../../helpers/test_database_setup.dart' as test_db;

/// 书架按"小说来源"派生的过滤逻辑测试。
///
/// 新设计：三档系统书架（全部/原创/联网），由小说 URL 前缀派生——
/// - 全部：bookshelf 表全部行
/// - 原创：`custom://` 前缀
/// - 联网：非 `custom://` 前缀
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
  }) async {
    await db.insert('bookshelf', {
      'url': url,
      'title': title,
      'author': '作者',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
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

    test('联网：仅非 custom:// 前缀的小说', () async {
      await seedNovel(url: 'custom://custom_novel_1', title: '原创书');
      await seedNovel(url: 'https://example.com/n1', title: '联网书A');
      await seedNovel(url: 'http://example.com/n2', title: '联网书B');

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

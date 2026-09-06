import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/repositories/bookshelf_repository.dart';
import 'package:novel_app/core/database/database_connection.dart';
import '../../helpers/test_database_setup.dart' as test_db;

/// moveNovelToBookshelf 放宽 from=1（"全部小说"虚拟书架）特例。
///
/// 背景：id=1 是虚拟书架，直接查 bookshelf 表，不写 novel_bookshelves 关联。
/// 旧实现 `from==1 || to==1` 一律抛 ArgumentError，导致从"全部小说"移出失败。
/// 新实现：to=1 仍抛（防御性），from=1 降级为 add-only（不调 removeNovelFromBookshelf）。
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

  /// 插入一条小说到 bookshelf 表（不写 novel_bookshelves 关联，模拟"只在全部小说"状态）。
  Future<void> seedNovel(String url) async {
    await db.insert('bookshelf', {
      'url': url,
      'title': '测试书',
      'author': '作者',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  test('move from 全部小说(1) to 我的收藏(2) 不抛错且关联表加一行', () async {
    const url = 'https://example.com/novel/1';
    await seedNovel(url);

    // 初始：novel_bookshelves 应为空（id=1 是虚拟书架，不写关联）
    final before = await db.query('novel_bookshelves');
    expect(before, isEmpty);

    // from=1 不再抛错
    await repo.moveNovelToBookshelf(url, 1, 2);

    // 关联表应有一行 (novel_url, 2)
    final after = await db.query('novel_bookshelves');
    expect(after, hasLength(1));
    expect(after.first['novel_url'], url);
    expect(after.first['bookshelf_id'], 2);

    // bookshelf 表小说行不动
    final novel = await db.query('bookshelf', where: 'url = ?', whereArgs: [url]);
    expect(novel, hasLength(1));
  });

  test('move to 全部小说(1) 仍抛 ArgumentError（防御性断言）', () async {
    const url = 'https://example.com/novel/2';
    await seedNovel(url);
    await repo.addNovelToBookshelf(url, 2);

    expect(
      () => repo.moveNovelToBookshelf(url, 2, 1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('move from 我的收藏(2) to 都市(3) 回归正常 add+remove', () async {
    const url = 'https://example.com/novel/3';
    // 新建一个非系统书架 id=3
    await db.insert('bookshelves', {
      'id': 3,
      'name': '都市',
      'is_system': 0,
      'sort_order': 2,
    });
    await seedNovel(url);
    await repo.addNovelToBookshelf(url, 2);

    await repo.moveNovelToBookshelf(url, 2, 3);

    final rows = await db.query('novel_bookshelves',
        where: 'novel_url = ?', whereArgs: [url]);
    expect(rows, hasLength(1));
    expect(rows.first['bookshelf_id'], 3);
  });

  test('move from == to 早 return 无副作用', () async {
    const url = 'https://example.com/novel/4';
    await seedNovel(url);
    await repo.addNovelToBookshelf(url, 2);

    await repo.moveNovelToBookshelf(url, 2, 2);

    final rows = await db.query('novel_bookshelves',
        where: 'novel_url = ?', whereArgs: [url]);
    expect(rows, hasLength(1));
    expect(rows.first['bookshelf_id'], 2);
  });
}

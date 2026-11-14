/// SideStoryRepository 测试：番外行的创建/查询/计数/级联删除
///
/// 覆盖：
/// - 创建番外：isSideStory=1 落库、URL 前缀约定、作者继承宿主
/// - 查询：章级过滤、聚合信息（章数/已读/字数）、锚点章标题、孤儿锚点
/// - 徽标计数：getSideStoryCountsByChapter
/// - 级联删除：单棵番外树（含番外套番外）、宿主小说级联（保宿主行）
/// - 书架过滤：番外行不出现在 BookshelfRepository / NovelRepository 的查询结果
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/bookshelf.dart';
import 'package:novel_app/repositories/bookshelf_repository.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/repositories/side_story_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database_setup.dart' as test_db;

/// 测试夹具常量（文件级：夹具函数与 main 共用）
const mainUrl = 'https://example.com/main';
const ch11Url = '$mainUrl#ch11';
const ch12Url = '$mainUrl#ch12';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SideStoryRepository repo;
  late NovelRepository novelRepo;
  late BookshelfRepository bookshelfRepo;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    repo = SideStoryRepository(dbConnection: DatabaseConnection.forTesting(db));
    novelRepo =
        NovelRepository(dbConnection: DatabaseConnection.forTesting(db));
    bookshelfRepo = BookshelfRepository(
        dbConnection: DatabaseConnection.forTesting(db));
    await _seedMainNovel(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('createSideStory：isSideStory=1 落库、URL 前缀正确、作者继承宿主', () async {
    final novel = await repo.createSideStory(
      title: '闺蜜往事',
      anchorNovelUrl: mainUrl,
      anchorChapterUrl: ch12Url,
      description: '女主和闺蜜的过往',
    );

    expect(novel.id, isNotNull);
    expect(novel.isSideStory, isTrue);
    expect(novel.url, startsWith(kSideStoryUrlPrefix));
    expect(novel.anchorNovelUrl, mainUrl);
    expect(novel.anchorChapterUrl, ch12Url);
    expect(novel.author, '测试作者', reason: '作者应继承宿主小说');

    final row =
        await db.query('bookshelf', where: 'id = ?', whereArgs: [novel.id]);
    expect(row.single['isSideStory'], 1);
    expect(row.single['description'], '女主和闺蜜的过往');
  });

  test('getSideStories：返回聚合信息（章数/已读/字数/锚点章标题）', () async {
    final ss = await repo.createSideStory(
      title: '闺蜜往事',
      anchorNovelUrl: mainUrl,
      anchorChapterUrl: ch12Url,
    );
    final ssUrl = ss.url;
    await _seedSideStoryChapters(db, ssUrl, chapterCount: 3, readCount: 1);

    final summaries = await repo.getSideStories(anchorNovelUrl: mainUrl);
    expect(summaries, hasLength(1));
    final s = summaries.single;
    expect(s.novel.title, '闺蜜往事');
    expect(s.chapterCount, 3);
    expect(s.readCount, 1);
    expect(s.totalChars, greaterThan(0));
    expect(s.anchorChapterTitle, '第12章 女主与闺蜜登场');
    expect(s.anchorChapterIndex, 11);
    expect(s.progress, closeTo(1 / 3, 0.01));
    expect(ssUrl, isNotNull);
  });

  test('getSideStories 章级过滤：只返回挂载在指定章的番外', () async {
    await repo.createSideStory(
      title: '挂在12章',
      anchorNovelUrl: mainUrl,
      anchorChapterUrl: ch12Url,
    );
    await repo.createSideStory(
      title: '挂在11章',
      anchorNovelUrl: mainUrl,
      anchorChapterUrl: ch11Url,
    );

    final ch12List =
        await repo.getSideStories(anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);
    expect(ch12List, hasLength(1));
    expect(ch12List.single.novel.title, '挂在12章');
  });

  test('getSideStoryCountsByChapter：徽标计数按锚点章分组', () async {
    await repo.createSideStory(
        title: 'A', anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);
    await repo.createSideStory(
        title: 'B', anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);
    await repo.createSideStory(
        title: 'C', anchorNovelUrl: mainUrl, anchorChapterUrl: ch11Url);

    final counts = await repo.getSideStoryCountsByChapter(mainUrl);
    expect(counts[ch12Url], 2);
    expect(counts[ch11Url], 1);
    expect(counts.length, 2);
  });

  test('锚点章被删除后：番外保留，anchorChapterTitle 为 null（孤儿容忍）', () async {
    await repo.createSideStory(
        title: '孤儿番外', anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);
    // 模拟主线章被删除
    await db.delete('novel_chapters', where: 'chapterUrl = ?', whereArgs: [ch12Url]);

    final summaries = await repo.getSideStories(anchorNovelUrl: mainUrl);
    expect(summaries, hasLength(1));
    expect(summaries.single.anchorChapterTitle, isNull);
    expect(summaries.single.novel.title, '孤儿番外');
  });

  test('deleteSideStoryTree：删除番外行+章节+缓存，主线不受影响', () async {
    final ss = await repo.createSideStory(
        title: '闺蜜往事', anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);
    await _seedSideStoryChapters(db, ss.url, chapterCount: 2, readCount: 0);

    final deleted = await repo.deleteSideStoryTree(ss.url);
    expect(deleted, 1);

    // 番外行已删
    final rows = await db.query('bookshelf',
        where: 'url = ?', whereArgs: [ss.url]);
    expect(rows, isEmpty);
    // 番外章节/缓存已删
    expect(
        await db.query('novel_chapters', where: 'novelUrl = ?', whereArgs: [ss.url]),
        isEmpty);
    expect(
        await db.query('chapter_cache', where: 'novelUrl = ?', whereArgs: [ss.url]),
        isEmpty);
    // 主线小说与主线章节完好
    expect(
        await db.query('bookshelf', where: 'url = ?', whereArgs: [mainUrl]),
        hasLength(1));
    expect(
        await db.query('novel_chapters', where: 'novelUrl = ?', whereArgs: [mainUrl]),
        hasLength(2));
  });

  test('番外套番外：deleteSideStoryTree 级联删除子番外整棵树', () async {
    final parent =
        await repo.createSideStory(title: '闺蜜往事', anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);
    await _seedSideStoryChapters(db, parent.url, chapterCount: 2, readCount: 0);
    final child = await repo.createSideStory(
        title: '苏晴的日记',
        anchorNovelUrl: parent.url,
        anchorChapterUrl: '${parent.url}#ch2');
    await _seedSideStoryChapters(db, child.url, chapterCount: 1, readCount: 0);

    // collectSideStoryTree 含根与子
    final tree = await repo.collectSideStoryTree(parent.url);
    expect(tree, containsAll([parent.url, child.url]));

    final deleted = await repo.deleteSideStoryTree(parent.url);
    expect(deleted, 2, reason: '父番外 + 子番外');
    expect(
        await db.query('bookshelf', where: 'url = ?', whereArgs: [child.url]),
        isEmpty,
        reason: '子番外行随父级联删除');
    // 主线仍完好
    expect(
        await db.query('bookshelf', where: 'url = ?', whereArgs: [mainUrl]),
        hasLength(1));
  });

  test('deleteSideStoriesOfNovel：清宿主全部番外，保宿主行与主线章节', () async {
    final ss1 = await repo.createSideStory(
        title: '番外一', anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);
    final ss2 = await repo.createSideStory(
        title: '番外二', anchorNovelUrl: mainUrl, anchorChapterUrl: ch11Url);
    await repo.createSideStory(
        title: '孙番外',
        anchorNovelUrl: ss1.url,
        anchorChapterUrl: '${ss1.url}#ch1');

    final deleted = await repo.deleteSideStoriesOfNovel(mainUrl);
    expect(deleted, 3, reason: '两部直接子番外 + 一部孙番外');

    final sideRows = await db.query(
      'bookshelf',
      where: 'isSideStory = 1',
    );
    expect(sideRows, isEmpty);
    // 主线行仍在
    final mainRow = await db.query('bookshelf', where: 'url = ?', whereArgs: [mainUrl]);
    expect(mainRow, hasLength(1));
    // 主线章节未被误删
    expect(
        await db.query('novel_chapters', where: 'novelUrl = ?', whereArgs: [mainUrl]),
        hasLength(2));
    expect(ss1.url, isNotNull);
    expect(ss2.url, isNotNull);
  });

  test('书架过滤：番外行不出现在书架三个分类与 getNovels 结果中', () async {
    await repo.createSideStory(
        title: '不入书架的番外', anchorNovelUrl: mainUrl, anchorChapterUrl: ch12Url);

    // 番外 URL 是 custom:// 前缀，若无过滤会混进「原创」书架
    final all = await bookshelfRepo.getNovelsByBookshelf(BookshelfKind.all);
    expect(all.map((n) => n.title), isNot(contains('不入书架的番外')));
    expect(all.map((n) => n.title), contains('主线小说'));

    final original =
        await bookshelfRepo.getNovelsByBookshelf(BookshelfKind.original);
    expect(original, isEmpty, reason: '主线是联网书；番外即使 custom:// 也不应进原创分类');

    final online = await bookshelfRepo.getNovelsByBookshelf(BookshelfKind.online);
    expect(online.map((n) => n.title), ['主线小说']);

    final novels = await novelRepo.getNovels();
    expect(novels.map((n) => n.title), ['主线小说'],
        reason: 'NovelRepository.getNovels（agent list_novels 数据源）也必须排除番外');

    final domains = await bookshelfRepo.getOnlineSourceDomains();
    expect(domains, ['example.com']);
  });
}

// ============================== 测试夹具 ==============================

Future<void> _seedMainNovel(Database db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('bookshelf', {
    'title': '主线小说',
    'author': '测试作者',
    'url': mainUrl,
    'addedAt': now,
  });
  // 两章主线（chapterIndex 0-based；第12章 = index 11）
  await db.insert('novel_chapters', {
    'novelUrl': mainUrl,
    'chapterUrl': ch11Url,
    'title': '第11章 山雨欲来',
    'chapterIndex': 10,
    'isUserInserted': 0,
  });
  await db.insert('novel_chapters', {
    'novelUrl': mainUrl,
    'chapterUrl': ch12Url,
    'title': '第12章 女主与闺蜜登场',
    'chapterIndex': 11,
    'isUserInserted': 0,
  });
}

/// 为番外种子 N 章（前 [readCount] 章标记已读），每章缓存 1000 字正文
Future<void> _seedSideStoryChapters(
  Database db,
  String sideStoryUrl, {
  required int chapterCount,
  required int readCount,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < chapterCount; i++) {
    final chapterUrl = '$sideStoryUrl#ch${i + 1}';
    await db.insert('novel_chapters', {
      'novelUrl': sideStoryUrl,
      'chapterUrl': chapterUrl,
      'title': '第${i + 1}章',
      'chapterIndex': i,
      'isUserInserted': 1,
      if (i < readCount) 'readAt': now,
    });
    await db.insert('chapter_cache', {
      'novelUrl': sideStoryUrl,
      'chapterUrl': chapterUrl,
      'title': '第${i + 1}章',
      'content': '正文' * 500, // 1000 字
      'chapterIndex': i,
      'cachedAt': now,
    });
  }
}

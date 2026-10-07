import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/core/interfaces/i_database_connection.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/repositories/chapter_version_repository.dart';
import '../../helpers/test_database_setup.dart';

/// ChapterRepository.searchInCachedContent 测试
///
/// 覆盖修复点：
/// 1. 标题与正文任一命中即返回（此前只搜正文，标题搜不到）
/// 2. 仅标题命中的章 titleMatched=true、无正文匹配位置
/// 3. 片段窗口重基坐标 + contentOffsetBase 可还原整章绝对偏移
/// 4. 命中行数超上限时 truncated=true
/// 5. novelUrl 范围过滤、大小写不敏感

void main() {
  TestDatabaseSetup.init();

  late Database db;
  late ChapterRepository repository;

  const testNovelUrl = 'https://example.com/novel/test-novel';

  Chapter makeChapter(
    String url, {
    int index = 0,
    String? title,
  }) {
    return Chapter(
      title: title ?? '第${index + 1}章',
      url: url,
      content: null,
      isCached: false,
      chapterIndex: index,
    );
  }

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    repository = ChapterRepository(
      dbConnection: _TestDbConnection(db),
      versionRepo: ChapterVersionRepository(dbConnection: _TestDbConnection(db)),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('正文命中', () {
    test('标题不含关键词时 titleMatched=false 且坐标可还原', () async {
      final content = '${'前' * 100}玄铁剑${'后' * 100}';
      await repository.cacheChapter(
        testNovelUrl,
        makeChapter('https://example.com/chapter/1', index: 0),
        content,
      );

      final page = await repository.searchInCachedContent('玄铁剑');
      final result = page.results.single;

      expect(result.titleMatched, isFalse);
      // 重基后的 start = 100 - (100 - 60) = 60
      expect(result.matchPositions.single.start, 60);
      expect(result.contentOffsetBase, 40);
      // 绝对偏移还原 = 窗口基 + 窗口内相对偏移
      expect(result.firstMatchAbsoluteOffset, 100);
      expect(
        content.substring(
          result.firstMatchAbsoluteOffset!,
          result.firstMatchAbsoluteOffset! + 3,
        ),
        '玄铁剑',
      );
    });
  });

  group('标题命中（修复点：此前标题搜不到）', () {
    test('仅标题命中 → 返回该章，titleMatched=true、无正文匹配', () async {
      await repository.cacheChapter(
        testNovelUrl,
        makeChapter(
          'https://example.com/chapter/1',
          index: 0,
          title: '第1章 玄铁重剑',
        ),
        '正文内容里完全没有那个词',
      );

      final page = await repository.searchInCachedContent('玄铁');
      expect(page.results.length, 1);

      final result = page.results.single;
      expect(result.titleMatched, isTrue);
      expect(result.matchPositions, isEmpty);
      expect(result.matchCount, 0);
      expect(result.firstMatchAbsoluteOffset, isNull);
      expect(result.chapterTitle, '第1章 玄铁重剑');
    });

    test('标题与正文同时命中 → titleMatched=true 且有正文匹配位置', () async {
      await repository.cacheChapter(
        testNovelUrl,
        makeChapter(
          'https://example.com/chapter/1',
          index: 0,
          title: '第1章 玄铁重剑',
        ),
        '他拔出了玄铁剑',
      );

      final page = await repository.searchInCachedContent('玄铁');
      final result = page.results.single;
      expect(result.titleMatched, isTrue);
      expect(result.matchCount, 1);
      expect(result.matchPositions.single.matchedText, '玄铁');
    });

    test('标题命中大小写不敏感', () async {
      await repository.cacheChapter(
        testNovelUrl,
        makeChapter(
          'https://example.com/chapter/1',
          index: 0,
          title: 'Chapter One: The Sword',
        ),
        '正文无关键词',
      );

      final page = await repository.searchInCachedContent('sword');
      expect(page.results.length, 1);
      expect(page.results.single.titleMatched, isTrue);
    });
  });

  group('范围与未命中', () {
    test('novelUrl 过滤只返回指定小说', () async {
      await repository.cacheChapter(
        testNovelUrl,
        makeChapter('https://example.com/chapter/1', index: 0),
        '含有关键词的内容',
      );
      await repository.cacheChapter(
        'https://example.com/novel/other',
        makeChapter('https://example.com/chapter/x', index: 0),
        '含有关键词的内容',
      );

      final page = await repository.searchInCachedContent(
        '关键词',
        novelUrl: testNovelUrl,
      );
      expect(page.results.length, 1);
      expect(page.results.single.novelUrl, testNovelUrl);
    });

    test('无命中返回空列表且不截断', () async {
      await repository.cacheChapter(
        testNovelUrl,
        makeChapter('https://example.com/chapter/1', index: 0),
        '普通内容',
      );

      final page = await repository.searchInCachedContent('不存在的词');
      expect(page.results, isEmpty);
      expect(page.truncated, isFalse);
    });
  });

  group('截断护栏', () {
    test('命中行数达到上限 → truncated=true', () async {
      for (var i = 0; i < 205; i++) {
        await repository.cacheChapter(
          testNovelUrl,
          makeChapter('https://example.com/chapter/$i', index: i),
          '命中词 $i',
        );
      }

      final page = await repository.searchInCachedContent('命中词');
      expect(page.truncated, isTrue, reason: '205 章命中超过 200 行上限');
      expect(page.results.length, 200);
    });

    test('命中行数未达上限 → truncated=false', () async {
      for (var i = 0; i < 5; i++) {
        await repository.cacheChapter(
          testNovelUrl,
          makeChapter('https://example.com/chapter/$i', index: i),
          '命中词 $i',
        );
      }

      final page = await repository.searchInCachedContent('命中词');
      expect(page.truncated, isFalse);
      expect(page.results.length, 5);
    });
  });
}

// ============================================================
// 内联数据库连接适配器
// ============================================================

/// IDatabaseConnection 的测试实现
class _TestDbConnection implements IDatabaseConnection {
  final Database _db;

  _TestDbConnection(this._db);

  @override
  Future<Database> get database async => _db;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  bool get isInitialized => true;
}

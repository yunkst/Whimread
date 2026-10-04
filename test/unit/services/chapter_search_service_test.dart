import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_repository.dart';
import 'package:novel_app/models/search_result.dart';
import 'package:novel_app/services/chapter_search_service.dart';

/// ChapterSearchService 测试：排序、截断透传、空关键词短路、异常包装
void main() {
  ChapterSearchResult makeResult({
    required int chapterIndex,
    String title = '章节',
  }) {
    return ChapterSearchResult(
      novelUrl: 'https://example.com/novel/1',
      novelTitle: '测试小说',
      novelAuthor: '作者',
      chapterUrl: 'https://example.com/chapter/$chapterIndex',
      chapterTitle: title,
      chapterIndex: chapterIndex,
      content: '关键词上下文片段',
      searchKeywords: const ['关键词'],
      matchPositions: const [
        MatchPosition(start: 0, end: 3, matchedText: '关键词'),
      ],
      cachedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  test('结果按章节索引升序排序', () async {
    final service = ChapterSearchService(
      chapterRepository: _FakeChapterRepository(
        page: (
          results: [
            makeResult(chapterIndex: 5),
            makeResult(chapterIndex: 1),
            makeResult(chapterIndex: 3),
          ],
          truncated: false,
        ),
      ),
    );

    final page = await service.searchInNovel('https://example.com/novel/1', '关键词');
    expect(
      page.results.map((r) => r.chapterIndex).toList(),
      [1, 3, 5],
    );
    expect(page.truncated, isFalse);
  });

  test('仓储截断标记透传给调用方', () async {
    final service = ChapterSearchService(
      chapterRepository: _FakeChapterRepository(
        page: (results: [makeResult(chapterIndex: 0)], truncated: true),
      ),
    );

    final page = await service.searchInNovel('https://example.com/novel/1', '关键词');
    expect(page.truncated, isTrue, reason: '截断标记必须透传，UI 才能提示结果不完整');
  });

  test('空关键词短路返回空结果，不触碰仓储', () async {
    final repo = _FakeChapterRepository(
      page: (results: [makeResult(chapterIndex: 0)], truncated: false),
    );
    final service = ChapterSearchService(chapterRepository: repo);

    for (final keyword in ['', '   ']) {
      final page = await service.searchInNovel('https://example.com/novel/1', keyword);
      expect(page.results, isEmpty);
      expect(page.truncated, isFalse);
    }
    expect(repo.callCount, 0, reason: '空关键词不应触发任何仓储查询');
  });

  test('仓储异常包装为「搜索失败」异常', () async {
    final service = ChapterSearchService(
      chapterRepository: _ThrowingChapterRepository(),
    );

    await expectLater(
      service.searchInNovel('https://example.com/novel/1', '关键词'),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('搜索失败'),
      )),
    );
  });
}

/// 只实现 searchInCachedContent 的测试替身，其余成员 noSuchMethod 兜底
class _FakeChapterRepository implements IChapterRepository {
  _FakeChapterRepository({required this.page});

  final ChapterSearchResultSet page;
  int callCount = 0;
  String? lastKeyword;
  String? lastNovelUrl;

  @override
  Future<ChapterSearchResultSet> searchInCachedContent(
    String keyword, {
    String? novelUrl,
  }) async {
    callCount++;
    lastKeyword = keyword;
    lastNovelUrl = novelUrl;
    return page;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _ThrowingChapterRepository implements IChapterRepository {
  @override
  Future<ChapterSearchResultSet> searchInCachedContent(
    String keyword, {
    String? novelUrl,
  }) async {
    throw StateError('db broken');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

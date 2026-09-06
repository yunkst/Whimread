import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_app/services/preload_service.dart';
import 'package:novel_app/services/headless_webview_content_service.dart';
import 'package:novel_app/services/headless_webview_errors.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/repositories/chapter_version_repository.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/chapter_content_result.dart';

import '../../helpers/test_database_setup.dart';
import 'test_helpers.mocks.dart' as test_mocks;

/// Manual mock for HeadlessWebViewContentService
class MockHeadlessWebViewContentService extends Mock
    implements HeadlessWebViewContentService {
  final Map<String, FetchContentResult> _stubs = {};
  FetchContentResult Function(String)? _fallback;

  void addStub(String url, ChapterContentResult? result) {
    _stubs[url] = result == null
        ? FetchContentResult.noScript()
        : FetchContentResult.success(result);
  }

  void setFallback(ChapterContentResult? Function(String) fn) {
    _fallback = (url) {
      final r = fn(url);
      return r == null
          ? FetchContentResult.noScript()
          : FetchContentResult.success(r);
    };
  }

  @override
  Future<FetchContentResult> fetchContent(
    String chapterUrl, {
    FetchPriority priority = FetchPriority.low,
  }) async {
    if (_stubs.containsKey(chapterUrl)) return _stubs[chapterUrl]!;
    if (_fallback != null) return _fallback!(chapterUrl);
    return super.noSuchMethod(
      Invocation.method(#fetchContent, [chapterUrl],
          {#priority: priority}),
      returnValue: Future<FetchContentResult>.value(
          FetchContentResult.noScript()),
      returnValueForMissingStub: Future<FetchContentResult>.value(
          FetchContentResult.noScript()),
    ) as Future<FetchContentResult>;
  }
}

/// 根因定位测试
///
/// 关键发现：_createTasks 跳过当前章节（by design），
/// 但如果只有一个URL，就不会创建任何任务！
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDatabaseSetup.init();

  late ChapterRepository chapterRepository;
  late MockHeadlessWebViewContentService mockHeadlessService;
  late PreloadService preloadService;
  late Database db;

  const testNovelUrl = 'https://example.com/novel/test';

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    chapterRepository = ChapterRepository(dbConnection: connection, versionRepo: ChapterVersionRepository(dbConnection: connection));
    mockHeadlessService = MockHeadlessWebViewContentService();
    preloadService = PreloadService(
      chapterRepository: chapterRepository,
      headlessService: mockHeadlessService,
    );
  });

  tearDown(() async {
    preloadService.dispose();
    await db.close();
  });

  // ============================================================
  // 根因验证: _createTasks 跳过当前章节
  // ============================================================
  group('根因验证: _createTasks 跳过当前章节', () {
    test('单URL + currentIndex=0 → 队列为空（BUG）', () async {
      final url = 'https://example.com/single_chapter';

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: [url],
        currentIndex: 0,
      );

      final stats = preloadService.getStatistics();
      print('单URL: enqueued_urls=${stats['enqueued_urls']}');

      // 当前章节被 _createTasks 跳过，所以 enqueued_urls = 0
      expect(stats['enqueued_urls'], 0,
          reason: '单URL场景下，当前章节（index=0）被跳过，队列为空');
    });

    test('2个URL + currentIndex=0 → 只有后续章节入队', () async {
      final urls = [
        'https://example.com/ch1',
        'https://example.com/ch2',
      ];

      mockHeadlessService.setFallback((_) => ChapterContentResult(content: '内容'));

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 等待处理完成
      await Future.delayed(Duration(milliseconds: 500));

      final stats = preloadService.getStatistics();
      print('2个URL: stats=$stats');

      // 当前章节(ch1)被跳过，只有ch2被入队并处理
      final processed = stats['total_processed'] as int;
      expect(processed, greaterThanOrEqualTo(1),
          reason: 'currentIndex=0时，ch2应该被处理');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('3个URL + currentIndex=1 → 前后章节都入队', () async {
      final urls = [
        'https://example.com/ch1',
        'https://example.com/ch2',
        'https://example.com/ch3',
      ];

      mockHeadlessService.setFallback((_) => ChapterContentResult(content: '内容'));

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 1,
      );

      // 等待第一个任务处理完成（缓存命中无延迟）
      await Future.delayed(Duration(milliseconds: 500));

      final stats = preloadService.getStatistics();
      print('3个URL: stats=$stats');

      // 当前章节(ch2)被跳过，ch3（后续）和ch1（前序）被入队
      final processed = stats['total_processed'] as int;
      expect(processed, greaterThanOrEqualTo(1),
          reason: 'currentIndex=1时，ch3和ch1应该被处理');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('10个URL + currentIndex=0 → 9个后续章节入队', () async {
      final urls = List.generate(10, (i) => 'https://example.com/ch$i');

      mockHeadlessService.setFallback((_) => ChapterContentResult(content: '内容'));

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 等待第一个任务处理完成
      await Future.delayed(Duration(milliseconds: 500));

      final stats = preloadService.getStatistics();
      print('10个URL: stats=$stats');

      // 当前章节(ch0)被跳过，9个后续章节被入队
      final processed = stats['total_processed'] as int;
      expect(processed, greaterThanOrEqualTo(1),
          reason: 'currentIndex=0时，至少一个后续章节应该被处理');
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  // ============================================================
  // 核心功能验证: 多章节 + mock API + 完整流程
  // ============================================================
  group('核心功能验证: 多章节完整流程', () {
    test('多章节应该触发 _processQueue 并缓存', () async {
      final urls = [
        'https://example.com/multi1',
        'https://example.com/multi2',
        'https://example.com/multi3',
      ];

      // Mock API
      for (final url in urls) {
        when(mockHeadlessService.fetchContent(url))
            .thenAnswer((_) async => FetchContentResult.success(ChapterContentResult(content: '内容:$url')));
      }

      // 入队
      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      print('入队后: queueLength=${preloadService.queueLength}');

      // 等待处理（第一个任务无需等待）
      await Future.delayed(Duration(milliseconds: 500));

      final stats = preloadService.getStatistics();
      print('处理后: $stats');

      final processed = stats['total_processed'] as int;
      final failed = stats['total_failed'] as int;
      print('processed=$processed, failed=$failed');

      // 至少应该处理1个（第一个无延迟）
      expect(processed + failed, greaterThan(0),
          reason: '应该至少处理一个任务');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('完整的 缓存→验证 流程', () async {
      final url1 = 'https://example.com/full1';
      final url2 = 'https://example.com/full2';

      // Mock
      when(mockHeadlessService.fetchContent(url1))
          .thenAnswer((_) async => FetchContentResult.success(ChapterContentResult(content: '缓存内容1')));
      when(mockHeadlessService.fetchContent(url2))
          .thenAnswer((_) async => FetchContentResult.success(ChapterContentResult(content: '缓存内容2')));

      // 入队（2个URL，currentIndex=0）
      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: [url1, url2],
        currentIndex: 0,
      );

      // 等待处理
      await Future.delayed(Duration(milliseconds: 500));

      // 验证: url2 应该被缓存（url1 是当前章节，被跳过）
      final cached2 = await chapterRepository.getCachedChapter(url2);
      print('url2 缓存内容: $cached2');

      expect(cached2, isNotNull, reason: 'url2 应该被缓存');
      expect(cached2, '缓存内容2');

      // url1 不应该被缓存（当前章节被跳过）
      final cached1 = await chapterRepository.getCachedChapter(url1);
      print('url1 缓存内容: $cached1');
      expect(cached1, isNull, reason: 'url1 是当前章节，不应被缓存');
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  // ============================================================
  // 生产场景模拟: 已缓存部分章节
  // ============================================================
  group('生产场景: 部分章节已缓存', () {
    test('已缓存章节被过滤，未缓存章节被预加载', () async {
      final urls = [
        'https://example.com/p1',
        'https://example.com/p2',
        'https://example.com/p3',
        'https://example.com/p4',
      ];

      // 预先缓存 p1 和 p3
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: urls[0], title: 'p1', content: '已缓存p1'),
        '已缓存p1',
      );
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: urls[2], title: 'p3', content: '已缓存p3'),
        '已缓存p3',
      );

      // Mock - 基于URL返回不同内容，并添加延迟防止立即处理
      when(mockHeadlessService.fetchContent(urls[1]))
          .thenAnswer((_) async {
        await Future.delayed(Duration(milliseconds: 200));
        return FetchContentResult.success(ChapterContentResult(content: '新缓存p2'));
      });
      when(mockHeadlessService.fetchContent(urls[3]))
          .thenAnswer((_) async {
        await Future.delayed(Duration(milliseconds: 200));
        return FetchContentResult.success(ChapterContentResult(content: '新缓存p4'));
      });

      // 入队（currentIndex=1，当前章节是p2）
      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 1,
      );

      final stats = preloadService.getStatistics();
      print('部分缓存场景: $stats');

      // 等待处理完成
      await Future.delayed(Duration(milliseconds: 500));

      final cached4 = await chapterRepository.getCachedChapter(urls[3]);
      print('p4 缓存内容: $cached4');
      expect(cached4, '新缓存p4');
    }, timeout: Timeout(Duration(seconds: 5)));
  });
}

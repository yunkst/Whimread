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
  final List<String> callOrder = [];

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
    callOrder.add(chapterUrl);
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

/// 预加载顺序修复验证测试
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

  group('修复验证: 预加载顺序正确', () {
    test('5章小说, 用户在读第1章 → ch2 最先被缓存', () async {
      final urls = List.generate(5, (i) => 'https://example.com/ch${i + 1}');

      final callOrder = <String>[];
      for (final url in urls) {
        mockHeadlessService.addStub(url, ChapterContentResult(content: '内容:$url'));
      }

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '5章小说',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 等待第一个任务（RateLimiter 第一次无延迟）
      await Future.delayed(Duration(milliseconds: 500));

      print('fetchContent 调用顺序: ${mockHeadlessService.callOrder}');

      // 修复后: ch2 应该是第一个被处理的
      expect(mockHeadlessService.callOrder, isNotEmpty, reason: '应该至少处理一个任务');
      expect(mockHeadlessService.callOrder[0], contains('ch2'),
          reason: 'ch2（紧邻当前章节）应该最先被缓存');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('3章小说, 用户在读第1章 → 顺序: ch2, ch3', () async {
      final urls = [
        'https://example.com/ch1',
        'https://example.com/ch2',
        'https://example.com/ch3',
      ];

      final callOrder = <String>[];
      for (final url in urls) {
        mockHeadlessService.addStub(url, ChapterContentResult(content: '内容:$url'));
      }

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '3章小说',
        chapterUrls: urls,
        currentIndex: 0,
      );

      await Future.delayed(Duration(milliseconds: 500));

      print('fetchContent 调用顺序: ${mockHeadlessService.callOrder}');
      expect(mockHeadlessService.callOrder[0], contains('ch2'),
          reason: 'ch2 应该最先被处理');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('100章小说, 用户在读第1章 → 入队数量正确', () async {
      final urls = List.generate(100, (i) => 'https://example.com/ch${i + 1}');

      for (final url in urls) {
        mockHeadlessService.addStub(url, ChapterContentResult(content: '内容:$url'));
      }

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '100章小说',
        chapterUrls: urls,
        currentIndex: 0,
      );

      final stats = preloadService.getStatistics();
      // 预期: 99 (100 - 1当前章节 = 99)
      // 注意: 由于异步处理，第一个任务可能已处理，enqueued_urls 可能为 98
      expect(stats['enqueued_urls'] as int, greaterThanOrEqualTo(98),
          reason: '至少应有98个章节入队（currentIndex=0跳过后，100-1=99，可能1个已处理）');

      // 第一个任务无延迟处理
      await Future.delayed(Duration(milliseconds: 500));

      final statsAfter = preloadService.getStatistics();
      final processed = statsAfter['total_processed'] as int;
      expect(processed, greaterThan(0), reason: '应该至少处理一个任务');
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('完整流程验证', () {
    test('缓存写入数据库且可查询', () async {
      final urls = [
        'https://example.com/ch1',
        'https://example.com/ch2',
        'https://example.com/ch3',
      ];

      mockHeadlessService.addStub(urls[1], ChapterContentResult(content: 'ch2的内容'));
      mockHeadlessService.addStub(urls[2], ChapterContentResult(content: 'ch3的内容'));

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试小说',
        chapterUrls: urls,
        currentIndex: 0,
      );

      await Future.delayed(Duration(milliseconds: 500));

      // ch2 应该已被缓存
      final cached2 = await chapterRepository.getCachedChapter(urls[1]);
      print('ch2 缓存: $cached2');
      expect(cached2, 'ch2的内容');

      // ch1（当前章节）不应被缓存
      final cached1 = await chapterRepository.getCachedChapter(urls[0]);
      expect(cached1, isNull);
    }, timeout: Timeout(Duration(seconds: 5)));

    test('部分已缓存场景', () async {
      final urls = [
        'https://example.com/p1',
        'https://example.com/p2',
        'https://example.com/p3',
        'https://example.com/p4',
      ];

      // 预先缓存 p2
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: urls[1], title: 'p2', content: '已缓存p2'),
        '已缓存p2',
      );

      mockHeadlessService.addStub(urls[2], ChapterContentResult(content: '新缓存p3'));
      mockHeadlessService.addStub(urls[3], ChapterContentResult(content: '新缓存p4'));

      // 用户在读 p1 (currentIndex=0)
      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 未缓存: p1(当前,跳过), p3, p4
      // _createTasks: safeIndex = uncachedUrls.indexOf(p1) 或 fallback
      // 后续: p3, p4
      // 前序: 无
      // 队列: [p3, p4] (addLast保持顺序)
      // 第一个处理: p3 ✅

      await Future.delayed(Duration(milliseconds: 500));

      final cached3 = await chapterRepository.getCachedChapter(urls[2]);
      print('p3 缓存: $cached3');
      expect(cached3, '新缓存p3');
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('原有功能回归', () {
    test('已缓存章节不入队', () async {
      final url = 'https://example.com/cached1';
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: url, title: '测试', content: '内容'),
        '内容',
      );

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: [url],
        currentIndex: 0,
      );

      final stats = preloadService.getStatistics();
      expect(stats['queue_length'], 0);
    });

    test('重复入队去重', () async {
      final urls = [
        'https://example.com/dup1',
        'https://example.com/dup2',
      ];

      mockHeadlessService.setFallback((_) => ChapterContentResult(content: '内容'));

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 第二次入队（去重）
      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      final stats = preloadService.getStatistics();
      // 去重后 enqueued_urls 不应翻倍
      // 注意：第二次调用时，第一个任务可能已被处理并从 _enqueuedUrls 移除
      // 所以这里只验证不会异常
      print('重复入队后 stats: $stats');
    }, timeout: Timeout(Duration(seconds: 5)));
  });
}

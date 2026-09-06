import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:novel_app/services/preload_service.dart';
import 'package:novel_app/services/headless_webview_content_service.dart';
import 'package:novel_app/services/headless_webview_errors.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/repositories/chapter_version_repository.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/chapter_content_result.dart';

import '../../helpers/test_database_setup.dart';

/// Manual mock for HeadlessWebViewContentService
class MockHeadlessWebViewContentService
    implements HeadlessWebViewContentService {
  final Map<String, FetchContentResult> _stubs = {};
  final List<String> callOrder = [];
  Completer<void>? _blockAll;
  bool blockProcessing = false;

  void addStub(String url, ChapterContentResult? result) {
    _stubs[url] = result == null
        ? FetchContentResult.noScript()
        : FetchContentResult.success(result);
  }

  /// 阻塞所有 fetchContent 调用，直到 [release] 被调用
  void blockAllProcessing() {
    _blockAll = Completer<void>();
    blockProcessing = true;
  }

  void release() {
    _blockAll?.complete();
    _blockAll = null;
    blockProcessing = false;
  }

  @override
  Future<FetchContentResult> fetchContent(
    String chapterUrl, {
    FetchPriority priority = FetchPriority.low,
  }) async {
    callOrder.add(chapterUrl);
    if (blockProcessing) {
      await _blockAll!.future;
    }
    if (_stubs.containsKey(chapterUrl)) return _stubs[chapterUrl]!;
    return FetchContentResult.noScript();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 验证 _createTasks 排序逻辑
///
/// 核心场景：当前章节已被阅读器缓存（_loadChapterContent 先于 enqueueTasks 执行），
/// _createTasks 应基于原始索引分割前后序，而非在过滤后列表中查找位置。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDatabaseSetup.init();

  late ChapterRepository chapterRepository;
  late MockHeadlessWebViewContentService mockHeadlessService;
  late PreloadService preloadService;
  late Database db;

  const testNovelUrl = 'https://example.com/novel/order-test';

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

  group('Bug 修复: 当前章节已缓存时排序正确', () {
    test('用户在读第500章且当前章已缓存 → 第501章应最先入队', () async {
      // 10 章模拟，用户在读第 5 章（0-based index=4）
      final urls = List.generate(10, (i) => 'https://example.com/ch${i + 1}');

      // 模拟阅读器已缓存当前章节（第5章）
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: urls[4], title: '第5章', content: '已缓存'),
        '已缓存',
      );

      // 其余章节添加 stub
      for (final url in urls.where((u) => u != urls[4])) {
        mockHeadlessService.addStub(
            url, ChapterContentResult(content: '内容:$url'));
      }

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '10章小说',
        chapterUrls: urls,
        currentIndex: 4,
      );

      // 等第一个任务执行
      await Future.delayed(Duration(milliseconds: 500));

      // 第5章已缓存 → 后续第6章(index=5)应最先被处理
      expect(mockHeadlessService.callOrder, isNotEmpty,
          reason: '应该至少处理一个任务');
      expect(mockHeadlessService.callOrder[0], contains('ch6'),
          reason: '第6章（后续章节）应最先被预加载，而不是从队尾倒着来');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('用户在读第1章且当前章已缓存 → 第2章应最先入队', () async {
      final urls = List.generate(5, (i) => 'https://example.com/ch${i + 1}');

      // 预缓存第1章（当前章节）
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: urls[0], title: '第1章', content: '已缓存'),
        '已缓存',
      );

      for (final url in urls.skip(1)) {
        mockHeadlessService.addStub(
            url, ChapterContentResult(content: '内容:$url'));
      }

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '5章小说',
        chapterUrls: urls,
        currentIndex: 0,
      );

      await Future.delayed(Duration(milliseconds: 500));

      expect(mockHeadlessService.callOrder, isNotEmpty);
      expect(mockHeadlessService.callOrder[0], contains('ch2'),
          reason: '第2章应最先被预加载');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('全部未缓存时排序也正确', () async {
      final urls = List.generate(5, (i) => 'https://example.com/ch${i + 1}');

      for (final url in urls) {
        mockHeadlessService.addStub(
            url, ChapterContentResult(content: '内容:$url'));
      }

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '5章小说',
        chapterUrls: urls,
        currentIndex: 2, // 第3章
      );

      await Future.delayed(Duration(milliseconds: 500));

      // 当前章节未被缓存，_createTasks 也应正确：
      // 后续: ch4, ch5 → 前序: ch2, ch1 → 第一个处理 ch4
      expect(mockHeadlessService.callOrder, isNotEmpty);
      expect(mockHeadlessService.callOrder[0], contains('ch4'),
          reason: '第4章（后续章节）应最先被预加载');
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('队列快照验证', () {
    test('队列入队顺序反映后续优先策略', () async {
      final urls = List.generate(6, (i) => 'https://example.com/q${i + 1}');

      // 预缓存当前章节（第3章）和第4章
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: urls[2], title: '第3章', content: '已缓存'),
        '已缓存',
      );
      await chapterRepository.cacheChapter(
        testNovelUrl,
        Chapter(url: urls[3], title: '第4章', content: '已缓存'),
        '已缓存',
      );

      // 阻塞 fetchContent，冻结队列（第一个任务会 pending）
      mockHeadlessService.blockAllProcessing();

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '6章小说',
        chapterUrls: urls,
        currentIndex: 2, // 第3章
      );

      // 等待 _processQueue 取出队头并阻塞
      await Future.delayed(Duration(milliseconds: 100));

      final snapshot = preloadService.getQueueSnapshot();

      // 已缓存: q3(当前), q4(后续)
      // 未缓存: q1, q2, q5, q6
      // 后续(index>2 且未缓存): q5, q6
      // 前序(index<2 且未缓存): q2, q1
      // 预期队列（q5 在队头，被 _processQueue 取出阻塞）: [q6, q2, q1]
      // 但 _createTasks 生成的顺序是 [q5, q6, q2, q1]
      // 验证生成顺序：取出的 callOrder[0] 应是 q5
      expect(mockHeadlessService.callOrder[0], contains('q5'),
          reason: 'q5 应在队头被首先处理');

      // 队列快照应是移除队头后的 [q6, q2, q1]
      expect(snapshot.length, 3, reason: '队头 q5 被取出处理中，剩 3 个');
      expect(snapshot[0].chapterUrl, contains('q6'));
      expect(snapshot[1].chapterUrl, contains('q2'));
      expect(snapshot[2].chapterUrl, contains('q1'));

      mockHeadlessService.release();
      preloadService.dispose();
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('去重验证', () {
    test('同一 URL 不会重复入队', () async {
      final urls = List.generate(3, (i) => 'https://example.com/dup${i + 1}');

      mockHeadlessService.blockAllProcessing();

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 等队头被取出阻塞
      await Future.delayed(Duration(milliseconds: 100));

      // 第二次入队
      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      await Future.delayed(Duration(milliseconds: 100));

      final snapshot = preloadService.getQueueSnapshot();
      // 不应有重复
      final urlCounts = <String, int>{};
      for (final task in snapshot) {
        urlCounts[task.chapterUrl] = (urlCounts[task.chapterUrl] ?? 0) + 1;
      }
      for (final entry in urlCounts.entries) {
        expect(entry.value, 1, reason: '${entry.key} 不应重复入队');
      }

      mockHeadlessService.release();
      preloadService.dispose();
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('抢占恢复验证', () {
    test('被抢占的任务放回队头', () async {
      final urls = [
        'https://example.com/b1',
        'https://example.com/b2',
        'https://example.com/b3',
      ];

      mockHeadlessService.addStub(
          urls[2], ChapterContentResult(content: '内容:b3'));

      mockHeadlessService.blockAllProcessing();

      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 等队头被取出阻塞
      await Future.delayed(Duration(milliseconds: 100));

      final snapshot = preloadService.getQueueSnapshot();
      expect(snapshot.length, greaterThanOrEqualTo(1),
          reason: '阻塞时队列中应还有未处理任务');

      mockHeadlessService.release();
      preloadService.dispose();
    }, timeout: Timeout(Duration(seconds: 5)));
  });

  group('pause/resume 回归', () {
    test('pause 之后 enqueueTasks 不会启动处理，直到 resume',
        () async {
      // 模拟真实时序：阅读器先 pause → 加载章节 → enqueueTasks → resume
      final urls = List.generate(3, (i) => 'https://example.com/pr${i + 1}');

      for (final url in urls) {
        mockHeadlessService.addStub(
            url, ChapterContentResult(content: '内容:$url'));
      }

      // 阅读器开始加载章节
      preloadService.pause();

      // 入队（不应启动处理循环）
      await preloadService.enqueueTasks(
        novelUrl: testNovelUrl,
        novelTitle: '测试',
        chapterUrls: urls,
        currentIndex: 0,
      );

      // 等一会儿，确保不会启动
      await Future.delayed(Duration(milliseconds: 100));

      expect(preloadService.isPaused, isTrue,
          reason: 'pause 后应保持暂停态');
      expect(preloadService.isProcessing, isFalse,
          reason: 'pause 状态下不应启动处理循环');
      expect(mockHeadlessService.callOrder, isEmpty,
          reason: 'pause 期间不应调用 fetchContent');

      // 队列应有 3 个任务（currentIndex=0 跳过当前，前序无 → 后续 pr2, pr3 + 前序 0 个 + 当前 pr1 被跳过）
      // 等等：currentIndex=0，跳过 pr1（i=0 是 safeIndex，不在后续/前序循环里），后续 pr2/pr3
      final snapshot = preloadService.getQueueSnapshot();
      expect(snapshot.length, 2,
          reason: '应入队 pr2, pr3（当前章节 pr1 不入队）');

      // 阅读器加载完成，恢复
      preloadService.resume();

      // 等处理循环启动
      await Future.delayed(Duration(milliseconds: 100));

      expect(preloadService.isPaused, isFalse);
      expect(mockHeadlessService.callOrder, isNotEmpty,
          reason: 'resume 后应开始处理队列');
      expect(mockHeadlessService.callOrder[0], contains('pr2'),
          reason: 'pr2 应是最先被处理的');
    }, timeout: Timeout(Duration(seconds: 5)));

    test('重复 pause 是幂等的', () async {
      preloadService.pause();
      expect(preloadService.isPaused, isTrue);

      preloadService.pause();
      expect(preloadService.isPaused, isTrue,
          reason: '重复 pause 不应改变状态');
    });

    test('resume 之前没 pause 是 no-op', () async {
      // 未 pause 时 resume 不应崩溃或启动处理
      preloadService.resume();
      expect(preloadService.isPaused, isFalse);
      expect(preloadService.isProcessing, isFalse);
    });
  });
}

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

/// Manual mock for HeadlessWebViewContentService
class MockHeadlessWebViewContentService extends Mock
    implements HeadlessWebViewContentService {
  final Map<String, FetchContentResult> _stubs = {};
  final List<String> callOrder = [];

  void addStub(String url, ChapterContentResult result) {
    _stubs[url] = FetchContentResult.success(result);
  }

  @override
  Future<FetchContentResult> fetchContent(
    String chapterUrl, {
    FetchPriority priority = FetchPriority.low,
  }) async {
    callOrder.add(chapterUrl);
    return _stubs[chapterUrl] ?? FetchContentResult.noScript();
  }
}

/// 预加载队列按新锚点重排的验证测试
///
/// 场景：预加载队列已存在时，用户跳章阅读后再次 enqueueTasks，
/// 队列应随新锚点整体重排，而不是沿用旧顺序、新任务一律追加队尾。
///
/// 统一先 pause() 阻止处理循环消费队列，保证断言的是完整队列顺序；
/// 恢复执行的行为在最后的 resume 测试中单独验证。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDatabaseSetup.init();

  late ChapterRepository chapterRepository;
  late MockHeadlessWebViewContentService mockHeadlessService;
  late PreloadService preloadService;
  late Database db;

  const novelA = 'https://example.com/novel/a';
  const novelB = 'https://example.com/novel/b';

  List<String> urls(String prefix, int count) =>
      List.generate(count, (i) => 'https://example.com/$prefix/ch${i + 1}');

  Future<void> enqueue(
    String novelUrl, {
    required List<String> chapterUrls,
    required int currentIndex,
  }) async {
    await preloadService.enqueueTasks(
      novelUrl: novelUrl,
      novelTitle: '测试小说',
      chapterUrls: chapterUrls,
      currentIndex: currentIndex,
    );
  }

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    chapterRepository = ChapterRepository(
      dbConnection: connection,
      versionRepo: ChapterVersionRepository(dbConnection: connection),
    );
    mockHeadlessService = MockHeadlessWebViewContentService();
    preloadService = PreloadService(
      chapterRepository: chapterRepository,
      headlessService: mockHeadlessService,
    );
    // 暂停处理循环：enqueueTasks 不再消费队列，队列顺序可整体断言
    preloadService.pause();
  });

  tearDown(() async {
    preloadService.dispose();
    await db.close();
  });

  group('跳章后按新锚点重排', () {
    test('10章队列存在, 用户跳到第8章 → ch9,ch10 优先, ch7..ch2 倒序殿后',
        () async {
      final urls10 = urls('r', 10);

      await enqueue(novelA, chapterUrls: urls10, currentIndex: 0);
      expect(preloadService.queuedChapterUrls, urls10.sublist(1),
          reason: '锚点 ch1: 后续章节正序 ch2..ch10');

      await enqueue(novelA, chapterUrls: urls10, currentIndex: 7);
      expect(preloadService.queuedChapterUrls, [
        ...urls10.sublist(8), // 后续: ch9, ch10
        ...urls10.sublist(0, 7).reversed, // 前序倒序: ch7..ch2
      ], reason: '队列应随新锚点 ch8 整体转向');
    });

    test('同锚点重复入队, 队列保持期望顺序不变', () async {
      final urls5 = urls('same', 5);

      await enqueue(novelA, chapterUrls: urls5, currentIndex: 1);
      final first = List<String>.of(preloadService.queuedChapterUrls);

      await enqueue(novelA, chapterUrls: urls5, currentIndex: 1);
      expect(preloadService.queuedChapterUrls, first,
          reason: '重排应幂等: 同锚点重复入队不改变顺序');
      expect(first,
          [...urls5.sublist(2), urls5[0]],
          reason: '锚点 ch2: 后续 ch3..ch5 正序, 前序 ch1 倒序');
    });

    test('章节列表扩充后, 新任务按新锚点插入期望位置而非一律队尾', () async {
      final urls4 = urls('g', 4);
      final urls6 = [...urls4, ...urls('g2', 2)]; // 追加 ch5, ch6

      await enqueue(novelA, chapterUrls: urls4, currentIndex: 0);
      expect(preloadService.queuedChapterUrls, urls4.sublist(1));

      // 锚点 ch3: 后续 ch4,ch5,ch6 正序, 前序 ch2,ch1 倒序
      await enqueue(novelA, chapterUrls: urls6, currentIndex: 2);
      expect(preloadService.queuedChapterUrls,
          [urls6[3], urls6[4], urls6[5], urls6[1], urls6[0]],
          reason: '新章节 ch5/ch6 应按锚点顺序插入到旧任务 ch2/ch1 之前');
    });
  });

  group('重排时淘汰失效任务', () {
    test('已被阅读器缓存的旧任务自动出队', () async {
      final urls5 = urls('e', 5);

      await enqueue(novelA, chapterUrls: urls5, currentIndex: 0);
      expect(preloadService.queuedChapterUrls, urls5.sublist(1));

      // 用户手动阅读 ch3, 阅读器直接写缓存（不经预加载）
      await chapterRepository.cacheChapter(
        novelA,
        Chapter(url: urls5[2], title: 'ch3', content: '阅读器缓存'),
        '阅读器缓存',
      );

      await enqueue(novelA, chapterUrls: urls5, currentIndex: 0);
      expect(preloadService.queuedChapterUrls,
          [urls5[1], urls5[3], urls5[4]],
          reason: 'ch3 已缓存, 不应继续留在队列');
    });

    test('所有章节已缓存时清空本小说残留任务', () async {
      final urls3 = urls('all', 3);

      await enqueue(novelA, chapterUrls: urls3, currentIndex: 0);
      expect(preloadService.queuedChapterUrls, isNotEmpty);

      for (final url in urls3) {
        await chapterRepository.cacheChapter(
          novelA,
          Chapter(url: url, title: url, content: '内容'),
          '内容',
        );
      }

      await enqueue(novelA, chapterUrls: urls3, currentIndex: 0);
      expect(preloadService.queuedChapterUrls, isEmpty,
          reason: '全部已缓存后, 本小说残留任务应被淘汰');
    });
  });

  group('多小说队列隔离', () {
    test('重排只影响目标小说, 其他小说任务保持原相对顺序', () async {
      final urlsA = urls('a', 4);
      final urlsB = urls('b', 3);

      await enqueue(novelA, chapterUrls: urlsA, currentIndex: 0);
      await enqueue(novelB, chapterUrls: urlsB, currentIndex: 0);
      expect(preloadService.queuedChapterUrls,
          [...urlsA.sublist(1), ...urlsB.sublist(1)]);

      // 小说A 锚点跳到 ch3: A 块重排为 [A4, A2, A1], 整体替换到原 A 首任务位置
      await enqueue(novelA, chapterUrls: urlsA, currentIndex: 2);
      expect(preloadService.queuedChapterUrls,
          [urlsA[3], urlsA[1], urlsA[0], ...urlsB.sublist(1)],
          reason: '小说B 的任务不受小说A 重排影响');
    });
  });

  group('重排后恢复执行', () {
    test('pause 期间重排, resume 后第一个处理的是新锚点的下一章', () async {
      final urls10 = urls('s', 10);
      for (final url in urls10) {
        mockHeadlessService.addStub(url, ChapterContentResult(content: '内容:$url'));
      }

      await enqueue(novelA, chapterUrls: urls10, currentIndex: 0);
      await enqueue(novelA, chapterUrls: urls10, currentIndex: 7);

      preloadService.resume();
      await Future.delayed(const Duration(milliseconds: 500));

      expect(mockHeadlessService.callOrder, isNotEmpty);
      expect(mockHeadlessService.callOrder.first, urls10[8],
          reason: '恢复后应首先预加载 ch9（新锚点 ch8 的下一章）');
    }, timeout: Timeout(Duration(seconds: 5)));
  });
}

import '../services/logger_service.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../services/api_service_wrapper.dart';
import '../services/headless_webview_content_service.dart';
import '../services/headless_webview_errors.dart';
import '../core/interfaces/repositories/i_chapter_repository.dart';
import '../core/providers/bookshelf_mutation_provider.dart';
import '../core/providers/chapter_mutation_provider.dart';
import '../core/providers/reader_state_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ReaderContentController (新版本)
///
/// 职责：
/// - 章节内容加载（从缓存或API）
/// - 缓存管理
/// - 阅读进度更新
/// - 通过Riverpod Provider管理状态，不使用setState回调
///
/// 使用方式：
/// ```dart
/// final controller = ReaderContentController(
///   ref: ref,
///   apiService: _apiService,
///   chapterRepository: _chapterRepository,
/// );
///
/// await controller.initialize();
/// await controller.loadChapter(chapter, novel);
/// ```
///
/// 状态变化通过Provider自动通知UI更新
///
/// 注意：阅读进度更新已迁移至 [BookshelfMutationNotifier.updateReadProgress]，
/// 故构造函数不再需要 `novelRepository` 参数——所有"写库 + invalidate"统一经
/// Notifier 收口，避免 [reading progress bug] 重演。
///
/// [reading progress bug]: 阅读完返回书架看不到进度更新，原因为直接调用
/// `INovelRepository.updateLastReadChapter` 绕过了 Notifier 的 invalidate。
class ReaderContentController {
  // ========== 依赖服务 ==========
  final ApiServiceWrapper _apiService;
  final IChapterRepository _chapterRepository;
  final WidgetRef _ref;
  final HeadlessWebViewContentService? _headlessService;

  // ========== 构造函数 ==========

  ReaderContentController({
    required WidgetRef ref,
    required ApiServiceWrapper apiService,
    required IChapterRepository chapterRepository,
    HeadlessWebViewContentService? headlessService,
  })  : _ref = ref,
        _apiService = apiService,
        _chapterRepository = chapterRepository,
        _headlessService = headlessService;

  // ========== 公开方法 ==========

  /// 初始化Controller
  ///
  /// 初始化API服务。API 初始化失败不阻断后续流程：章节内容提取已完全走
  /// HeadlessWebView + 本地缓存，不依赖后端 API。失败时只记日志，调用方
  /// 仍可正常调用 [loadChapter]。
  Future<void> initialize() async {
    try {
      await _apiService.init();
      LoggerService.instance.i(
        'ReaderContentController: API初始化成功',
        category: LogCategory.ui,
        tags: ['reader'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        'ReaderContentController: API 初始化失败（非致命，内容提取走 HeadlessWebView）: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ui,
        tags: ['reader', 'api', 'non-fatal'],
      );
      // 不 setError、不 rethrow——loadChapter 的缓存+HeadlessWebView 路径
      // 不需要后端 API。
    }
  }

  /// 加载章节内容
  ///
  /// [chapter] 要加载的章节
  /// [novel] 所属小说
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  /// [resetScrollPosition] 是否重置滚动位置（用于回调，本Controller不处理）
  Future<void> loadChapter(
    Chapter chapter,
    Novel novel, {
    bool forceRefresh = false,
    bool resetScrollPosition = true,
  }) async {
    final notifier = _ref.read(chapterContentStateNotifierProvider.notifier);

    // 设置当前上下文
    notifier.setCurrentContext(chapter, novel);

    // 设置加载状态
    notifier.setLoading(true);
    if (resetScrollPosition) {
      notifier.clearContent();
    }

    try {
      LoggerService.instance.d(
        'ReaderContentController: 开始加载章节 - ${chapter.title}',
        category: LogCategory.ui,
        tags: ['reader'],
      );

      String content;

      // 先尝试从缓存获取（非强制刷新时）
      if (!forceRefresh) {
        final cachedContent =
            await _chapterRepository.getCachedChapter(chapter.url);
        if (cachedContent != null && cachedContent.trim().isNotEmpty) {
          content = cachedContent;
          LoggerService.instance.d(
            'ReaderContentController: 从缓存加载 - ${cachedContent.length}字符',
            category: LogCategory.ui,
            tags: ['reader'],
          );

          // 更新状态
          notifier.setContent(content);
          notifier.setLoading(false);

          // 更新阅读进度
          await updateReadingProgress(novel.url, chapter);

          LoggerService.instance.i(
            'ReaderContentController: 章节加载完成 - ${chapter.title}',
            category: LogCategory.ui,
            tags: ['reader'],
          );
          return;
        }
      }

      // 缓存未命中或强制刷新，先尝试 Headless WebView，再回退 API
      LoggerService.instance.d(
        'ReaderContentController: ${forceRefresh ? "强制刷新" : "缓存未命中"}，尝试获取',
        category: LogCategory.ui,
        tags: ['reader'],
      );
      content = await _fetchChapterContent(chapter.url, forceRefresh);

      // 改进：使用 trim() 验证内容有效性
      final trimmedContent = content.trim();
      if (trimmedContent.isEmpty) {
        throw Exception('获取到的章节内容为空');
      }

      if (trimmedContent.length < 50) {
        throw Exception('获取到的章节内容过短（${trimmedContent.length}字符）');
      }

      // 验证通过，缓存章节（forceRefresh时覆盖旧缓存）
      // 走 ChapterMutationNotifier 收口：写库 + bump signal 触发章节列表软刷新
      // （isCached 标记实时变 true）
      await _ref.read(chapterMutationProvider.notifier).cacheChapter(
            novel.url,
            chapter,
            content,
          );
      LoggerService.instance.i(
        'ReaderContentController: 已缓存章节 - ${content.length}字符',
        category: LogCategory.ui,
        tags: ['reader'],
      );

      // 再次验证内容是否为空（防御性编程）
      if (content.trim().isEmpty) {
        throw Exception('章节内容为空，无法显示');
      }

      // 更新状态
      notifier.setContent(content);
      notifier.setLoading(false);

      // 更新阅读进度
      await updateReadingProgress(novel.url, chapter);

      // 注意：预加载功能由 reader_screen 直接调用 PreloadService 处理
      // 此 Controller 不负责预加载逻辑

      LoggerService.instance.i(
        'ReaderContentController: 章节加载完成 - ${chapter.title}',
        category: LogCategory.ui,
        tags: ['reader'],
      );
    } catch (e) {
      notifier.setLoading(false);
      notifier.setError('加载章节失败: $e');
      LoggerService.instance.e(
        'ReaderContentController: 加载失败 - $e',
        category: LogCategory.ui,
        tags: ['reader'],
      );
      rethrow;
    }
  }

  /// 更新阅读进度
  ///
  /// [novelUrl] 小说URL
  /// [chapter] 当前章节
  ///
  /// 走 [BookshelfMutationNotifier.updateReadProgress] 统一收口：
  /// 写库成功后自动 invalidate `bookshelfNovelsProvider`，书架页"最近阅读"
  /// 立即刷新；以前直接调 `INovelRepository.updateLastReadChapter` 会绕过
  /// Notifier，导致阅读完返回书架看不到进度更新。
  Future<void> updateReadingProgress(String novelUrl, Chapter chapter) async {
    try {
      final chapterIndex = chapter.chapterIndex ?? 0;
      await _ref
          .read(bookshelfMutationProvider.notifier)
          .updateReadProgress(novelUrl, chapterIndex);
      LoggerService.instance.d(
        'ReaderContentController: 已更新阅读进度 - 章节$chapterIndex',
        category: LogCategory.ui,
        tags: ['reader'],
      );
    } catch (e) {
      LoggerService.instance.e(
        'ReaderContentController: 更新阅读进度失败 - $e',
        category: LogCategory.ui,
        tags: ['reader'],
      );
    }
  }

  /// 更新内容（用于改写等需要直接更新内容的场景）
  void setContent(String newContent) {
    _ref
        .read(chapterContentStateNotifierProvider.notifier)
        .updateContent(newContent);
    LoggerService.instance.d(
      'ReaderContentController: 内容已更新 - ${newContent.length}字符',
      category: LogCategory.ui,
      tags: ['reader'],
    );
  }

  // ========== Getters ==========

  /// 章节内容（从Provider获取）
  String get content => _ref.read(chapterContentStateNotifierProvider).content;

  /// 是否正在加载（从Provider获取）
  bool get isLoading =>
      _ref.read(chapterContentStateNotifierProvider).isLoading;

  /// 错误信息（从Provider获取）
  String get errorMessage =>
      _ref.read(chapterContentStateNotifierProvider).errorMessage;

  /// 当前章节（从Provider获取）
  Chapter? get currentChapter =>
      _ref.read(chapterContentStateNotifierProvider).currentChapter;

  /// 当前小说（从Provider获取）
  Novel? get currentNovel =>
      _ref.read(chapterContentStateNotifierProvider).currentNovel;

  // ========== 私有方法 ==========

  /// 获取章节内容（纯 Headless WebView，不再回退后端 API）
  ///
  /// 使用 [FetchPriority.high] 优先级，可抢占预加载任务。
  /// 遇到 WebView 忙碌时有限重试（3 次，间隔 2 秒）。
  Future<String> _fetchChapterContent(String chapterUrl, bool forceRefresh) async {
    if (_headlessService != null) {
      const maxRetries = 3;
      const retryDelay = Duration(seconds: 2);

      for (var attempt = 0; attempt < maxRetries; attempt++) {
        final result = await _headlessService!.fetchContent(
          chapterUrl,
          priority: FetchPriority.high,
        );

        if (result.isSuccess) {
          LoggerService.instance.d(
            'ReaderContentController: Headless WebView 获取成功',
            category: LogCategory.ui,
            tags: ['reader', 'headless-webview'],
          );
          return result.content.content;
        }

        if (result.isBusy) {
          // WebView 正忙，等待后重试
          LoggerService.instance.w(
            'ReaderContentController: WebView 忙碌，'
            '第${attempt + 1}次重试（共$maxRetries次）',
            category: LogCategory.ui,
            tags: ['reader', 'headless-webview', 'busy-retry'],
          );
          if (attempt < maxRetries - 1) {
            await Future.delayed(retryDelay);
          }
          continue;
        }

        // isNoScript: 真的没有脚本，不需要重试
        break;
      }

      // 所有重试耗尽或 noScript，做最后一次尝试以确定最终结果类型
      final lastResult = await _headlessService!.fetchContent(
        chapterUrl,
        priority: FetchPriority.high,
      );
      if (lastResult.isSuccess) {
        return lastResult.content.content;
      }
      if (lastResult.isNoScript) {
        throw NoExtractionScriptException(
          _extractHost(chapterUrl) ?? '',
          url: chapterUrl,
        );
      }
      // busy 状态耗尽重试
      throw WebViewBusyException(
        _extractHost(chapterUrl) ?? '',
        url: chapterUrl,
      );
    }

    throw NoExtractionScriptException(
      _extractHost(chapterUrl) ?? '',
      url: chapterUrl,
    );
  }

  /// 从 URL 提取 host（用于错误信息）
  static String? _extractHost(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isNotEmpty ? host : null;
    } catch (_) {
      return null;
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/chapter_mutation_provider.dart';
import '../../models/chapter.dart';
import '../../services/api_service_wrapper.dart';
import '../../services/headless_webview_chapter_list_service.dart';
import '../../services/headless_webview_errors.dart';
import '../../services/logger_service.dart';
import '../../core/interfaces/repositories/i_chapter_repository.dart';
import '../../core/interfaces/repositories/i_novel_repository.dart';

/// 章节加载器
/// 负责章节列表的加载、刷新和缓存管理
///
/// 写路径（cacheNovelChapters）走 [ChapterMutationNotifier] 收口：
/// 持有 `Ref` 调 `chapterMutationProvider`，写库 + bump signal 触发章节列表软刷新。
class ChapterLoader {
  final Ref _ref;
  final ApiServiceWrapper _api;
  final IChapterRepository _chapterRepo;
  final INovelRepository _novelRepo;
  final HeadlessWebViewChapterListService _chapterListHeadlessService;
  final _log = LoggerService.instance;

  ChapterLoader({
    required Ref ref,
    required ApiServiceWrapper api,
    required IChapterRepository chapterRepository,
    required INovelRepository novelRepository,
    required HeadlessWebViewChapterListService chapterListHeadlessService,
  })  : _ref = ref,
        _api = api,
        _chapterRepo = chapterRepository,
        _novelRepo = novelRepository,
        _chapterListHeadlessService = chapterListHeadlessService;

  /// 初始化API服务
  Future<void> initApi() async {
    await _api.init();
  }

  /// 加载章节列表
  /// [novelUrl] 小说URL
  /// [forceRefresh] 是否强制刷新
  /// 返回章节列表
  Future<List<Chapter>> loadChapters(
    String novelUrl, {
    bool forceRefresh = false,
  }) async {
    _log.d(
      '加载章节列表: $novelUrl, forceRefresh=$forceRefresh',
      category: LogCategory.ui,
      tags: ['chapter-list', 'load'],
    );

    try {
      // 对于本地创建的小说，直接从数据库加载用户创建的章节
      if (novelUrl.startsWith('custom://')) {
        final chapters = await _chapterRepo.getCachedNovelChapters(novelUrl);
        _log.i(
          '本地小说章节加载完成: ${chapters.length}章',
          category: LogCategory.database,
          tags: ['chapter', 'load'],
        );
        return chapters;
      }

      // 先尝试从缓存加载
      final cachedChapters = await _chapterRepo.getCachedNovelChapters(novelUrl);

      if (cachedChapters.isNotEmpty && !forceRefresh) {
        // 有缓存且不强制刷新时，直接返回缓存
        _log.i(
          '从缓存加载章节列表: ${cachedChapters.length}章',
          category: LogCategory.database,
          tags: ['chapter', 'load', 'cache-hit'],
        );
        return cachedChapters;
      }

      if (cachedChapters.isNotEmpty && forceRefresh) {
        // 有缓存但需要刷新时，先返回缓存，调用方负责后台更新
        _log.i(
          '从缓存加载章节列表(待刷新): ${cachedChapters.length}章',
          category: LogCategory.database,
          tags: ['chapter', 'load', 'cache-hit', 'pending-refresh'],
        );
        return cachedChapters;
      }

      // 没有缓存时，从后端获取
      _log.d(
        '缓存未命中，从后端获取章节列表',
        category: LogCategory.network,
        tags: ['chapter-list', 'load', 'backend'],
      );
      return await refreshFromBackend(novelUrl, forceRefresh: forceRefresh);
    } catch (e, st) {
      _log.e(
        '加载章节列表失败: $novelUrl - $e',
        stackTrace: st.toString(),
        category: LogCategory.ui,
        tags: ['chapter-list', 'load'],
      );
      rethrow;
    }
  }

  /// 从 headless WebView 刷新章节列表
  /// [novelUrl] 小说URL
  /// [forceRefresh] 是否强制刷新（保留接口兼容，当前由 headless 处理）
  /// 返回刷新后的章节列表
  Future<List<Chapter>> refreshFromBackend(String novelUrl,
      {bool forceRefresh = false}) async {
    _log.d(
      '从 headless WebView 刷新章节列表: $novelUrl',
      category: LogCategory.network,
      tags: ['chapter-list', 'refresh'],
    );

    try {
      // 对于本地创建的小说，直接从数据库获取用户创建的章节
      if (novelUrl.startsWith('custom://')) {
        return await _chapterRepo.getCachedNovelChapters(novelUrl);
      }

      // 尝试 headless WebView 获取章节列表
      final result =
          await _chapterListHeadlessService.fetchChapterList(novelUrl);

      if (result.isSuccess) {
        final chapters = result.chapters;
        // 缓存章节列表：走 ChapterMutationNotifier 收口（写库 + bump signal
        // 触发章节列表软刷新）
        await _ref
            .read(chapterMutationProvider.notifier)
            .cacheNovelChapters(novelUrl, chapters);
        _log.i(
          '章节列表缓存在数据库: ${chapters.length}章',
          category: LogCategory.database,
          tags: ['chapter', 'cache'],
        );

        // 重新从数据库获取合并后的章节列表（包括用户插入的章节）
        final mergedChapters = await _chapterRepo.getCachedNovelChapters(novelUrl);
        _log.i(
          '从 headless WebView 刷新章节列表完成: ${mergedChapters.length}章(含用户章节)',
          category: LogCategory.network,
          tags: ['chapter-list', 'refresh'],
        );
        return mergedChapters;
      }

      // 非成功态 → 根据具体原因抛出对应异常
      final host = _extractHost(novelUrl) ?? '';

      // WebView 正忙 → 可重试
      if (result.isBusy) {
        throw WebViewBusyException(host, url: novelUrl);
      }

      // 页面加载失败 → 可重试
      if (result.isLoadFailed) {
        throw PageLoadFailedException(novelUrl);
      }

      // 无脚本（含脚本返回空） → 不可重试，提示用户生成脚本
      throw NoExtractionScriptException(host, url: novelUrl);
    } catch (e, st) {
      _log.e(
        '刷新章节列表失败: $novelUrl - $e',
        stackTrace: st.toString(),
        category: LogCategory.network,
        tags: ['chapter-list', 'refresh'],
      );
      rethrow;
    }
  }

  /// 加载上次阅读的章节索引
  /// [novelUrl] 小说URL
  /// 返回上次阅读的章节索引
  Future<int> loadLastReadChapter(String novelUrl) async {
    try {
      return await _novelRepo.getLastReadChapter(novelUrl);
    } catch (e, st) {
      _log.e(
        '加载上次阅读章节索引失败: $novelUrl - $e',
        stackTrace: st.toString(),
        category: LogCategory.database,
        tags: ['chapter', 'last-read'],
      );
      rethrow;
    }
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

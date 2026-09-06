import '../models/chapter.dart';
import '../services/headless_webview_content_service.dart';
import '../services/headless_webview_errors.dart';
import '../core/interfaces/repositories/i_chapter_repository.dart';
import 'logger_service.dart';

/// ChapterHistoryService
///
/// 职责：
/// - 获取历史章节内容（用于AI生成的上下文）
/// - 统一历史章节加载逻辑
/// - 支持缓存和 Headless WebView 获取
///
/// 使用方式：
/// ```dart
/// // 通过Provider获取（推荐）
/// final service = ref.watch(chapterHistoryServiceProvider);
///
/// // 或手动指定依赖
/// final service = ChapterHistoryService(
///   chapterRepo: _chapterRepo,
///   headlessService: _headlessService,
/// );
///
/// final historyContent = await service.fetchHistoryChaptersContent(
///   chapters: widget.chapters,
///   currentChapter: widget.currentChapter,
///   maxHistoryCount: 2,
/// );
/// ```
class ChapterHistoryService {
  static const LogCategory _category = LogCategory.database;
  static const List<String> _tags = ['history'];
  final IChapterRepository _chapterRepo;
  final HeadlessWebViewContentService? _headlessService;

  /// 创建 ChapterHistoryService 实例
  ///
  /// 参数:
  /// - [chapterRepo] 章节仓库（必需）
  /// - [headlessService] Headless WebView 内容服务（可选，用于获取章节内容）
  ChapterHistoryService({
    required IChapterRepository chapterRepo,
    HeadlessWebViewContentService? headlessService,
  })  : _chapterRepo = chapterRepo,
        _headlessService = headlessService;

  /// 获取历史章节内容（最多前N章）
  ///
  /// [chapters] 所有章节列表
  /// [currentChapter] 当前章节
  /// [maxHistoryCount] 最大历史章节数量（默认2）
  ///
  /// 返回格式化后的历史章节内容字符串
  Future<String> fetchHistoryChaptersContent({
    required List<Chapter> chapters,
    required Chapter currentChapter,
    int maxHistoryCount = 2,
  }) async {
    final currentIndex = chapters.indexWhere(
      (c) => c.url == currentChapter.url,
    );

    if (currentIndex == -1) {
      LoggerService.instance.w('未找到当前章节索引', category: _category, tags: _tags);
      return '';
    }

    LoggerService.instance.d('当前章节索引=$currentIndex, 开始获取历史章节', category: _category, tags: _tags);

    final historyContents = <String>[];

    // 从最近到最远获取历史章节
    for (int i = 1; i <= maxHistoryCount; i++) {
      final historyIndex = currentIndex - i;
      if (historyIndex >= 0 && historyIndex < chapters.length) {
        final chapter = chapters[historyIndex];

        try {
          final content = await _loadChapterContent(chapter);
          if (content == null) {
            LoggerService.instance.w('无提取脚本，跳过 - ${chapter.title}', category: _category, tags: _tags);
            continue;
          }

          // 格式化为历史章节内容
          historyContents.add('历史章节: ${chapter.title}\n\n$content');
          LoggerService.instance.i('已加载历史章节 - ${chapter.title} (${content.length}字符)', category: _category, tags: _tags);
        } catch (e) {
          LoggerService.instance.e('加载历史章节失败 - ${chapter.title}', category: _category, tags: _tags);
          // 继续加载其他章节，不中断
        }
      }
    }

    final result = historyContents.join('\n\n');
    LoggerService.instance.i('历史章节加载完成，共${historyContents.length}章，总计${result.length}字符', category: _category, tags: _tags);

    return result;
  }

  /// 仅获取历史章节内容列表（不格式化）
  ///
  /// 返回章节内容列表（纯内容，不包含标题前缀）
  Future<List<String>> fetchHistoryChaptersList({
    required List<Chapter> chapters,
    required Chapter currentChapter,
    int maxHistoryCount = 2,
  }) async {
    final currentIndex = chapters.indexWhere(
      (c) => c.url == currentChapter.url,
    );

    if (currentIndex == -1) return [];

    final historyContents = <String>[];

    for (int i = 1; i <= maxHistoryCount; i++) {
      final historyIndex = currentIndex - i;
      if (historyIndex >= 0 && historyIndex < chapters.length) {
        final chapter = chapters[historyIndex];

        try {
          final content = await _loadChapterContent(chapter);
          if (content != null) {
            historyContents.add(content);
          }
        } catch (e) {
          LoggerService.instance.e('加载失败 - ${chapter.title}', category: _category, tags: _tags);
        }
      }
    }

    return historyContents;
  }

  /// 加载单个章节内容：先查缓存，未命中时尝试 Headless WebView。
  ///
  /// 返回 `null` 表示无法获取（缓存未命中 + 无 headless 脚本）。
  /// 抛异常表示 fetch 过程中出错（由调用方决定是否继续）。
  Future<String?> _loadChapterContent(Chapter chapter) async {
    final cached = await _chapterRepo.getCachedChapter(chapter.url);
    if (cached != null && cached.isNotEmpty) {
      LoggerService.instance.d('从缓存加载 - ${chapter.title}', category: _category, tags: _tags);
      return cached;
    }

    if (_headlessService == null) return null;

    LoggerService.instance.d('缓存未命中，尝试 Headless WebView - ${chapter.title}', category: _category, tags: _tags);
    final result = await _headlessService!.fetchContent(
      chapter.url,
      priority: FetchPriority.low, // 后台获取，不抢占阅读器
    );
    // busy 时直接返回 null（非关键路径）；noScript 也返回 null
    if (result.isSuccess && result.content.content.trim().isNotEmpty) {
      return result.content.content;
    }
    return null;
  }
}

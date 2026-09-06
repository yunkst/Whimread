import '../../../models/chapter.dart';
import '../../../models/search_result.dart';

/// 章节数据仓库接口
///
/// 负责章节内容缓存、章节列表管理和用户自定义章节的数据访问操作。
///
/// ## 写方法脱钩说明（2026-07-29 章节写入收口重构）
///
/// 12 个写方法已从本接口迁出到内部 `IChapterWriter`（定义在
/// `lib/repositories/chapter_repository.dart`），仅 [ChapterMutationNotifier]
/// 通过 `chapterWriterProvider` 持有写能力。普通调用方持有 `IChapterRepository`
/// 类型拿不到写方法，编译期阻止绕过 Notifier 直接写库——正是「agent 写完章节
/// 列表不刷新」bug 的根因。
///
/// 所有调用点必须改走 `chapterMutationProvider` 收口路径（参见 plan
/// `docs/superpowers/plans/2026-07-29-chapter-mutation-notifier.md`）。
abstract class IChapterRepository {
  // ========== 章节缓存管理 ==========

  /// 检查章节是否已缓存（内存优先）
  ///
  /// [chapterUrl] 章节的URL
  /// 返回是否已缓存
  Future<bool> isChapterCached(String chapterUrl);

  /// 批量检查缓存状态，返回未缓存的章节URL列表
  ///
  /// [chapterUrls] 章节URL列表
  /// 返回未缓存的章节URL列表
  Future<List<String>> filterUncachedChapters(List<String> chapterUrls);

  /// 批量查询章节缓存状态
  ///
  /// [chapterUrls] 章节URL列表
  /// 返回章节URL到缓存状态的映射
  Future<Map<String, bool>> getChaptersCacheStatus(List<String> chapterUrls);

  // ========== 预加载状态管理 ==========
  // 注意：预加载状态由 PreloadService 内部维护，不属于 Repository 职责。

  /// 清理内存状态
  void clearMemoryState();

  // ========== 章节内容查询 ==========

  /// 获取缓存的章节内容
  ///
  /// [chapterUrl] 章节的URL
  /// 返回章节内容，如果不存在则返回null
  Future<String?> getCachedChapter(String chapterUrl);

  /// 获取小说的所有缓存章节
  ///
  /// [novelUrl] 小说的URL
  /// 返回章节列表，按章节索引升序排列
  Future<List<Chapter>> getCachedChapters(String novelUrl);

  // ========== 章节列表查询 ==========

  /// 获取缓存的章节列表
  ///
  /// [novelUrl] 小说的URL
  /// 返回章节列表，按章节索引升序排列
  Future<List<Chapter>> getCachedNovelChapters(String novelUrl);

  // ========== 用户自定义章节判定 ==========

  /// 判断是否为本地章节
  ///
  /// [chapterUrl] 章节的URL
  /// 返回是否为本地章节
  static bool isLocalChapter(String chapterUrl) {
    return chapterUrl.startsWith('custom://') ||
        chapterUrl.startsWith('user_chapter_');
  }

  // ========== 阅读状态查询 ==========

  /// 获取已缓存的章节数量（实际有内容的章节）
  ///
  /// [novelUrl] 小说的URL
  /// 返回 chapter_cache 表中已缓存的章节数量
  Future<int> getCachedChaptersCount(String novelUrl);

  /// 获取小说的总章节数
  ///
  /// [novelUrl] 小说的URL
  /// 返回 novel_chapters 表中的章节总数
  Future<int> getTotalChaptersCount(String novelUrl);

  // ========== 章节内容搜索 ==========

  /// 搜索缓存章节内容
  ///
  /// [keyword] 搜索关键词
  /// [novelUrl] 可选的小说URL，用于限制搜索范围
  /// 返回匹配的章节搜索结果列表
  Future<List<ChapterSearchResult>> searchInCachedContent(
    String keyword, {
    String? novelUrl,
  });

  // ========== ID-based 查询方法（Agent 工具用） ==========

  /// 根据 ID 查询章节（JOIN 两表获取完整信息）
  ///
  /// [id] novel_chapters.id
  /// 返回 Chapter 对象，不存在则返回 null
  Future<Chapter?> getChapterById(int id);

  /// 根据 ID 获取章节 URL（内部 ID→URL 解析用）
  ///
  /// [id] novel_chapters.id
  /// 返回 chapterUrl，不存在则返回 null
  Future<String?> getChapterUrlById(int id);

  /// 根据 ID 检查章节是否存在
  ///
  /// [id] novel_chapters.id
  /// 返回是否存在的布尔值
  Future<bool> chapterExistsById(int id);

  /// 根据 URL 获取章节 ID（搜索结果用）
  ///
  /// [url] chapterUrl
  /// 返回 novel_chapters.id，不存在则返回 null
  Future<int?> getChapterIdByUrl(String url);
}

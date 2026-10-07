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


  // ========== 章节内容查询 ==========

  /// 获取缓存的章节内容
  ///
  /// [chapterUrl] 章节的URL
  /// 返回章节内容，如果不存在则返回null
  Future<String?> getCachedChapter(String chapterUrl);

  // ========== 章节列表查询 ==========

  /// 获取缓存的章节列表
  ///
  /// [novelUrl] 小说的URL
  /// 返回章节列表，按章节索引升序排列
  Future<List<Chapter>> getCachedNovelChapters(String novelUrl);

  // ========== 用户自定义章节判定 ==========


  // ========== 阅读状态查询 ==========


  /// 获取小说的总章节数
  ///
  /// [novelUrl] 小说的URL
  /// 返回 novel_chapters 表中的章节总数
  Future<int> getTotalChaptersCount(String novelUrl);

  /// 批量获取多本小说的缓存/总章节数（单条 GROUP BY 查询）
  ///
  /// 供书架页统计使用，替代逐本 2 次 COUNT 的 N+1 模式。
  /// 结果中缺失的 url 表示该小说无章节记录。
  Future<Map<String, ({int cached, int total})>> getChapterCountsForNovels(
    List<String> novelUrls,
  );

  // ========== 章节内容搜索 ==========

  /// 搜索缓存章节内容（章节正文与标题）
  ///
  /// [keyword] 搜索关键词
  /// [novelUrl] 可选的小说URL，用于限制搜索范围
  ///
  /// 返回命中结果列表及是否被行数上限截断（[ChapterSearchResultSet]）。
  /// 关键词命中正文或章节标题任一即返回该章；仅标题命中的行
  /// [ChapterSearchResult.matchPositions] 为空、
  /// [ChapterSearchResult.titleMatched] 为 true。
  ///
  /// 内存护栏（防止搜常见字命中全书导致 OOM）：
  /// - 命中行数上限 200（SQL LIMIT），超量时 truncated=true
  /// - 每章最多记录 20 个匹配位置
  /// - content 只携带覆盖已记录匹配的窗口文本（前后各留 60 字符），
  ///   匹配位置重基到窗口坐标系；整章绝对偏移用
  ///   [ChapterSearchResult.contentOffsetBase] 还原
  Future<ChapterSearchResultSet> searchInCachedContent(
    String keyword, {
    String? novelUrl,
  });

}

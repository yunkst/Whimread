import '../models/search_result.dart';
import '../core/interfaces/repositories/i_chapter_repository.dart';
import 'logger_service.dart';

/// 章节搜索服务类
class ChapterSearchService {
  final IChapterRepository _chapterRepository;

  /// 构造函数 - 支持依赖注入
  /// 注意：必须通过Provider注入，不再支持直接实例化
  ChapterSearchService({required IChapterRepository chapterRepository})
      : _chapterRepository = chapterRepository;

  /// 在指定小说的缓存内容中搜索关键词（章节正文 + 章节标题）
  ///
  /// [novelUrl] 小说的URL，用于限制搜索范围
  /// [keyword] 搜索关键词
  ///
  /// 返回按章节索引排序的搜索结果；命中行数超过仓储上限时 truncated=true，
  /// 调用方需向用户提示结果不完整。
  Future<ChapterSearchResultSet> searchInNovel(
    String novelUrl,
    String keyword,
  ) async {
    if (keyword.trim().isEmpty) {
      return (results: const <ChapterSearchResult>[], truncated: false);
    }

    try {
      final page = await _chapterRepository.searchInCachedContent(
        keyword.trim(),
        novelUrl: novelUrl,
      );

      // 按章节索引排序
      final sortedResults = List<ChapterSearchResult>.from(page.results);
      sortedResults.sort((a, b) {
        return a.chapterIndex.compareTo(b.chapterIndex);
      });

      return (results: sortedResults, truncated: page.truncated);
    } catch (e, st) {
      LoggerService.instance.e(
        'searchInNovel 失败: novelUrl=$novelUrl keyword=$keyword - $e',
        stackTrace: st.toString(),
        category: LogCategory.database,
        tags: ['search', 'in_novel', 'failed'],
      );
      throw Exception('搜索失败: $e');
    }
  }
}

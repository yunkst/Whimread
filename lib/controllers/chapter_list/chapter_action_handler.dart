import '../../core/interfaces/repositories/i_chapter_repository.dart';
import '../../services/logger_service.dart';

/// 章节操作处理器（只读委托）
///
/// 仅保留 [isChapterCached] 只读方法。写操作（insertChapter / deleteChapter）
/// 已迁出，由 [ChapterMutationNotifier] 统一收口（写库 + bump signal 触发
/// 章节列表软刷新）。调用方应直接 `ref.read(chapterMutationProvider.notifier)`
/// 调对应方法，绕开本 controller。
class ChapterActionHandler {
  final IChapterRepository _chapterRepo;
  final _log = LoggerService.instance;

  ChapterActionHandler({
    required IChapterRepository chapterRepository,
  }) : _chapterRepo = chapterRepository;

  /// 检查章节是否已缓存
  Future<bool> isChapterCached(String chapterUrl) async {
    try {
      return await _chapterRepo.isChapterCached(chapterUrl);
    } catch (e, st) {
      _log.e(
        '检查章节缓存状态失败: $chapterUrl - $e',
        stackTrace: st.toString(),
        category: LogCategory.database,
        tags: ['chapter', 'cache'],
      );
      rethrow;
    }
  }
}

import '../../models/chapter.dart';
import '../../services/logger_service.dart';

/// 章节重排控制器（纯逻辑，无 DB 依赖）
///
/// 仅保留 [onReorder] 内存重排逻辑。持久化 [saveReorderedChapters] 已迁出，
/// 由 [ChapterMutationNotifier.updateChaptersOrder] 统一收口（写库 + bump signal）。
/// 调用方在 Notifier 层先 onReorder 得到重排列表，再调 updateChaptersOrder 持久化。
class ChapterReorderController {
  ChapterReorderController();

  /// 处理章节重排
  /// [oldIndex] 原始索引
  /// [newIndex] 新索引
  /// [chapters] 当前章节列表
  /// 返回重排后的章节列表
  List<Chapter> onReorder({
    required int oldIndex,
    required int newIndex,
    required List<Chapter> chapters,
  }) {
    int adjustedIndex = newIndex;
    if (oldIndex < newIndex) {
      adjustedIndex = newIndex - 1;
    }

    final Chapter item = chapters.removeAt(oldIndex);
    chapters.insert(adjustedIndex, item);

    LoggerService.instance.i(
      '章节重排: "${item.title}" 从 $oldIndex 移动到 $adjustedIndex',
      category: LogCategory.ui,
      tags: ['chapter-list', 'reorder'],
    );

    return chapters;
  }
}

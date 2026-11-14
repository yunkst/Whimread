/// 番外汇总视图模型
///
/// 番外列表页（章级/小说级）的单行数据：番外 Novel 行 + 从章节表聚合出的
/// 章数/已读数/字数 + 锚点章标题（孤儿锚点为 null，展示层回退「原章节已移除」）。
///
/// 聚合数据由 `SideStoryRepository.getSideStories` 的子查询一次性带出，
/// 避免 N+1 查询。
library;

import 'novel.dart';

class SideStorySummary {
  /// 番外的 bookshelf 行（isSideStory=1，url 为 custom://sidestory/ 时间戳）
  final Novel novel;

  /// 番外自身的章节数（novel_chapters 中该番外 novelUrl 下的行数）
  final int chapterCount;

  /// 已读章节数（readAt 非空的行数）
  final int readCount;

  /// 正文字数合计（chapter_cache.content 长度和；未缓存章节不计入）
  final int totalChars;

  /// 锚点章标题（LEFT JOIN novel_chapters；锚点章已被删除时为 null）
  final String? anchorChapterTitle;

  /// 锚点章在宿主小说中的序号（展示「第X章」用；锚点已删除时为 null）
  final int? anchorChapterIndex;

  const SideStorySummary({
    required this.novel,
    required this.chapterCount,
    required this.readCount,
    required this.totalChars,
    this.anchorChapterTitle,
    this.anchorChapterIndex,
  });

  /// 是否已开始阅读（继续阅读入口的文案依据）
  bool get hasProgress => readCount > 0;

  /// 阅读进度（0.0 ~ 1.0；无章节时为 0）
  double get progress =>
      chapterCount == 0 ? 0 : (readCount / chapterCount).clamp(0.0, 1.0);
}

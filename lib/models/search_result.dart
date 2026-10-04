/// 章节搜索结果
class ChapterSearchResult {
  final String novelUrl;
  final String novelTitle;
  final String novelAuthor;
  final String chapterUrl;
  final String chapterTitle;
  final int chapterIndex;
  final String content;
  final List<String> searchKeywords;
  final List<MatchPosition> matchPositions;
  final DateTime cachedAt;

  /// 关键词是否命中章节标题（标题单独命中时 [matchPositions] 可为空）
  final bool titleMatched;

  /// [content] 片段窗口起点在整章正文中的绝对字符偏移。
  /// [matchPositions] 是窗口内相对坐标，消费方需要整章坐标时用
  /// contentOffsetBase + position.start 还原。
  final int contentOffsetBase;

  const ChapterSearchResult({
    required this.novelUrl,
    required this.novelTitle,
    required this.novelAuthor,
    required this.chapterUrl,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.content,
    required this.searchKeywords,
    required this.matchPositions,
    required this.cachedAt,
    this.titleMatched = false,
    this.contentOffsetBase = 0,
  });

  /// 获取匹配数量
  int get matchCount => matchPositions.length;

  /// 获取第一个匹配位置
  MatchPosition? get firstMatch =>
      matchPositions.isNotEmpty ? matchPositions.first : null;

  /// 第一个匹配在整章正文中的绝对字符偏移（无正文匹配返回 null）
  int? get firstMatchAbsoluteOffset => matchPositions.isEmpty
      ? null
      : contentOffsetBase + matchPositions.first.start;

  /// 获取章节索引文本
  String get chapterIndexText => '第 ${chapterIndex + 1} 章';
}

/// 一次章节内容搜索的完整返回：结果列表 + 是否被行数上限截断。
///
/// 截断时 results 只含上限内的命中章节，UI/工具调用方应向用户提示结果不完整。
typedef ChapterSearchResultSet = ({
  List<ChapterSearchResult> results,
  bool truncated,
});

/// 匹配位置信息
class MatchPosition {
  final int start;
  final int end;
  final String matchedText;

  const MatchPosition({
    required this.start,
    required this.end,
    required this.matchedText,
  });
}

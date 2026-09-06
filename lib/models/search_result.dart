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
  });

  /// 获取匹配数量
  int get matchCount => matchPositions.length;

  /// 获取第一个匹配位置
  MatchPosition? get firstMatch =>
      matchPositions.isNotEmpty ? matchPositions.first : null;

  /// 获取章节索引文本
  String get chapterIndexText => '第 ${chapterIndex + 1} 章';
}

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

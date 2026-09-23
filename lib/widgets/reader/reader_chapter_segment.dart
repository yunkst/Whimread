/// 阅读器正文分段——无限滚动拼接的最小渲染单元。
///
/// 一段 = 一个已拼接进阅读视图的章节：
/// - [paragraphs] 为展示用段落（改写揭示的旧文本占位已由上层替换）
/// - 标注 / 待揭示均以「章内段落序号」为 key，随段落归属章节，
///   不受扁平化后的条目位移影响
class ReaderChapterSegment {
  final String chapterUrl;
  final List<String> paragraphs;

  /// 已有标注的章内段落序号集合（显示标注图标）
  final Set<int> annotatedIndexes;

  /// 待揭示段落（章内段落序号 → 改写后的新文本）
  final Map<int, String> pendingReveals;

  const ReaderChapterSegment({
    required this.chapterUrl,
    required this.paragraphs,
    this.annotatedIndexes = const {},
    this.pendingReveals = const {},
  });

  /// 按显示层一致规则拆分正文（按 '\n' 拆 + 过滤空行）
  static List<String> splitParagraphs(String content) =>
      content.split('\n').where((p) => p.trim().isNotEmpty).toList();
}

/// 分段 → 扁平条目的布局换算。
///
/// 条目序列 = Σ(章节起点标记 + 该章段落) + 尾部占位。
/// 章节起点标记为 0 高度条目，携带章节级 GlobalKey，供阅读页做
/// 「当前章检测」与「刷新/切章后重定位到章节起点」。
class ReaderFlatLayout {
  final List<ReaderChapterSegment> segments;

  const ReaderFlatLayout(this.segments);

  /// 扁平条目总数（含每章起点标记与末尾 1 项占位）
  int get itemCount =>
      segments.fold(0, (n, s) => n + 1 + s.paragraphs.length) + 1;

  /// 条目为章节起点标记时返回章节 URL，否则返回 null
  String? markerChapterUrlAt(int index) {
    var cursor = 0;
    for (final s in segments) {
      if (index == cursor) return s.chapterUrl;
      cursor += 1 + s.paragraphs.length;
    }
    return null;
  }

  /// 条目为段落时返回（章节 URL, 章内段落序号, 段落文本），否则 null
  (String, int, String)? paragraphAt(int index) {
    var cursor = 0;
    for (final s in segments) {
      final inSegmentIndex = index - cursor - 1; // 跳过章节起点标记
      if (inSegmentIndex >= 0 && inSegmentIndex < s.paragraphs.length) {
        return (s.chapterUrl, inSegmentIndex, s.paragraphs[inSegmentIndex]);
      }
      cursor += 1 + s.paragraphs.length;
    }
    return null;
  }
}

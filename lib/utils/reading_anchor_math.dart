import '../models/reading_anchor.dart';

/// 正文 ListView 已布局条目的采样快照。
///
/// [index] 为扁平条目序号（0 = 章节分隔线，之后为该章段落 0..n-1，
/// 依章递推，末位为尾部占位）；[contentOffset] 为条目顶在滚动内容
/// 坐标系里的偏移；[height] 为条目高。
class ReaderListItemSample {
  final int index;
  final double contentOffset;
  final double height;

  const ReaderListItemSample({
    required this.index,
    required this.contentOffset,
    required this.height,
  });

  double get bottom => contentOffset + height;
}

/// 章内阅读锚点的采样/换算纯函数（无渲染树依赖，可单测）。
///
/// 渲染树采样由阅读页完成（SliverList 子节点遍历），这里只做
/// 「样本 → 锚点」与「锚点 + 样本 → 跳转偏移」的换算。
class ReadingAnchorMath {
  ReadingAnchorMath._();

  /// 视口顶所在条目：首个 bottom 越过视口顶的样本（即「正在读」的条目）。
  ///
  /// 样本须按 index 升序；找不到（视口顶在所有样本之下，如尾部占位区）
  /// 返回 null。
  static ReaderListItemSample? topVisibleItem(
    List<ReaderListItemSample> items,
    double scrollOffset,
  ) {
    for (final item in items) {
      if (item.bottom > scrollOffset) return item;
    }
    return null;
  }

  /// 由视口顶条目样本换算章内锚点；非段落条目（分隔线）时
  /// 返回该章第 0 段、比例 0。
  ///
  /// [paragraphInfoAt] 将扁平条目序号换算为（章节 URL, 章内段落序号），
  /// 非段落条目返回 null；[chapterUrlOfFlat] 将扁平条目序号换算为所属
  /// 章节 URL（分隔线也属于其后章节）。
  static ReadingAnchor? anchorFromTopItem({
    required ReaderListItemSample topItem,
    required double scrollOffset,
    required (String, int)? Function(int flatIndex) paragraphInfoAt,
    required String? Function(int flatIndex) chapterUrlOfFlat,
  }) {
    final info = paragraphInfoAt(topItem.index);
    if (info != null) {
      final (chapterUrl, paragraphIndex) = info;
      final ratio = topItem.height <= 0
          ? 0.0
          : ((scrollOffset - topItem.contentOffset) / topItem.height)
              .clamp(0.0, 1.0)
              .toDouble();
      return ReadingAnchor(
        chapterUrl: chapterUrl,
        paragraphIndex: paragraphIndex,
        paragraphRatio: ratio,
      );
    }
    final url = chapterUrlOfFlat(topItem.index);
    if (url == null) return null;
    return ReadingAnchor(
      chapterUrl: url,
      paragraphIndex: 0,
      paragraphRatio: 0,
    );
  }

  /// 目标条目（[targetIndex]）的精确样本；未布局（ListView 缓存区外）返回 null。
  static ReaderListItemSample? locateItem(
    List<ReaderListItemSample> items,
    int targetIndex,
  ) {
    for (final item in items) {
      if (item.index == targetIndex) return item;
    }
    return null;
  }

  /// 将整章正文的字符偏移换算为章内锚点（搜索命中跳转用）。
  ///
  /// 段落拆分与显示层一致（ReaderChapterSegment.splitParagraphs：
  /// 按 '\n' 拆 + 过滤空行，段落文本取原始行）。[charOffset] 归入包含它的
  /// 首个非空行（行尾换行符位置归入该行）；落在空行区域时归入其后首个
  /// 非空段落；超出正文长度时 clamp 到末段。
  /// 全文无非空段落（无可定位目标）返回 null。
  static ReadingAnchor? anchorForCharOffset({
    required String chapterUrl,
    required String content,
    required int charOffset,
  }) {
    final lines = content.split('\n');
    var cursor = 0;
    var paragraphIndex = -1;
    String? lastLine;
    var lastParagraphIndex = -1;

    for (final line in lines) {
      final lineStart = cursor;
      cursor += line.length + 1; // +1 为换行符
      if (line.trim().isEmpty) continue;
      paragraphIndex++;
      lastLine = line;
      lastParagraphIndex = paragraphIndex;

      if (charOffset <= lineStart + line.length) {
        final ratio = line.isEmpty
            ? 0.0
            : ((charOffset - lineStart) / line.length)
                .clamp(0.0, 1.0)
                .toDouble();
        return ReadingAnchor(
          chapterUrl: chapterUrl,
          paragraphIndex: paragraphIndex,
          paragraphRatio: ratio,
        );
      }
    }

    if (lastLine == null) return null;
    return ReadingAnchor(
      chapterUrl: chapterUrl,
      paragraphIndex: lastParagraphIndex,
      paragraphRatio: 0,
    );
  }

  /// 锚点写入的变更门控：段落序号/章节变化必写；同段内比例漂移超过
  /// [ratioThreshold] 才写（降低高频滚动下的无效落库）。
  static bool anchorChangedSignificantly(
    ReadingAnchor? previous,
    ReadingAnchor next, {
    double ratioThreshold = 0.15,
  }) {
    if (previous == null) return true;
    if (previous.chapterUrl != next.chapterUrl) return true;
    if (previous.paragraphIndex != next.paragraphIndex) return true;
    return (previous.paragraphRatio - next.paragraphRatio).abs() >
        ratioThreshold;
  }
}

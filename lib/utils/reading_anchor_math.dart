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

  /// 估算「让 [targetIndex] 条目顶落在视口顶」的滚动偏移。
  ///
  /// 恢复跳转的第一跳目标条目通常未布局（用户上次读在章中间），只能用
  /// 已布局条目做线性外推：
  /// - 目标两侧各取最近样本，按条目间距算平均高，从下方样本外推；
  /// - 只有一侧样本时用该侧最近两样本的梯度，仅单个样本时退化用其自身高度。
  /// - [intraRatio] 按估出的平均条目高折算段内偏移。
  ///
  /// 无法估算（无样本）返回 null。结果可能超出 maxScrollExtent，由调用方 clamp。
  static double? estimateJumpOffset({
    required List<ReaderListItemSample> items,
    required int targetIndex,
    required double intraRatio,
  }) {
    if (items.isEmpty) return null;

    final sorted = [...items]..sort((a, b) => a.index.compareTo(b.index));
    final exact = locateItem(sorted, targetIndex);
    if (exact != null) {
      return exact.contentOffset + intraRatio * exact.height;
    }

    ReaderListItemSample? below;
    ReaderListItemSample? above;
    for (final item in sorted) {
      if (item.index < targetIndex) below = item;
      if (item.index > targetIndex && above == null) above = item;
    }
    final anchor = below ?? above;
    if (anchor == null) return null;

    double perIndex;
    if (below != null && above != null) {
      perIndex = (above.contentOffset - below.contentOffset) /
          (above.index - below.index);
    } else {
      final other = _nearestOther(sorted, anchor);
      perIndex = other == null
          ? (anchor.height > 0 ? anchor.height : 100.0)
          : (anchor.contentOffset - other.contentOffset).abs() /
              (anchor.index - other.index).abs();
    }
    if (!perIndex.isFinite || perIndex <= 0) perIndex = 100.0;

    return anchor.contentOffset +
        (targetIndex - anchor.index) * perIndex +
        intraRatio * perIndex;
  }

  /// 样本中与 [item] index 距离最近的另一个样本
  static ReaderListItemSample? _nearestOther(
    List<ReaderListItemSample> sorted,
    ReaderListItemSample item,
  ) {
    ReaderListItemSample? best;
    var bestDist = 1 << 62;
    for (final s in sorted) {
      if (identical(s, item)) continue;
      final d = (s.index - item.index).abs();
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    return best;
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

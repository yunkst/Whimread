import '../models/reading_anchor.dart';

/// 章节块形状快照（几何层登记用，与控制器块列表同序）
class BlockShape {
  final String chapterUrl;
  final int paragraphCount;
  const BlockShape(this.chapterUrl, this.paragraphCount);

  @override
  bool operator ==(Object other) =>
      other is BlockShape &&
      other.chapterUrl == chapterUrl &&
      other.paragraphCount == paragraphCount;

  @override
  int get hashCode => Object.hash(chapterUrl, paragraphCount);
}

/// 单章块的实测几何：分隔线高 + 逐段高（null = 尚未实测）。
class _GeometryBlock {
  final BlockShape shape;
  double? dividerHeight;
  final List<double?> paragraphHeights;

  _GeometryBlock(this.shape)
      : paragraphHeights = List<double?>.filled(shape.paragraphCount, null);

  double get _knownParagraphSum {
    var sum = 0.0;
    for (final h in paragraphHeights) {
      if (h != null) sum += h;
    }
    return sum;
  }

  int get _measuredCount =>
      paragraphHeights.where((h) => h != null).length;

  /// 已实测段落的平均高；一段都没测过返回 null。
  double? get averageParagraphHeight =>
      _measuredCount == 0 ? null : _knownParagraphSum / _measuredCount;

  /// 块内容整体是否已被实测（分隔线 + 全部段落）。
  bool get fullyMeasured =>
      dividerHeight != null &&
      paragraphHeights.every((h) => h != null);
}

/// 章内阅读位置的单一真理源：段落高度表 + 「锚点 ↔ 扁平条目 ↔ 内容偏移」
/// 的全部换算。
///
/// 正文是「每章 = 分隔线 + 段落 0..n-1」的固定结构（与显示层一致），几何层
/// 把这个结构的实测尺寸集中在这里维护，像素与语义位置的换算不再散落在
/// 控制器的采样回调、目标索引换算和外推估算三处：
/// - 写入侧：渲染树采样（扁平条目 → (章节, 段落, 高, 内容偏移)）喂进表里；
/// - 读取侧：恢复跳转直接按表累加算偏移，不再用「相邻两三个样本的梯度」
///   做线性外推（段落高度差异大时那套会差好几屏）。
///
/// 纯 Dart、无渲染树依赖——几何数据的真实性与接线（何时喂、何时失效）
/// 归控制器，这里只保证换算正确。全部可单测。
class ReadingGeometry {
  /// 未实测段的估算兜底高（像素）。只在整块零实测时参与，且仅影响
  /// 恢复第一跳的落点——第一跳后按实测校正，不进任何持久化状态。
  static const double fallbackParagraphHeight = 100.0;

  /// 分隔线未实测时的估算兜底高。
  static const double fallbackDividerHeight = 48.0;

  final List<_GeometryBlock> _blocks = [];

  /// 当前块形状（供扁平索引换算用）
  List<BlockShape> get shapes =>
      List.unmodifiable(_blocks.map((b) => b.shape));

  // ----- 形状同步与失效 -----

  /// 与控制器的块列表同步形状：
  /// - 同 URL 且段数不变的块保留实测值；
  /// - 段数变化（内容重取/改写）或新出现的块重置为未测；
  /// - 消失的块（窗口回收/导航重置）连同实测值一起移除。
  void syncBlocks(List<BlockShape> shapes) {
    final next = <_GeometryBlock>[];
    for (final shape in shapes) {
      final existing = _blocks.where((b) => b.shape == shape).toList();
      next.add(existing.isNotEmpty ? existing.first : _GeometryBlock(shape));
    }
    _blocks
      ..clear()
      ..addAll(next);
  }

  /// 单章实测失效（内容重取/改写后段数不变的块）。
  void invalidateChapter(String chapterUrl) {
    final b = _find(chapterUrl);
    if (b == null) return;
    b.dividerHeight = null;
    for (var i = 0; i < b.paragraphHeights.length; i++) {
      b.paragraphHeights[i] = null;
    }
  }

  /// 字体变化 → 全部实测高失效（排版参数变了，旧高度不可信）。
  void invalidateAll() {
    for (final b in _blocks) {
      b.dividerHeight = null;
      for (var i = 0; i < b.paragraphHeights.length; i++) {
        b.paragraphHeights[i] = null;
      }
    }
  }

  // ----- 采样写入 -----

  void recordDivider(String chapterUrl, double height) {
    _find(chapterUrl)?.dividerHeight = height;
  }

  void recordParagraph(String chapterUrl, int paragraphIndex, double height) {
    final block = _find(chapterUrl);
    if (block == null ||
        paragraphIndex < 0 ||
        paragraphIndex >= block.paragraphHeights.length) {
      return;
    }
    block.paragraphHeights[paragraphIndex] = height;
  }

  _GeometryBlock? _find(String chapterUrl) {
    for (final b in _blocks) {
      if (b.shape.chapterUrl == chapterUrl) return b;
    }
    return null;
  }

  // ----- 扁平条目 ↔ (章节, 段落) -----

  /// 扁平条目序号 → (章节 URL, 章内段落序号)；
  /// 分隔线/尾部占位返回 null（与显示层条目序列一致：每章 = 分隔线 + 段落）。
  ({String url, int paragraphIndex})? paragraphInfoAtFlatIndex(int flatIndex) {
    var cursor = 0;
    for (final b in _blocks) {
      final inSegment = flatIndex - cursor - 1; // 跳过分隔线
      if (inSegment >= 0 && inSegment < b.shape.paragraphCount) {
        return (url: b.shape.chapterUrl, paragraphIndex: inSegment);
      }
      cursor += 1 + b.shape.paragraphCount;
    }
    return null;
  }

  /// 扁平条目序号 → 所属章节 URL（分隔线归属其后章节；尾部占位返回 null）
  String? chapterUrlAtFlatIndex(int flatIndex) {
    var cursor = 0;
    for (final b in _blocks) {
      if (flatIndex <= cursor + b.shape.paragraphCount) {
        return b.shape.chapterUrl;
      }
      cursor += 1 + b.shape.paragraphCount;
    }
    return null;
  }

  /// 扁平条目序号是否恰好是某章的分隔线条目；是则返回该章 URL。
  String? dividerUrlAtFlatIndex(int flatIndex) {
    var cursor = 0;
    for (final b in _blocks) {
      if (flatIndex == cursor) return b.shape.chapterUrl;
      cursor += 1 + b.shape.paragraphCount;
    }
    return null;
  }

  /// 锚点 → 目标条目的扁平索引（段落越界 clamp 到末段；章不在块列表返回 null）
  int? flatIndexOfAnchor(ReadingAnchor anchor) {
    var cursor = 0;
    for (final b in _blocks) {
      if (b.shape.chapterUrl == anchor.chapterUrl) {
        if (b.shape.paragraphCount == 0) return cursor;
        final paraIdx = anchor.paragraphIndex
            .clamp(0, b.shape.paragraphCount - 1)
            .toInt();
        return cursor + 1 + paraIdx;
      }
      cursor += 1 + b.shape.paragraphCount;
    }
    return null;
  }

  // ----- 锚点 → 内容偏移（表驱动估算） -----

  /// 按表累加计算「锚点位置」的全局内容偏移。
  ///
  /// 偏移 = 顶部 padding + Σ前序块高 + 锚点章内：
  /// 分隔线 + Σ前序段高 + 比例 × 目标段高。
  /// 未实测的段用块内已测均高兜底（整块未测用 [fallbackParagraphHeight]）；
  /// 这只影响恢复第一跳的落点，第一跳后由实测校正。
  ///
  /// 锚点章不在块列表返回 null。
  double? estimateOffsetOf(
    ReadingAnchor anchor, {
    required double topPadding,
  }) {
    var cursor = topPadding;
    for (final b in _blocks) {
      final isTarget = b.shape.chapterUrl == anchor.chapterUrl;
      final divider = b.dividerHeight ?? fallbackDividerHeight;
      final avg = b.averageParagraphHeight;
      if (isTarget) {
        if (b.shape.paragraphCount == 0) return cursor;
        final paraIdx = anchor.paragraphIndex
            .clamp(0, b.shape.paragraphCount - 1)
            .toInt();
        var sum = divider;
        for (var i = 0; i < paraIdx; i++) {
          sum += b.paragraphHeights[i] ?? avg ?? fallbackParagraphHeight;
        }
        final targetHeight =
            b.paragraphHeights[paraIdx] ?? avg ?? fallbackParagraphHeight;
        return cursor + sum + anchor.paragraphRatio * targetHeight;
      }
      // 非目标块：整块高（未测段按均高/兜底补齐）
      var sum = divider;
      for (var i = 0; i < b.shape.paragraphCount; i++) {
        sum += b.paragraphHeights[i] ?? avg ?? fallbackParagraphHeight;
      }
      cursor += sum;
    }
    return null;
  }

  /// 目标章是否已全量实测（分隔线 + 全部段落）。调试与测试用。
  bool isChapterFullyMeasured(String chapterUrl) =>
      _find(chapterUrl)?.fullyMeasured ?? false;
}

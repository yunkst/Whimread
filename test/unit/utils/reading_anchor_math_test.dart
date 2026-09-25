/// ReadingAnchorMath 测试：视口顶条目选取、锚点换算、跳转偏移估算、写入门控
///
/// 场景模型与正文 ListView 一致：每章条目 = 分隔线(1) + 段落(n)，
/// 扁平序号 0 = 第一章分隔线，末位为尾部占位。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/reading_anchor.dart';
import 'package:novel_app/utils/reading_anchor_math.dart';

/// 构造「均匀高度条目」的采样序列：itemHeight 为段落高，dividerHeight 为
/// 分隔线高，topPadding 为首条目内容偏移（ListView 顶部 padding）。
List<ReaderListItemSample> uniformSamples({
  required List<int> paragraphCounts,
  required double itemHeight,
  double dividerHeight = 40,
  double topPadding = 16,
}) {
  final samples = <ReaderListItemSample>[];
  var offset = topPadding;
  var flatIndex = 0;
  for (final count in paragraphCounts) {
    samples.add(ReaderListItemSample(
      index: flatIndex++,
      contentOffset: offset,
      height: dividerHeight,
    ));
    offset += dividerHeight;
    for (var i = 0; i < count; i++) {
      samples.add(ReaderListItemSample(
        index: flatIndex++,
        contentOffset: offset,
        height: itemHeight,
      ));
      offset += itemHeight;
    }
  }
  return samples;
}

void main() {
  group('topVisibleItem（保存：视口顶条目选取）', () {
    final items = uniformSamples(paragraphCounts: [5], itemHeight: 100);

    test('视口顶落在第 2 段中部 → 选中第 2 段', () {
      // 布局：16(topPad) + 40(divider) = 56 起为段落；段1: 56-156, 段2: 156-256
      final top = ReadingAnchorMath.topVisibleItem(items, 200);
      expect(top?.index, 2);
    });

    test('视口顶恰在段落边界 → 选中下一段（bottom > offset 严格判定）', () {
      final top = ReadingAnchorMath.topVisibleItem(items, 156);
      expect(top?.index, 2);
    });

    test('视口顶在分隔线上 → 选中分隔线', () {
      final top = ReadingAnchorMath.topVisibleItem(items, 30);
      expect(top?.index, 0);
    });

    test('视口顶在所有样本之下（尾部占位区）→ null', () {
      final top = ReadingAnchorMath.topVisibleItem(items, 99999);
      expect(top, isNull);
    });
  });

  group('anchorFromTopItem（保存：样本 → 锚点）', () {
    test('段落条目 → 章内段落序号 + 段内比例', () {
      final items = uniformSamples(paragraphCounts: [5], itemHeight: 100);
      const scrollOffset = 206.0; // 第2段(156-256)内，越过 50%
      final top = ReadingAnchorMath.topVisibleItem(items, scrollOffset)!;
      final anchor = ReadingAnchorMath.anchorFromTopItem(
        topItem: top,
        scrollOffset: scrollOffset,
        paragraphInfoAt: (i) => i == 0 ? null : ('u1', i - 1),
        chapterUrlOfFlat: (i) => i <= 5 ? 'u1' : null,
      );
      expect(anchor?.chapterUrl, 'u1');
      expect(anchor?.paragraphIndex, 1);
      expect(anchor?.paragraphRatio, closeTo(0.5, 0.001));
    });

    test('分隔线条目 → 该章第 0 段、比例 0', () {
      final items = uniformSamples(paragraphCounts: [3], itemHeight: 100);
      final top = ReadingAnchorMath.topVisibleItem(items, 20)!;
      final anchor = ReadingAnchorMath.anchorFromTopItem(
        topItem: top,
        scrollOffset: 20,
        paragraphInfoAt: (i) => i == 0 ? null : ('u1', i - 1),
        chapterUrlOfFlat: (i) => i <= 3 ? 'u1' : null,
      );
      expect(anchor?.paragraphIndex, 0);
      expect(anchor?.paragraphRatio, 0);
    });

    test('尾部占位（无所属章节）→ null（不保存）', () {
      final items = uniformSamples(paragraphCounts: [3], itemHeight: 100);
      const placeholder = ReaderListItemSample(
        index: 4,
        contentOffset: 456,
        height: 160,
      );
      final anchor = ReadingAnchorMath.anchorFromTopItem(
        topItem: placeholder,
        scrollOffset: 500,
        paragraphInfoAt: (i) => i < 4 ? (i == 0 ? null : ('u1', i - 1)) : null,
        chapterUrlOfFlat: (i) => i < 4 ? 'u1' : null,
      );
      expect(anchor, isNull);
    });

    test('比例越界被 clamp（防御路径：样本间存在间隙时可达）', () {
      // 连续布局下 topVisibleItem 选中的段落比例必在 [0,1]；
      // 仅当采样条目间存在间隙（如滚动补偿瞬间）才会越界，直接构造验证。
      const item = ReaderListItemSample(
          index: 1, contentOffset: 200, height: 100);
      final below = ReadingAnchorMath.anchorFromTopItem(
        topItem: item,
        scrollOffset: 100, // 低于条目顶 200
        paragraphInfoAt: (i) => ('u1', i - 1),
        chapterUrlOfFlat: (i) => 'u1',
      );
      expect(below?.paragraphRatio, 0.0);

      final above = ReadingAnchorMath.anchorFromTopItem(
        topItem: item,
        scrollOffset: 500, // 越过条目底 300
        paragraphInfoAt: (i) => ('u1', i - 1),
        chapterUrlOfFlat: (i) => 'u1',
      );
      expect(above?.paragraphRatio, 1.0);
    });
  });

  group('estimateJumpOffset（恢复：跳转偏移估算）', () {
    test('目标已布局 → 精确偏移 + 段内比例折算', () {
      final items = uniformSamples(paragraphCounts: [5], itemHeight: 100);
      final offset = ReadingAnchorMath.estimateJumpOffset(
        items: items,
        targetIndex: 3,
        intraRatio: 0.5,
      );
      // 段3 顶 = 16 + 40 + 2*100 = 256
      expect(offset, closeTo(256 + 50, 0.001));
    });

    test('目标未布局、仅下方有样本 → 用邻近梯度线性外推', () {
      // 只采样到前 3 条目（分隔线 + 段0 + 段1），目标为段 10
      final items = uniformSamples(paragraphCounts: [5], itemHeight: 100)
          .where((s) => s.index <= 2)
          .toList();
      final offset = ReadingAnchorMath.estimateJumpOffset(
        items: items,
        targetIndex: 12,
        intraRatio: 0,
      );
      // 下方样本段1 顶 = 156，邻近梯度 100px/序号 → 156 + (12-2)*100 = 1156
      expect(offset, closeTo(1156, 0.001));
    });

    test('目标在样本之上（往下恢复）→ 反向外推出合法偏移', () {
      final items = uniformSamples(paragraphCounts: [5], itemHeight: 100)
          .where((s) => s.index >= 3)
          .toList();
      final offset = ReadingAnchorMath.estimateJumpOffset(
        items: items,
        targetIndex: 1,
        intraRatio: 0,
      );
      // 上方样本段2 顶 = 256，梯度 100 → 256 + (1-3)*100 = 56
      expect(offset, closeTo(56, 0.001));
    });

    test('单一 takeSample 退化：用自身高度做梯度', () {
      const items = [
        ReaderListItemSample(index: 0, contentOffset: 16, height: 40),
      ];
      final offset = ReadingAnchorMath.estimateJumpOffset(
        items: items,
        targetIndex: 20,
        intraRatio: 0,
      );
      expect(offset, closeTo(16 + 20 * 40, 0.001));
    });

    test('空样本 → null', () {
      expect(
        ReadingAnchorMath.estimateJumpOffset(
            items: const [], targetIndex: 1, intraRatio: 0),
        isNull,
      );
    });
  });

  group('locateItem', () {
    test('命中返回样本，未命中返回 null', () {
      final items = uniformSamples(paragraphCounts: [3], itemHeight: 100);
      expect(ReadingAnchorMath.locateItem(items, 2)?.index, 2);
      expect(ReadingAnchorMath.locateItem(items, 99), isNull);
    });
  });

  group('anchorChangedSignificantly（写入门控）', () {
    const base = ReadingAnchor(
      chapterUrl: 'u',
      paragraphIndex: 5,
      paragraphRatio: 0.4,
    );

    test('首写必保存', () {
      expect(ReadingAnchorMath.anchorChangedSignificantly(null, base), isTrue);
    });

    test('章节/段落变化必保存', () {
      expect(
        ReadingAnchorMath.anchorChangedSignificantly(
          base,
          const ReadingAnchor(
              chapterUrl: 'u', paragraphIndex: 6, paragraphRatio: 0.4),
        ),
        isTrue,
      );
      expect(
        ReadingAnchorMath.anchorChangedSignificantly(
          base,
          const ReadingAnchor(
              chapterUrl: 'v', paragraphIndex: 5, paragraphRatio: 0.4),
        ),
        isTrue,
      );
    });

    test('同段小幅比例漂移跳过，超过阈值保存', () {
      expect(
        ReadingAnchorMath.anchorChangedSignificantly(
          base,
          const ReadingAnchor(
              chapterUrl: 'u', paragraphIndex: 5, paragraphRatio: 0.45),
        ),
        isFalse,
        reason: '0.05 < 0.15 阈值',
      );
      expect(
        ReadingAnchorMath.anchorChangedSignificantly(
          base,
          const ReadingAnchor(
              chapterUrl: 'u', paragraphIndex: 5, paragraphRatio: 0.8),
        ),
        isTrue,
      );
    });
  });
}

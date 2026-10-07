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

  group('anchorForCharOffset（搜索命中：字符偏移 → 段落锚点）', () {
    // 正文：段落 0 = '第一段落'（前有 2 个空行），段落 1 = '第二段落'，
    // 段落 2 = '第三段落'。各非空行起始偏移：p0=2、p1=8、p2=13。
    const content = '\n\n第一段落\n\n第二段落\n第三段落';
    const p0Start = 2, p1Start = 8;

    test('命中段落 0 首字符 → 段落 0、比例 0', () {
      final anchor = ReadingAnchorMath.anchorForCharOffset(
        chapterUrl: 'u',
        content: content,
        charOffset: p0Start,
      );
      expect(anchor, isNotNull);
      expect(anchor!.paragraphIndex, 0);
      expect(anchor.paragraphRatio, 0);
    });

    test('命中段落中段 → 段内比例按字符占比', () {
      final anchor = ReadingAnchorMath.anchorForCharOffset(
        chapterUrl: 'u',
        content: content,
        charOffset: p1Start + 2,
      );
      expect(anchor!.paragraphIndex, 1);
      expect(anchor.paragraphRatio, closeTo(0.5, 1e-9));
    });

    test('偏移落在空行 → 归入其后首个非空段落', () {
      // p0 结束于偏移 6（含行尾换行符）；偏移 7 是空行区域，归入段落 1
      final anchor = ReadingAnchorMath.anchorForCharOffset(
        chapterUrl: 'u',
        content: content,
        charOffset: 7,
      );
      expect(anchor!.paragraphIndex, 1);
    });

    test('偏移超出正文末尾 → clamp 到末段、比例 0', () {
      final anchor = ReadingAnchorMath.anchorForCharOffset(
        chapterUrl: 'u',
        content: content,
        charOffset: 999,
      );
      expect(anchor!.paragraphIndex, 2);
      expect(anchor.paragraphRatio, 0);
    });

    test('空行分段规则与显示层一致（按 \\n 拆 + 过滤空白行）', () {
      // 全空白行也无 \n 之外内容 → 无可定位段落
      expect(
        ReadingAnchorMath.anchorForCharOffset(
          chapterUrl: 'u',
          content: '\n  \n\n',
          charOffset: 0,
        ),
        isNull,
      );
      // 行首尾空格保留：段落文本取原始行（与 splitParagraphs 一致，
      // 过滤判定用 trim，但段落内容不 trim）
      final anchor = ReadingAnchorMath.anchorForCharOffset(
        chapterUrl: 'u',
        content: ' 第一段 ',
        charOffset: 0,
      );
      expect(anchor!.paragraphIndex, 0);
      expect(anchor.paragraphRatio, 0);
    });
  });
}

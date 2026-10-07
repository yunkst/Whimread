import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/reading_anchor.dart';
import 'package:novel_app/utils/reading_geometry.dart';

/// 几何层单测：段落高表 + 扁平索引映射 + 表驱动偏移换算。
///
/// 换算是位置恢复与章检测共用的真理源——控制器只负责喂数据与接线，
/// 正确性全部锁在这里（此前这套逻辑零覆盖）。
void main() {
  ReadingAnchor anchorOf(String url, int para, double ratio) =>
      ReadingAnchor(
        chapterUrl: url,
        paragraphIndex: para,
        paragraphRatio: ratio,
      );

  group('syncBlocks 形状同步', () {
    test('同 URL 同段数 → 保留实测值', () {
      final g = ReadingGeometry();
      g.syncBlocks([const BlockShape('a', 3)]);
      g.recordParagraph('a', 0, 50);
      g.recordDivider('a', 40);

      g.syncBlocks([const BlockShape('a', 3)]);
      expect(g.isChapterFullyMeasured('a'), isFalse); // 还有段没测
      g.recordParagraph('a', 1, 60);
      g.recordParagraph('a', 2, 70);
      expect(g.isChapterFullyMeasured('a'), isTrue);
    });

    test('段数变化 → 该块实测全部失效', () {
      final g = ReadingGeometry();
      g.syncBlocks([const BlockShape('a', 2)]);
      g.recordDivider('a', 40);
      g.recordParagraph('a', 0, 50);
      g.recordParagraph('a', 1, 60);
      expect(g.isChapterFullyMeasured('a'), isTrue);

      g.syncBlocks([const BlockShape('a', 5)]); // 内容重取，段数变了
      expect(g.isChapterFullyMeasured('a'), isFalse);
    });

    test('新块加入 / 旧块消失', () {
      final g = ReadingGeometry();
      g.syncBlocks([const BlockShape('a', 2)]);
      g.recordDivider('a', 40);
      g.recordParagraph('a', 0, 50);
      g.recordParagraph('a', 1, 60);

      g.syncBlocks([const BlockShape('a', 2), const BlockShape('b', 1)]);
      expect(g.chapterUrlAtFlatIndex(0), 'a');
      expect(g.chapterUrlAtFlatIndex(3), 'b');

      g.syncBlocks([const BlockShape('b', 1)]); // a 被回收
      expect(g.chapterUrlAtFlatIndex(0), 'b');
      // a 的实测值随块一起消失
      expect(g.shapes.map((s) => s.chapterUrl), ['b']);
    });

    test('invalidateAll 清空全部实测（字号变化）', () {
      final g = ReadingGeometry();
      g.syncBlocks([const BlockShape('a', 1)]);
      g.recordDivider('a', 40);
      g.recordParagraph('a', 0, 50);
      expect(g.isChapterFullyMeasured('a'), isTrue);

      g.invalidateAll();
      expect(g.isChapterFullyMeasured('a'), isFalse);
    });
  });

  group('扁平索引 ↔ 段落映射（与显示层条目序列一致）', () {
    // 块结构：a = [分隔线0, 段0=1, 段1=2]；b = [分隔线3, 段0=4]
    final shapes = [const BlockShape('a', 2), const BlockShape('b', 1)];

    test('paragraphInfoAtFlatIndex：分隔线与尾部占位返回 null', () {
      final g = ReadingGeometry()..syncBlocks(shapes);
      expect(g.paragraphInfoAtFlatIndex(0), isNull); // a 的分隔线
      expect(g.paragraphInfoAtFlatIndex(1), (url: 'a', paragraphIndex: 0));
      expect(g.paragraphInfoAtFlatIndex(2), (url: 'a', paragraphIndex: 1));
      expect(g.paragraphInfoAtFlatIndex(3), isNull); // b 的分隔线
      expect(g.paragraphInfoAtFlatIndex(4), (url: 'b', paragraphIndex: 0));
      expect(g.paragraphInfoAtFlatIndex(5), isNull); // 尾部占位
    });

    test('chapterUrlAtFlatIndex：分隔线归其后章节，尾部占位 null', () {
      final g = ReadingGeometry()..syncBlocks(shapes);
      expect(g.chapterUrlAtFlatIndex(0), 'a');
      expect(g.chapterUrlAtFlatIndex(3), 'b');
      expect(g.chapterUrlAtFlatIndex(5), isNull);
    });

    test('flatIndexOfAnchor：段落越界 clamp 到末段', () {
      final g = ReadingGeometry()..syncBlocks(shapes);
      expect(g.flatIndexOfAnchor(anchorOf('a', 0, 0)), 1);
      expect(g.flatIndexOfAnchor(anchorOf('a', 1, 0.5)), 2);
      expect(g.flatIndexOfAnchor(anchorOf('a', 99, 0)), 2); // 越界 → 末段
      expect(g.flatIndexOfAnchor(anchorOf('b', 0, 0)), 4);
      expect(g.flatIndexOfAnchor(anchorOf('nope', 0, 0)), isNull);
    });
  });

  group('estimateOffsetOf：表驱动偏移换算', () {
    test('全量实测时偏移精确可验（padding + 分隔线 + 段前缀和 + 比例×段高）',
        () {
      final g = ReadingGeometry()..syncBlocks([const BlockShape('a', 3)]);
      g.recordDivider('a', 40);
      g.recordParagraph('a', 0, 100);
      g.recordParagraph('a', 1, 200);
      g.recordParagraph('a', 2, 300);

      // 段0 顶部 = 16(padding) + 40(分隔线) = 56
      expect(g.estimateOffsetOf(anchorOf('a', 0, 0), topPadding: 16), 56);
      // 段1 顶部 = 56 + 100 = 156；比例 0.5 落在段1 中部 = 156 + 100
      expect(g.estimateOffsetOf(anchorOf('a', 1, 0.5), topPadding: 16), 256);
      // 段2 顶部 = 56 + 100 + 200 = 356；比例 1.0 = 段2 底
      expect(g.estimateOffsetOf(anchorOf('a', 2, 1.0), topPadding: 16), 656);
    });

    test('多块：前序块高按实测累加', () {
      final g = ReadingGeometry()
        ..syncBlocks([const BlockShape('a', 1), const BlockShape('b', 1)]);
      // a：分隔线 10 + 段 100 → 块高 110
      g.recordDivider('a', 10);
      g.recordParagraph('a', 0, 100);
      // b：分隔线 20 + 段 200
      g.recordDivider('b', 20);
      g.recordParagraph('b', 0, 200);

      // b 段0 顶部 = 16 + 110 + 20 = 146
      expect(g.estimateOffsetOf(anchorOf('b', 0, 0), topPadding: 16), 146);
      // b 段0 比例 0.25 = 146 + 50
      expect(g.estimateOffsetOf(anchorOf('b', 0, 0.25), topPadding: 16), 196);
    });

    test('未实测段用块内已测均高兜底（不是零）', () {
      final g = ReadingGeometry()..syncBlocks([const BlockShape('a', 3)]);
      g.recordDivider('a', 40);
      g.recordParagraph('a', 0, 100); // 已测均高 = 100
      // 段1、段2 未测 → 按均高 100 累加
      expect(g.estimateOffsetOf(anchorOf('a', 2, 0), topPadding: 16), 56 + 200);
    });

    test('整块零实测 → 兜底高参与第一跳估算（不返回 null）', () {
      final g = ReadingGeometry()..syncBlocks([const BlockShape('a', 2)]);
      final offset = g.estimateOffsetOf(anchorOf('a', 1, 0), topPadding: 16);
      expect(offset, isNotNull);
      // 16 + 48(fallback 分隔线) + 100(fallback 段) = 164
      expect(offset, 16 + 48 + 100);
    });

    test('锚点章不在块列表 → null', () {
      final g = ReadingGeometry()..syncBlocks([const BlockShape('a', 1)]);
      expect(g.estimateOffsetOf(anchorOf('nope', 0, 0), topPadding: 16), isNull);
    });

    test('空章节块：锚点落在分隔线', () {
      final g = ReadingGeometry()..syncBlocks([const BlockShape('a', 0)]);
      expect(g.estimateOffsetOf(anchorOf('a', 0, 0), topPadding: 16), 16);
    });
  });
}

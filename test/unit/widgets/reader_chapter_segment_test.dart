import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/reader/reader_chapter_segment.dart';

void main() {
  group('ReaderChapterSegment.splitParagraphs', () {
    test('按 \\n 拆分并过滤空行，与显示层规则一致', () {
      final paragraphs = ReaderChapterSegment.splitParagraphs(
        '第一段\n\n第二段\n   \n第三段',
      );
      expect(paragraphs, ['第一段', '第二段', '第三段']);
    });

    test('空内容返回空列表', () {
      expect(ReaderChapterSegment.splitParagraphs(''), isEmpty);
      expect(ReaderChapterSegment.splitParagraphs('\n\n  \n'), isEmpty);
    });
  });

  group('ReaderFlatLayout', () {
    ReaderChapterSegment segment(String url, List<String> paragraphs) =>
        ReaderChapterSegment(chapterUrl: url, paragraphs: paragraphs);

    test('空分段：只有尾部占位一项', () {
      final layout = ReaderFlatLayout([]);
      expect(layout.itemCount, 1);
      expect(layout.markerChapterUrlAt(0), isNull);
      expect(layout.paragraphAt(0), isNull);
    });

    test('单分段：起点标记 + 段落 + 尾部占位', () {
      final layout = ReaderFlatLayout([
        segment('ch1', ['p1', 'p2', 'p3']),
      ]);

      expect(layout.itemCount, 1 + 3 + 1);

      expect(layout.markerChapterUrlAt(0), 'ch1');
      expect(layout.markerChapterUrlAt(1), isNull);
      expect(layout.markerChapterUrlAt(4), isNull);
      expect(layout.markerChapterUrlAt(99), isNull);

      expect(layout.paragraphAt(0), isNull); // 起点标记
      expect(layout.paragraphAt(1), ('ch1', 0, 'p1'));
      expect(layout.paragraphAt(2), ('ch1', 1, 'p2'));
      expect(layout.paragraphAt(3), ('ch1', 2, 'p3'));
      expect(layout.paragraphAt(4), isNull); // 尾部占位
      expect(layout.paragraphAt(5), isNull); // 越界
    });

    test('多分段：每章起点前插一个标记条目', () {
      final layout = ReaderFlatLayout([
        segment('ch1', ['a1', 'a2']),
        segment('ch2', ['b1']),
      ]);

      // ch1: 标记(0) + 2 段；ch2: 标记(3) + 1 段；尾部占位(5)
      expect(layout.itemCount, 6);
      expect(layout.markerChapterUrlAt(0), 'ch1');
      expect(layout.paragraphAt(1), ('ch1', 0, 'a1'));
      expect(layout.paragraphAt(2), ('ch1', 1, 'a2'));
      expect(layout.markerChapterUrlAt(3), 'ch2');
      expect(layout.paragraphAt(4), ('ch2', 0, 'b1'));
      expect(layout.markerChapterUrlAt(5), isNull);
    });

    test('顶部拼接上一章后：既有段落条目整体后移，映射关系不变', () {
      final before = ReaderFlatLayout([
        segment('ch12', ['x1', 'x2']),
      ]);
      expect(before.paragraphAt(1), ('ch12', 0, 'x1'));

      // 拼接 ch11（1 段）到顶部 → ch12 的所有条目后移 2（标记 + 1 段）
      final after = ReaderFlatLayout([
        segment('ch11', ['w1']),
        segment('ch12', ['x1', 'x2']),
      ]);
      expect(after.itemCount, before.itemCount + 2);
      expect(after.markerChapterUrlAt(0), 'ch11');
      expect(after.paragraphAt(1), ('ch11', 0, 'w1'));
      expect(after.paragraphAt(3), ('ch12', 0, 'x1'));
      expect(after.paragraphAt(4), ('ch12', 1, 'x2'));
    });

    test('底部拼接下一章后：既有条目位置不变，新章追加在后', () {
      final before = ReaderFlatLayout([
        segment('ch1', ['a1']),
      ]);
      final after = ReaderFlatLayout([
        segment('ch1', ['a1']),
        segment('ch2', ['b1', 'b2']),
      ]);

      expect(after.itemCount, before.itemCount + 3);
      expect(after.paragraphAt(1), ('ch1', 0, 'a1')); // 原位置不动
      expect(after.markerChapterUrlAt(2), 'ch2');
      expect(after.paragraphAt(3), ('ch2', 0, 'b1'));
      expect(after.paragraphAt(4), ('ch2', 1, 'b2'));
    });
  });
}

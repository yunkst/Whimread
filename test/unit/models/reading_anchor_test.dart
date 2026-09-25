/// ReadingAnchor 序列化测试：encode/decode 往返 + 损坏数据宽容降级
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/reading_anchor.dart';

void main() {
  group('encode/decode 往返', () {
    test('常规 URL 与比例往返一致', () {
      const anchor = ReadingAnchor(
        chapterUrl: 'https://www.example.com/book/123/456789.html',
        paragraphIndex: 42,
        paragraphRatio: 0.35,
      );
      final decoded = ReadingAnchor.decode(anchor.encode());
      expect(decoded, anchor);
    });

    test('中文 URL 与特殊字符往返一致', () {
      const anchor = ReadingAnchor(
        chapterUrl: 'https://示例. com/书/第十二章?query=参数&x=1',
        paragraphIndex: 0,
        paragraphRatio: 0.0,
      );
      final decoded = ReadingAnchor.decode(anchor.encode());
      expect(decoded?.chapterUrl, anchor.chapterUrl);
      expect(decoded?.paragraphIndex, 0);
    });

    test('含引号与反斜杠的 URL 往返一致', () {
      const anchor = ReadingAnchor(
        chapterUrl: r'https://example.com/a"b\c',
        paragraphIndex: 7,
        paragraphRatio: 1.0,
      );
      final decoded = ReadingAnchor.decode(anchor.encode());
      expect(decoded, anchor);
    });

    test('比例越界被 clamp 到 [0, 1]', () {
      const anchor = ReadingAnchor(
        chapterUrl: 'u',
        paragraphIndex: 1,
        paragraphRatio: 1.5,
      );
      expect(ReadingAnchor.decode(anchor.encode())?.paragraphRatio, 1.0);

      const anchor2 = ReadingAnchor(
        chapterUrl: 'u',
        paragraphIndex: 1,
        paragraphRatio: -0.2,
      );
      expect(ReadingAnchor.decode(anchor2.encode())?.paragraphRatio, 0.0);
    });

    test('ratio 舍入到 3 位小数（降低高频写入抖动）', () {
      const anchor = ReadingAnchor(
        chapterUrl: 'u',
        paragraphIndex: 1,
        paragraphRatio: 0.123456,
      );
      final decoded = ReadingAnchor.decode(anchor.encode());
      expect(decoded?.paragraphRatio, closeTo(0.123, 0.0001));
    });
  });

  group('decode 宽容降级', () {
    test('null / 空串 / 垃圾字符串返回 null', () {
      expect(ReadingAnchor.decode(null), isNull);
      expect(ReadingAnchor.decode(''), isNull);
      expect(ReadingAnchor.decode('not-json{{{'), isNull);
      expect(ReadingAnchor.decode('[]'), isNull);
    });

    test('字段缺失或非法返回 null', () {
      expect(ReadingAnchor.decode('{"p":1,"r":0.5}'), isNull, // 缺 u
          reason: '缺章节 URL 不恢复');
      expect(ReadingAnchor.decode('{"u":"","p":1,"r":0.5}'), isNull,
          reason: '空 URL 不恢复');
      expect(ReadingAnchor.decode('{"u":"a","r":0.5}'), isNull, // 缺 p
          reason: '缺段落序号不恢复');
      expect(ReadingAnchor.decode('{"u":"a","p":-3,"r":0.5}'), isNull,
          reason: '负段落序号不恢复');
      expect(ReadingAnchor.decode('{"u":"a","p":1}'), isNull, // 缺 r
          reason: '缺比例不恢复');
    });

    test('旧格式/半损坏数据返回 null 而非抛异常', () {
      expect(ReadingAnchor.decode('{"u":123,"p":1,"r":0.5}'), isNull);
      expect(ReadingAnchor.decode('{"u":"a","p":"abc","r":0.5}'), isNull);
    });
  });

  group('相等性', () {
    test('同字段相等，不同字段不等', () {
      const a = ReadingAnchor(
          chapterUrl: 'u', paragraphIndex: 1, paragraphRatio: 0.5);
      const b = ReadingAnchor(
          chapterUrl: 'u', paragraphIndex: 1, paragraphRatio: 0.5);
      const otherRatio = ReadingAnchor(
          chapterUrl: 'u', paragraphIndex: 1, paragraphRatio: 0.6);
      const otherChapter = ReadingAnchor(
          chapterUrl: 'v', paragraphIndex: 1, paragraphRatio: 0.5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == otherRatio, isFalse);
      expect(a == otherChapter, isFalse);
    });
  });
}

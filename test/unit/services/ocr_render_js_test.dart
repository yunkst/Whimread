import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/ocr_render_js.dart';

void main() {
  group('buildOcrRenderJs', () {
    test('替换 CODEPOINT 占位符', () {
      final js = buildOcrRenderJs(0xE3E8, 'MyFont');
      expect(js, contains('const cp = 0xE3E8;'));
      // fontFamily 通过十六进制码点序列注入，JS 侧用 String.fromCodePoint 还原
      // "MyFont" 的码点: 77,121,70,111,110,116
      expect(js, contains('String.fromCodePoint(...[77,121,70,111,110,116])'));
      expect(js, contains("'80px ' + fontFamily"));
    });

    test('替换 FONT_FAMILY 占位符', () {
      final js = buildOcrRenderJs(0xE3E9, 'AntiCrawlFont');
      // "AntiCrawlFont" 的码点序列
      expect(js, contains('String.fromCodePoint(...[65,110,116,105,67,114,97,119,108,70,111,110,116])'));
      expect(js, contains("'80px ' + fontFamily"));
    });

    test('保留 await document.fonts.ready', () {
      final js = buildOcrRenderJs(0xE3E8, 'F');
      expect(js, contains('await document.fonts.ready'));
    });

    test('返回 base64 不带前缀', () {
      final js = buildOcrRenderJs(0xE3E8, 'F');
      expect(js, contains("toDataURL('image/png').split(',')[1]"));
    });

    test('不出现具体站点选择器', () {
      final js = buildOcrRenderJs(0xE3E8, 'F');
      expect(js, isNot(contains('muye-reader')));
      expect(js, isNot(contains('fanqie')));
    });
  });
}

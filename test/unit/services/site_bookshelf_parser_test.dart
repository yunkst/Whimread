/// SiteBookshelfParser 纯解析器单元测试
///
/// 覆盖 bookshelf_js 返回 JSON 的各种形态：
/// - 合法 {novels:[{title,url}]} → 提取列表
/// - 空数组 / 缺 novels / 非 Map 顶层 / 非法 JSON → null
/// - 某项缺 title / url → 跳过该项；全部无效 → null
/// - title/url 首尾空白 trim
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/site_bookshelf_parser.dart';

void main() {
  group('SiteBookshelfParser.parse', () {
    test('合法 novels → 提取列表', () {
      final out = SiteBookshelfParser.parse('''
        {
          "novels": [
            {"title": "斗破苍穹", "url": "https://a.com/book/1/"},
            {"title": "凡人修仙传", "url": "https://a.com/book/2/"}
          ]
        }
      ''');
      expect(out, isNotNull);
      expect(out, hasLength(2));
      expect(out![0].title, '斗破苍穹');
      expect(out[0].url, 'https://a.com/book/1/');
      expect(out[1].title, '凡人修仙传');
    });

    test('novels 为空数组 → null', () {
      expect(SiteBookshelfParser.parse('{"novels": []}'), isNull);
    });

    test('缺 novels 字段 → null', () {
      expect(SiteBookshelfParser.parse('{"title": "x"}'), isNull);
    });

    test('顶层非对象 → null', () {
      expect(SiteBookshelfParser.parse('[1,2,3]'), isNull);
      expect(SiteBookshelfParser.parse('"str"'), isNull);
    });

    test('非法 JSON → null（不抛异常）', () {
      expect(SiteBookshelfParser.parse('not json at all'), isNull);
      expect(SiteBookshelfParser.parse(''), isNull);
    });

    test('某项缺 title / url → 跳过该项', () {
      final out = SiteBookshelfParser.parse('''
        {
          "novels": [
            {"title": "缺url"},
            {"url": "https://a.com/2"},
            {"title": "有效", "url": "https://a.com/3"}
          ]
        }
      ''');
      expect(out, isNotNull);
      expect(out, hasLength(1));
      expect(out![0].title, '有效');
    });

    test('全部项无效 → null', () {
      final out = SiteBookshelfParser.parse('''
        { "novels": [ {"title": "缺url"}, {"url": "https://a.com/2"} ] }
      ''');
      expect(out, isNull);
    });

    test('title/url 首尾空白 trim；非字符串字段 toString 兜底', () {
      final out = SiteBookshelfParser.parse('''
        { "novels": [ {"title": "  书名  ", "url": " https://a.com/x "} ] }
      ''');
      expect(out, isNotNull);
      expect(out![0].title, '书名');
      expect(out[0].url, 'https://a.com/x');
    });
  });
}
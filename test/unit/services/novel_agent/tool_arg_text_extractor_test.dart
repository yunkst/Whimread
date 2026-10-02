/// ToolArgTextExtractor 单元测试
///
/// 覆盖：完整 JSON / 半截 JSON（打字机中段）/ 转义序列 / 截断转义 /
/// 键位置校验（值内同名文本不误判）/ 非字符串值跳过。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/tool_arg_text_extractor.dart';

void main() {
  group('extractStringField', () {
    test('完整 JSON：提取闭合值', () {
      expect(
        ToolArgTextExtractor.extractStringField('{"text":"山雨欲来风满楼"}', 'text'),
        '山雨欲来风满楼',
      );
    });

    test('半截 JSON：值未开始返回空串', () {
      expect(ToolArgTextExtractor.extractStringField('{"text":', 'text'), '');
      expect(ToolArgTextExtractor.extractStringField('{"text": ', 'text'), '');
      expect(ToolArgTextExtractor.extractStringField('{"text"', 'text'), isNull);
    });

    test('半截 JSON：值流到一半返回已到达部分', () {
      expect(
        ToolArgTextExtractor.extractStringField('{"text":"夜色如墨，', 'text'),
        '夜色如墨，',
      );
    });

    test('键尚未出现返回 null', () {
      expect(ToolArgTextExtractor.extractStringField('{"char', 'text'), isNull);
      expect(ToolArgTextExtractor.extractStringField('', 'text'), isNull);
    });

    test('转义引号与换行', () {
      final raw = r'{"text":"第一行\n第二行 \"引号\" 结束"}';
      expect(
        ToolArgTextExtractor.extractStringField(raw, 'text'),
        '第一行\n第二行 "引号" 结束',
      );
    });

    test('截断的转义序列丢弃尾部', () {
      expect(
        ToolArgTextExtractor.extractStringField('{"text":"abc\\', 'text'),
        'abc',
      );
      expect(
        ToolArgTextExtractor.extractStringField(r'{"text":"abc\u4e2', 'text'),
        'abc',
      );
    });

    test(r'\uXXXX 解码（含代理对 emoji）', () {
      expect(
        ToolArgTextExtractor.extractStringField(r'{"text":"\u4e2d\u6587"}', 'text'),
        '中文',
      );
      expect(
        ToolArgTextExtractor.extractStringField(r'{"text":"\ud83d\ude00"}', 'text'),
        '😀',
      );
    });

    test('值内同名文本不误判为键', () {
      final raw = '{"character":"说text的人","text":"正文"}';
      expect(ToolArgTextExtractor.extractStringField(raw, 'text'), '正文');
      expect(ToolArgTextExtractor.extractStringField(raw, 'character'), '说text的人');
    });

    test('非字符串值跳过继续找', () {
      // 第一个 "text" 是数字值，第二个是字符串值（极端构造，验证继续搜索路径）
      final raw = '{"a":1, "text": 42, "text": "ok"}';
      expect(ToolArgTextExtractor.extractStringField(raw, 'text'), 'ok');
    });

    test('character 字段提取', () {
      final raw = '{"character":"林昭","text":"剑出鞘了"}';
      expect(ToolArgTextExtractor.extractStringField(raw, 'character'), '林昭');
    });
  });

  group('extract', () {
    test('narrate 中段流式：text 渐增、character 保持 null', () {
      final r1 = ToolArgTextExtractor.extract('{"text":"开篇');
      expect(r1.text, '开篇');
      expect(r1.character, isNull);

      final r2 = ToolArgTextExtractor.extract('{"text":"开篇第一段，风起。"}');
      expect(r2.text, '开篇第一段，风起。');
      expect(r2.character, isNull);
    });

    test('speak：character 先到，text 后流', () {
      final r = ToolArgTextExtractor.extract('{"character":"林昭","text":"走"');
      expect(r.character, '林昭');
      expect(r.text, '走');
    });

    test('空参数串返回空文本', () {
      final r = ToolArgTextExtractor.extract('');
      expect(r.text, '');
      expect(r.character, isNull);
    });
  });
}

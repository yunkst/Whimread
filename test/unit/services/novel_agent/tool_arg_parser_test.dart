/// ToolArgParser 参数安全解析器单元测试
///
/// 验证所有参数提取方法的类型安全行为：
/// - requireString / requireInt — 必填参数的成功和失败路径
/// - optionalInt / optionalString / nullableString — 可选参数
/// - 类型转换（double→int, String→int）
/// - 错误格式（missing / type_error / empty）
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/novel_agent/tool_arg_parser_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/tool_arg_parser.dart';

void main() {
  group('ToolArgParser', () {
    // ═══ requireString ═══

    group('requireString', () {
      test('正常提取 String', () {
        final parser = ToolArgParser({'name': 'hello'});
        final (value, err) = parser.requireString('name');
        expect(value, 'hello');
        expect(err, isNull);
      });

      test('自动 trim', () {
        final parser = ToolArgParser({'name': '  hello  '});
        final (value, err) = parser.requireString('name');
        expect(value, 'hello');
        expect(err, isNull);
      });

      test('缺失返回错误', () {
        final parser = ToolArgParser(<String, dynamic>{});
        final (value, err) = parser.requireString('name');
        expect(value, '');
        expect(err, isNotNull);
        final decoded = jsonDecode(err!) as Map<String, dynamic>;
        expect(decoded['error'], 'missing_required_param');
      });

      test('null 返回错误', () {
        final parser = ToolArgParser({'name': null});
        final (value, err) = parser.requireString('name');
        expect(value, '');
        expect(err, isNotNull);
      });

      test('类型不匹配返回错误', () {
        final parser = ToolArgParser({'name': 123});
        final (value, err) = parser.requireString('name');
        expect(value, '');
        expect(err, isNotNull);
        final decoded = jsonDecode(err!) as Map<String, dynamic>;
        expect(decoded['error'], 'param_type_error');
      });

      test('空字符串（trim 后）返回错误', () {
        final parser = ToolArgParser({'name': '   '});
        final (value, err) = parser.requireString('name');
        expect(value, '');
        expect(err, isNotNull);
        final decoded = jsonDecode(err!) as Map<String, dynamic>;
        expect(decoded['error'], 'empty_param');
      });
    });

    // ═══ requireInt ═══

    group('requireInt', () {
      test('正常提取 int', () {
        final parser = ToolArgParser({'position': 5});
        final (value, err) = parser.requireInt('position');
        expect(value, 5);
        expect(err, isNull);
      });

      test('double 自动转 int', () {
        final parser = ToolArgParser({'position': 5.0});
        final (value, err) = parser.requireInt('position');
        expect(value, 5);
        expect(err, isNull);
      });

      test('String 数字自动解析', () {
        final parser = ToolArgParser({'position': '5'});
        final (value, err) = parser.requireInt('position');
        expect(value, 5);
        expect(err, isNull);
      });

      test('缺失返回错误', () {
        final parser = ToolArgParser(<String, dynamic>{});
        final (value, err) = parser.requireInt('position');
        expect(value, 0);
        expect(err, isNotNull);
        final decoded = jsonDecode(err!) as Map<String, dynamic>;
        expect(decoded['error'], 'missing_required_param');
      });

      test('非数字 String 返回错误', () {
        final parser = ToolArgParser({'position': 'five'});
        final (value, err) = parser.requireInt('position');
        expect(value, 0);
        expect(err, isNotNull);
        final decoded = jsonDecode(err!) as Map<String, dynamic>;
        expect(decoded['error'], 'param_type_error');
      });

      test('bool 类型返回错误', () {
        final parser = ToolArgParser({'position': true});
        final (value, err) = parser.requireInt('position');
        expect(value, 0);
        expect(err, isNotNull);
      });
    });

    // ═══ optionalInt ═══

    group('optionalInt', () {
      test('正常提取 int', () {
        final parser = ToolArgParser({'position': 5});
        final (value, err) = parser.optionalInt('position');
        expect(value, 5);
        expect(err, isNull);
      });

      test('缺失返回 (null, null)', () {
        final parser = ToolArgParser(<String, dynamic>{});
        final (value, err) = parser.optionalInt('position');
        expect(value, isNull);
        expect(err, isNull);
      });

      test('null 返回 (null, null)', () {
        final parser = ToolArgParser({'position': null});
        final (value, err) = parser.optionalInt('position');
        expect(value, isNull);
        expect(err, isNull);
      });

      test('double 自动转 int', () {
        final parser = ToolArgParser({'position': 3.0});
        final (value, err) = parser.optionalInt('position');
        expect(value, 3);
        expect(err, isNull);
      });

      test('类型不匹配返回错误', () {
        final parser = ToolArgParser({'position': 'abc'});
        final (value, err) = parser.optionalInt('position');
        expect(value, isNull);
        expect(err, isNotNull);
      });
    });

    // ═══ optionalString ═══

    group('optionalString', () {
      test('正常提取 String', () {
        final parser = ToolArgParser({'description': 'hello'});
        final (value, err) = parser.optionalString('description');
        expect(value, 'hello');
        expect(err, isNull);
      });

      test('缺失返回 (null, null)', () {
        final parser = ToolArgParser(<String, dynamic>{});
        final (value, err) = parser.optionalString('description');
        expect(value, isNull);
        expect(err, isNull);
      });

      test('类型不匹配返回错误', () {
        final parser = ToolArgParser({'description': 123});
        final (value, err) = parser.optionalString('description');
        expect(value, isNull);
        expect(err, isNotNull);
      });
    });

    // ═══ nullableString ═══

    group('nullableString', () {
      test('正常提取 String', () {
        final parser = ToolArgParser({'desc': 'hello'});
        final (value, err) = parser.nullableString('desc');
        expect(value, 'hello');
        expect(err, isNull);
      });

      test('缺失返回 (null, null)', () {
        final parser = ToolArgParser(<String, dynamic>{});
        final (value, err) = parser.nullableString('desc');
        expect(value, isNull);
        expect(err, isNull);
      });

      test('空字符串返回 (null, null)', () {
        final parser = ToolArgParser({'desc': '   '});
        final (value, err) = parser.nullableString('desc');
        expect(value, isNull);
        expect(err, isNull);
      });
    });

    // ═══ 错误格式验证 ═══

    group('错误格式', () {
      test('missing 错误包含 param 字段', () {
        final parser = ToolArgParser(<String, dynamic>{});
        final (_, err) = parser.requireString('novelId');
        final decoded = jsonDecode(err!) as Map<String, dynamic>;
        expect(decoded['error'], 'missing_required_param');
        expect(decoded['param'], 'novelId');
        expect(decoded['message'], contains('novelId'));
      });

      test('type 错误包含期望和实际类型', () {
        final parser = ToolArgParser({'novelId': 'abc'});
        final (_, err) = parser.requireInt('novelId');
        final decoded = jsonDecode(err!) as Map<String, dynamic>;
        expect(decoded['error'], 'param_type_error');
        expect(decoded['param'], 'novelId');
        expect(decoded['message'], contains('int'));
      });
    });
  });
}

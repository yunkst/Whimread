import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/tool_arg_parser.dart';

void main() {
  group('requireBool', () {
    test('bool 值返回 (value, null)', () {
      expect(ToolArgParser({'k': true}).requireBool('k'), (true, null));
      expect(ToolArgParser({'k': false}).requireBool('k'), (false, null));
    });

    test('缺失返回 missing_error', () {
      final (_, err) = ToolArgParser({}).requireBool('k');
      expect(err, isNotNull);
      final decoded = jsonDecode(err!);
      expect(decoded['error'], 'missing_required_param');
      expect(decoded['param'], 'k');
    });

    test('null 返回 missing_error', () {
      final (_, err) = ToolArgParser({'k': null}).requireBool('k');
      expect(err, isNotNull);
      expect(jsonDecode(err!)['error'], 'missing_required_param');
    });

    test('非 bool 返回 type_error', () {
      final (_, err) = ToolArgParser({'k': 'true'}).requireBool('k');
      expect(err, isNotNull);
      expect(jsonDecode(err!)['error'], 'param_type_error');
    });
  });
}

/// ToolCall.fromJson / StreamingResult.buildToolCalls 单元测试
///
/// 验证 arguments 解析失败时（流式拼接截断 / JSON 不闭合 / 解析成功但不是对象）
/// 回填 __parse_error 标记字典，而非静默丢失用户参数。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/dsl_engine/build_tool_calls_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToolCall.fromJson arguments 解析', () {
    test('合法 JSON 字符串 → 解析为 Map，不带错误标记', () {
      final tc = ToolCall.fromJson({
        'id': 'call_1',
        'function': {
          'name': 'list_novels',
          'arguments': '{"limit": 10}',
        },
      });
      expect(tc.name, 'list_novels');
      expect(tc.arguments, {'limit': 10});
      expect(tc.arguments.containsKey(kArgsParseErrorKey), false);
    });

    test('arguments 已为 Map → 直接使用', () {
      final tc = ToolCall.fromJson({
        'id': 'call_1',
        'function': {
          'name': 'foo',
          'arguments': {'a': 1, 'b': 'x'},
        },
      });
      expect(tc.arguments, {'a': 1, 'b': 'x'});
      expect(tc.arguments.containsKey(kArgsParseErrorKey), false);
    });

    test('JSON 不合法（缺右括号） → 标记 __parse_error，保留原始预览', () {
      final tc = ToolCall.fromJson({
        'id': 'call_1',
        'function': {
          'name': 'create_chapter',
          // 故意不闭合：缺少最右边的 }
          'arguments': '{"position":1,"instruction":"写得好',
        },
      });
      expect(tc.arguments.containsKey(kArgsParseErrorKey), true);
      expect(tc.arguments[kArgsParseErrorKey], true);
      expect(tc.arguments.containsKey(kArgsParseErrorDetailKey), true);
      expect(tc.arguments.containsKey(kArgsRawPreviewKey), true);
      expect(
        (tc.arguments[kArgsRawPreviewKey] as String).length,
        greaterThan(0),
      );
    });

    test('合法 JSON 但不是对象（数组）→ 也标记 __parse_error', () {
      final tc = ToolCall.fromJson({
        'id': 'call_1',
        'function': {
          'name': 'weird_tool',
          'arguments': '[1,2,3]',
        },
      });
      expect(tc.arguments.containsKey(kArgsParseErrorKey), true);
      expect(
        tc.arguments[kArgsParseErrorDetailKey].toString(),
        contains('不是对象'),
      );
    });

    test('arguments 字段类型异常（数字）→ 也标记', () {
      final tc = ToolCall.fromJson({
        'id': 'call_1',
        'function': {
          'name': 'foo',
          'arguments': 42,
        },
      });
      expect(tc.arguments.containsKey(kArgsParseErrorKey), true);
    });

    test('arguments 为 null / 空字符串 → 不标记（正常无参工具）', () {
      final tc1 = ToolCall.fromJson({
        'id': 'call_1',
        'function': {'name': 'foo', 'arguments': null},
      });
      expect(tc1.arguments, isEmpty);
      expect(tc1.arguments.containsKey(kArgsParseErrorKey), false);

      final tc2 = ToolCall.fromJson({
        'id': 'call_1',
        'function': {'name': 'foo', 'arguments': ''},
      });
      expect(tc2.arguments, isEmpty);
      expect(tc2.arguments.containsKey(kArgsParseErrorKey), false);
    });

    test('原始 args 超长 → preview 被截断到 500 字符（+ truncated 后缀）', () {
      // 构造一个超长的不闭合 JSON
      final broken = '{"x":${'y' * 2000}'; // 故意不闭合
      final tc = ToolCall.fromJson({
        'id': 'call_1',
        'function': {'name': 'foo', 'arguments': broken},
      });
      expect(tc.arguments.containsKey(kArgsParseErrorKey), true);
      // 500 字符 + '...(truncated)' (14字符) = 514
      expect(
        (tc.arguments[kArgsRawPreviewKey] as String).length,
        lessThanOrEqualTo(514),
      );
    });
  });

  group('StreamingResult.buildToolCalls 解析', () {
    test('聚合后合法 args 字符串 → 解析正常', () {
      final sr = StreamingResult(toolCallDeltas: [
        {
          'index': 0,
          'id': 'c1',
          'function': {'name': 'list_novels'}
        },
        {
          'index': 0,
          'function': {'arguments': '{"limit":5}'}
        },
      ]);
      final tcs = sr.buildToolCalls();
      expect(tcs, hasLength(1));
      expect(tcs.first.name, 'list_novels');
      expect(tcs.first.arguments, {'limit': 5});
    });

    test('聚合后 args 拼接成不合法 JSON → 标记 __parse_error', () {
      // 模拟流式拼接：第 2 段末尾尾随逗号破坏 JSON 闭合
      final sr = StreamingResult(toolCallDeltas: [
        {
          'index': 0,
          'id': 'c1',
          'function': {'name': 'create_chapter'}
        },
        {
          'index': 0,
          'function': {'arguments': '{"position":1,"instruction":"写'}
        },
        {
          'index': 0,
          'function': {'arguments': '一章主角修炼"},}'}
        },
      ]);
      final tcs = sr.buildToolCalls();
      expect(tcs, hasLength(1));
      expect(tcs.first.arguments.containsKey(kArgsParseErrorKey), true);
    });

    test('多 tool_calls 并行（index=0,1），各自独立聚合与解析', () {
      final sr = StreamingResult(toolCallDeltas: [
        {
          'index': 0,
          'id': 'c1',
          'function': {'name': 'tool_a'}
        },
        {
          'index': 1,
          'id': 'c2',
          'function': {'name': 'tool_b'}
        },
        {
          'index': 0,
          'function': {'arguments': '{"a":1}'}
        },
        {
          'index': 1,
          'function': {'arguments': '[bad json'}
        },
      ]);
      final tcs = sr.buildToolCalls();
      expect(tcs, hasLength(2));
      // index=0 正常
      final a = tcs.firstWhere((t) => t.id == 'c1');
      expect(a.arguments, {'a': 1});
      expect(a.arguments.containsKey(kArgsParseErrorKey), false);
      // index=1 标记错误
      final b = tcs.firstWhere((t) => t.id == 'c2');
      expect(b.arguments.containsKey(kArgsParseErrorKey), true);
    });

    test('空 deltas 列表 → 返回空 toolCalls', () {
      final sr = StreamingResult(toolCallDeltas: const []);
      expect(sr.buildToolCalls(), isEmpty);
    });

    // 回归：DeepSeek-V4-Pro 流式后续帧 function.name 为空串 ""，覆盖首帧真名
    // （实捕 llm_1787760494454_3332 同型流：首帧 name="list_prompt_tags" 完整、
    // 次帧 name="" 且 id=null，OpenAI/glm-4.7 规范行为是省略字段而非空串）。
    // 空串不是合法工具名，不得覆盖已聚合的 name。
    test('DeepSeek 后续帧 name 为空串 → 不覆盖首帧真名（回归 llm_1787760494454_3332）', () {
      final sr = StreamingResult(toolCallDeltas: [
        {
          'index': 0,
          'id': '01a03eedc2b388ed35523f51cdc15fa6',
          'type': 'function',
          'function': {'name': 'list_prompt_tags', 'arguments': ''},
        },
        {
          'index': 0,
          'id': null,
          'type': null,
          'function': {'name': '', 'arguments': '{}'},
        },
      ]);
      final tcs = sr.buildToolCalls();
      expect(tcs, hasLength(1));
      expect(tcs.first.name, 'list_prompt_tags');
      expect(tcs.first.arguments, isEmpty); // "{}" 解析为空 Map
    });

    test('name 先空串后有值 → 空串不写入，最终取非空 name', () {
      final sr = StreamingResult(toolCallDeltas: [
        {
          'index': 0,
          'id': 'c1',
          'function': {'name': ''}  // 首帧空串（部分网关首帧只带 id）
        },
        {
          'index': 0,
          'function': {'name': 'list_prompt_tags'}  // 后续帧补上真名
        },
        {
          'index': 0,
          'function': {'arguments': '{}'}
        },
      ]);
      final tcs = sr.buildToolCalls();
      expect(tcs, hasLength(1));
      expect(tcs.first.name, 'list_prompt_tags');
    });

    test('name 帧全为空串 → 整条不可执行，返回空列表', () {
      final sr = StreamingResult(toolCallDeltas: [
        {
          'index': 0,
          'id': 'c1',
          'function': {'name': '', 'arguments': '{}'}
        },
      ]);
      expect(sr.buildToolCalls(), isEmpty);
    });
  });
}

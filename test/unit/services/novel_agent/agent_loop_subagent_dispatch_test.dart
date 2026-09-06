/// AgentLoop 拆分「普通工具串行 + dispatch_subagent 并行」单元测试
///
/// 验证任务 7 改造：
/// - 同轮 2 个 dispatch_subagent 工具调用应**并行执行**（耗时重叠），
///   而非像普通工具那样串行（每个等上一个完成）。
/// - dispatch_subagent 与普通工具混合时，普通工具应**先串行跑完**
///   再并行派子 Agent；不能把子 Agent 派发与普通工具并行。
/// - 调用 `_executeSingleTool` 私有方法路径时，`toolCallId` 应透传进 scenario。
///
/// 沿用 agent_loop_cancel_test.dart 的 FakeLlmProvider + FakeAgentScenario 范式。
/// FakeAgentScenario 重写 executeTool 接 toolCallId（用于校验透传）。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/novel_agent/agent_loop_subagent_dispatch_test.dart
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import '../../../helpers/fake_agent_scenario.dart';
import '../../../helpers/noop_llm_http_client.dart';

// ---------------------------------------------------------------------------
// Fakes（与 agent_loop_cancel_test.dart 同范式，独立文件避免测试间耦合）
// ---------------------------------------------------------------------------

/// 按预设脚本返回流式响应的假 LLM Provider
class _ScriptedLlm extends LlmProvider {
  _ScriptedLlm()
      : super(
          const LlmConfig(
            baseUrl: 'http://localhost',
            apiKey: 'test',
            defaultModel: 'test-model',
          ),
          httpClient: NoopLlmHttpClient(),
        );

  final List<_ScriptedResponse> _script = [];
  int callCount = 0;

  void enqueue(_ScriptedResponse r) => _script.add(r);

  @override
  Stream<LlmStreamChunk> chatStreamWithTools({
    required List<ChatMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
  }) async* {
    callCount++;
    if (_script.isEmpty) {
      throw StateError('_ScriptedLlm 脚本已耗尽');
    }
    final resp = _script.removeAt(0);
    for (final chunk in resp.contentChunks) {
      yield LlmStreamChunk(contentChunk: chunk);
    }
    if (resp.toolCallDeltas != null) {
      yield LlmStreamChunk(
        toolCallDeltas: resp.toolCallDeltas!,
        finishReason: 'tool_calls',
      );
    } else {
      yield const LlmStreamChunk(finishReason: 'stop');
    }
  }
}

class _ScriptedResponse {
  final List<String> contentChunks;
  final List<Map<String, dynamic>>? toolCallDeltas;
  const _ScriptedResponse({this.contentChunks = const [], this.toolCallDeltas});
}

/// 假场景：可控制每个工具的耗时，并按调用顺序记录开始/结束时间
///
/// 重写 executeTool 接 toolCallId（命名参数），用以验证 AgentLoop 透传 call.id。
/// 同时记录每个工具的 start/end wall clock 和 toolCallId，供测试断言。
class _DispatchAgentScenario extends BaseFakeAgentScenario {
  @override
  final String id = 'dispatch-test';

  @override
  final String displayName = 'Dispatch Test Scenario';

  /// 按工具名配置的延时（默认 0）
  final Map<String, Duration> toolDelays;

  /// 工具调用记录：开始时间、结束时间、toolCallId
  final List<_ToolExecutionRecord> executions = [];

  _DispatchAgentScenario({
    this.toolDelays = const {},
  });

  @override
  String buildSystemPrompt(AgentScenarioContext context) => 'sys';

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    final start = DateTime.now();
    final delay = toolDelays[name] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final end = DateTime.now();
    executions.add(_ToolExecutionRecord(
      name: name,
      toolCallId: toolCallId,
      start: start,
      end: end,
    ));
    return _encodeJson({'ok': true});
  }
}

class _ToolExecutionRecord {
  final String name;
  final String? toolCallId;
  final DateTime start;
  final DateTime end;
  _ToolExecutionRecord({
    required this.name,
    required this.toolCallId,
    required this.start,
    required this.end,
  });
}

String _encodeJson(Map<String, dynamic> m) {
  return '{${m.entries.map((e) => '"${e.key}":${_encodeValue(e.value)}').join(',')}}';
}

String _encodeValue(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return '$v';
  if (v is String) {
    return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  }
  return '"$v"';
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

void main() {
  group('AgentLoop dispatch_subagent 并行 / 串行拆分', () {
    test('同轮 2 个 dispatch_subagent 并行执行（时间重叠）', () async {
      // LLM 第一轮返回 2 个 dispatch_subagent tool_calls，第二轮无 tool 结束。
      final llm = _ScriptedLlm()
        ..enqueue(const _ScriptedResponse(
          contentChunks: [''],
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'tc_a',
              'function': {'name': 'dispatch_subagent', 'arguments': '{}'},
            },
            {
              'index': 1,
              'id': 'tc_b',
              'function': {'name': 'dispatch_subagent', 'arguments': '{}'},
            },
          ],
        ))
        ..enqueue(const _ScriptedResponse(contentChunks: ['完成']));

      // 每个 dispatch_subagent 模拟 100ms 子 Agent
      final scenario = _DispatchAgentScenario(
        toolDelays: const {'dispatch_subagent': Duration(milliseconds: 100)},
      );
      final loop = AgentLoop(llm: llm, scenario: scenario);

      await loop.run(
        initialMessages: [const ChatMessage(role: 'user', content: 'go')],
        systemPrompt: 'sys',
        emit: (_) {},
      );

      expect(scenario.executions.length, 2,
          reason: '应执行 2 次 dispatch_subagent');
      // 验证两个 dispatch_subagent 的时间区间**重叠**（并行执行）
      // 串行执行时 a.end 必然 < b.start（无重叠）；并行才有重叠。
      final a = scenario.executions[0];
      final b = scenario.executions[1];
      final overlap = a.start.isBefore(b.end) && b.start.isBefore(a.end);
      expect(overlap, isTrue,
          reason:
              '两个 dispatch_subagent 应并行执行（时间区间重叠），而非串行（区间不重叠）');
    });

    test('dispatch_subagent 与普通工具混合：普通工具先串行跑完再派子', () async {
      // 第一轮返回 [list_novels, dispatch_subagent]
      // 第二轮无 tool 结束
      final llm = _ScriptedLlm()
        ..enqueue(const _ScriptedResponse(
          contentChunks: [''],
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'tc_normal',
              'function': {'name': 'list_novels', 'arguments': '{}'},
            },
            {
              'index': 1,
              'id': 'tc_dispatch',
              'function': {'name': 'dispatch_subagent', 'arguments': '{}'},
            },
          ],
        ))
        ..enqueue(const _ScriptedResponse(contentChunks: ['done']));

      // list_novels 慢一点，dispatch_subagent 快点
      final scenario = _DispatchAgentScenario(
        toolDelays: const {
          'list_novels': Duration(milliseconds: 50),
          'dispatch_subagent': Duration(milliseconds: 50),
        },
      );
      final loop = AgentLoop(llm: llm, scenario: scenario);

      await loop.run(
        initialMessages: [const ChatMessage(role: 'user', content: 'go')],
        systemPrompt: 'sys',
        emit: (_) {},
      );

      expect(scenario.executions.length, 2);
      final normal = scenario.executions.firstWhere((e) => e.name == 'list_novels');
      final dispatch =
          scenario.executions.firstWhere((e) => e.name == 'dispatch_subagent');

      // 普通工具必须早于 dispatch_subagent 开始
      expect(normal.start.isBefore(dispatch.start) ||
              normal.start.isAtSameMomentAs(dispatch.start), isTrue,
          reason: '普通工具 list_novels 应在 dispatch_subagent 之前开始');

      // 普通工具必须早于 dispatch_subagent 结束（串行语义）。
      // 用 <= 而非 < 容忍同毫秒边界（Future.delayed + DateTime.now 在跨测试文件
      // 场景下调度抖动可能让 end 与 start 落在同一毫秒，但仍属串行先完成语义）。
      expect(!normal.end.isAfter(dispatch.start), isTrue,
          reason:
              'list_novels 串行跑完（end <= dispatch.start）；不是与 dispatch_subagent 并行');
    });

    test('toolCallId 透传到 scenario.executeTool', () async {
      // 验证 AgentLoop 把 call.id 传给 scenario.executeTool(toolCallId: ...)
      final llm = _ScriptedLlm()
        ..enqueue(const _ScriptedResponse(
          contentChunks: [''],
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'tc-xyz-123',
              'function': {'name': 'list_novels', 'arguments': '{}'},
            },
          ],
        ))
        ..enqueue(const _ScriptedResponse(contentChunks: ['完成']));

      final scenario = _DispatchAgentScenario();
      final loop = AgentLoop(llm: llm, scenario: scenario);

      await loop.run(
        initialMessages: [const ChatMessage(role: 'user', content: 'go')],
        systemPrompt: 'sys',
        emit: (_) {},
      );

      expect(scenario.executions.length, 1);
      expect(scenario.executions.first.toolCallId, 'tc-xyz-123',
          reason: 'AgentLoop 必须把 LLM tool_calls[i].id 透传给 executeTool');
    });
  });
}
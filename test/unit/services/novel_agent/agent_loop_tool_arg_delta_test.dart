/// AgentLoop 工具参数流式转发（ToolArgDeltaEvent）测试
///
/// 验证：
/// - 白名单工具（streamableToolNames）的参数流式过程 emit ToolArgDeltaEvent，
///   text 为累计文本，≥12 字符增量节流，首个非空必发
/// - 非白名单工具不 emit
/// - 流结束后仍走正常 ReAct（ToolCallStart/End + AgentDone 不受影响）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import '../../../helpers/fake_agent_scenario.dart';
import '../../../helpers/noop_llm_http_client.dart';

class _ScriptedLlm extends LlmProvider {
  _ScriptedLlm(this.rounds)
      : super(const LlmConfig(
          baseUrl: 'http://localhost',
          apiKey: 'test',
          defaultModel: 'test-model',
        ), httpClient: NoopLlmHttpClient());

  /// 每轮 LLM 响应的 content chunk 与 tool_call delta 帧序列
  final List<List<LlmStreamChunk>> rounds;
  int callCount = 0;

  @override
  Stream<LlmStreamChunk> chatStreamWithTools({
    required List<ChatMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
  }) async* {
    final frames = rounds[callCount];
    callCount++;
    yield* Stream.fromIterable(frames);
  }
}

/// 构造一帧 narrate 工具的 arguments delta
Map<String, dynamic> _narrateDelta(String argsFragment, {int index = 0}) =>
    {
      'index': index,
      'id': index == 0 ? 'call_real_1' : null,
      'function': {'name': 'narrate', 'arguments': argsFragment},
    };

class _StreamableScenario extends BaseFakeAgentScenario {
  @override
  String get id => 'fake_streamable';

  @override
  Set<String> get streamableToolNames => const {'narrate'};

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    return '{"ok":true}';
  }
}

class _PlainScenario extends BaseFakeAgentScenario {
  @override
  String get id => 'fake_plain';

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    return '{"ok":true}';
  }
}

void main() {
  test('白名单工具：参数流式 emit 累计文本，节流生效', () async {
    final llm = _ScriptedLlm([
      [
        // 帧 1：id + name 到达，值未开始 → 不 emit（text 为空）
        LlmStreamChunk(toolCallDeltas: [
          {'index': 0, 'id': 'call_real_1', 'function': {'name': 'narrate', 'arguments': '{"text":"'}}
        ], finishReason: null),
        // 帧 2：短文本（<12 字符增量）→ 首个非空必发
        LlmStreamChunk(toolCallDeltas: [
          {'index': 0, 'function': {'arguments': '夜色'}}
        ], finishReason: null),
        // 帧 3：又只增 2 字 → 不 emit
        LlmStreamChunk(toolCallDeltas: [
          {'index': 0, 'function': {'arguments': '如墨'}}
        ], finishReason: null),
        // 帧 4：累计超过 12 字增量 → emit
        LlmStreamChunk(toolCallDeltas: [
          {'index': 0, 'function': {'arguments': '，远处传来马蹄声阵阵，火把的光在山道上游移。'}}
        ], finishReason: null),
        LlmStreamChunk(finishReason: 'tool_calls'),
      ],
      [
        LlmStreamChunk(contentChunk: '好的'),
        const LlmStreamChunk(finishReason: 'stop'),
      ],
    ]);
    final loop = AgentLoop(llm: llm, scenario: _StreamableScenario());

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '开始')],
      systemPrompt: 'sys',
      emit: events.add,
    );

    final deltas = events.whereType<ToolArgDeltaEvent>().toList();
    // 首发（夜色）+ 超阈值一次 = 2 次
    expect(deltas, hasLength(2));
    expect(deltas[0].toolCallId, 'call_real_1');
    expect(deltas[0].text, '夜色');
    expect(deltas[1].text, '夜色如墨，远处传来马蹄声阵阵，火把的光在山道上游移。');

    // 正常 ReAct 不受影响：工具开始/结束 + 最终完成
    expect(events.whereType<ToolCallStartEvent>().map((e) => e.name), contains('narrate'));
    expect(events.whereType<ToolCallEndEvent>(), isNotEmpty);
    expect(events.last, isA<AgentDoneEvent>());
  });

  test('非白名单场景：同样参数不 emit', () async {
    final llm = _ScriptedLlm([
      [
        LlmStreamChunk(toolCallDeltas: [
          {'index': 0, 'id': 'call_x', 'function': {'name': 'narrate', 'arguments': '{"text":"很长很长的一段剧情文本超过十二个字符了"}'}}
        ], finishReason: null),
        LlmStreamChunk(finishReason: 'tool_calls'),
      ],
      [
        LlmStreamChunk(contentChunk: 'done'),
        const LlmStreamChunk(finishReason: 'stop'),
      ],
    ]);
    final loop = AgentLoop(llm: llm, scenario: _PlainScenario());

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '开始')],
      systemPrompt: 'sys',
      emit: events.add,
    );

    expect(events.whereType<ToolArgDeltaEvent>(), isEmpty);
    expect(events.last, isA<AgentDoneEvent>());
  });

  test('占位 id：真实 id 帧未到达时按 index 合成 call_<index>', () async {
    final llm = _ScriptedLlm([
      [
        // id 尚未到达（首帧无 id）→ 占位 call_0
        LlmStreamChunk(toolCallDeltas: [
          {'index': 0, 'function': {'name': 'narrate', 'arguments': '{"text":"超过十二个字符的首段剧情文本内容"'}}
        ], finishReason: null),
        LlmStreamChunk(finishReason: 'tool_calls'),
      ],
      [
        LlmStreamChunk(contentChunk: '好的'),
        const LlmStreamChunk(finishReason: 'stop'),
      ],
    ]);
    final loop = AgentLoop(llm: llm, scenario: _StreamableScenario());

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '开始')],
      systemPrompt: 'sys',
      emit: events.add,
    );

    final deltas = events.whereType<ToolArgDeltaEvent>().toList();
    expect(deltas, hasLength(1));
    expect(deltas.first.toolCallId, 'call_0');
  });

  test('思维链增量：emit ReasoningDeltaEvent（与工具白名单无关，仅展示用）', () async {
    final llm = _ScriptedLlm([
      [
        LlmStreamChunk(reasoningChunk: '玩家想试探，'),
        LlmStreamChunk(reasoningChunk: '我该让林昭保持警惕。'),
        LlmStreamChunk(toolCallDeltas: [
          {'index': 0, 'id': 'call_r', 'function': {'name': 'narrate', 'arguments': '{"text":"超过十二个字符的首段剧情文本内容'}}
        ], finishReason: null),
        LlmStreamChunk(finishReason: 'tool_calls'),
      ],
      [
        LlmStreamChunk(contentChunk: '好的'),
        const LlmStreamChunk(finishReason: 'stop'),
      ],
    ]);
    // 用非白名单场景验证：reasoning 发射与白名单无关
    final loop = AgentLoop(llm: llm, scenario: _PlainScenario());

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '开始')],
      systemPrompt: 'sys',
      emit: events.add,
    );

    final reasoning = events.whereType<ReasoningDeltaEvent>().toList();
    expect(reasoning.map((e) => e.text).join(), '玩家想试探，我该让林昭保持警惕。');
    // 正常 ReAct 不受影响
    expect(events.whereType<ToolArgDeltaEvent>(), isEmpty);
    expect(events.last, isA<AgentDoneEvent>());
  });
}

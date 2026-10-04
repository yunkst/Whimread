/// AgentLoop 流式参数尾字收尾测试
///
/// 用户反馈「文字游戏吞字，完整内容要等本轮 loop 结束才显示」。根因：
/// 工具参数的展示增量按「≥12 字符」节流 emit，且只在 toolCallDeltas chunk
/// 里发——流结束后无补发，最后一块参数（不足 12 字符的一截）永远发不出
/// 去；而工具执行后到回合结束之间没有任何机制用完整参数回填直播画面
/// （pending 段按设计跳过 narrate/speak），尾字只能等 AgentDone 的定稿
/// 投影才补上。
///
/// 修复：工具执行前做一次收尾 flush（仅在确有缺口时）。覆盖：
/// - 末块不足阈值 → 收尾补齐，最后一次打字机文本 == 工具完整参数
/// - 参数整块在收尾帧才到达（流式期间一个字没发）→ 收尾补发全文
/// - 已在流式期间发全 → 不产生多余事件
///
/// 运行:
///   flutter test test/unit/services/novel_agent/agent_loop_arg_flush_test.dart
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
    if (callCount >= rounds.length) {
      throw StateError('轮次脚本已耗尽：循环多发了第 ${callCount + 1} 轮');
    }
    yield* Stream.fromIterable(rounds[callCount++]);
  }
}

/// narrate/speak 为流式工具的场景（记录工具收到的完整参数）
class _StoryStreamScenario extends BaseFakeAgentScenario {
  final List<Map<String, dynamic>> args = [];

  @override
  String get id => 'fake_story_stream';

  @override
  Set<String> get streamableToolNames => const {'narrate', 'speak'};

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    this.args.add(args);
    return '{"ok":true}';
  }
}

/// narrate 流式工具调用，参数按 [chunks] 逐帧下，最后一帧 finish
List<LlmStreamChunk> _streamRound(List<String> chunks,
        {String name = 'narrate', String id = 'call_n1'}) =>
    [
      for (var i = 0; i < chunks.length; i++)
        LlmStreamChunk(
          toolCallDeltas: [
            {
              'index': 0,
              if (i == 0) 'id': id,
              'function': {
                if (i == 0) 'name': name,
                'arguments': chunks[i],
              },
            }
          ],
          finishReason: null,
        ),
      const LlmStreamChunk(finishReason: 'tool_calls'),
    ];

/// 裸文本收尾轮（narrate 非终止工具，循环会继续到下一轮才结束）
List<LlmStreamChunk> _bareTextRound() => [
      const LlmStreamChunk(contentChunk: '。'),
      const LlmStreamChunk(finishReason: 'stop'),
    ];

Future<(List<AgentEvent>, _StoryStreamScenario)> _run(
  List<LlmStreamChunk> firstRound,
) async {
  final scenario = _StoryStreamScenario();
  final loop = AgentLoop(
      llm: _ScriptedLlm([firstRound, _bareTextRound()]), scenario: scenario);
  final events = <AgentEvent>[];
  await loop.run(
    initialMessages: const [ChatMessage(role: 'user', content: '开演')],
    systemPrompt: 'sys',
    emit: events.add,
  );
  return (events, scenario);
}

List<ToolArgDeltaEvent> _deltas(List<AgentEvent> events) =>
    events.whereType<ToolArgDeltaEvent>().toList();

void main() {
  test('末块不足 12 字符：收尾把尾字补齐（打字机文本 == 工具完整参数）',
      () async {
    final (events, scenario) = await _run(_streamRound([
      '{"character": "林昭", "text": "屋内烛火摇曳，',
      '窗外更鼓已过三声。"}',
    ]));

    final deltas = _deltas(events);
    final finalText = scenario.args.single['text'] as String;
    expect(finalText, '屋内烛火摇曳，窗外更鼓已过三声。');
    expect(deltas, isNotEmpty);
    expect(deltas.last.text, finalText,
        reason: '最后一次打字机事件必须已是完整文本（修复前停在首帧）');
    expect(deltas.last.character, '林昭');
  });

  test('参数整块在收尾帧才到达：流式期间一字未发，收尾补发全文', () async {
    final (events, scenario) = await _run(_streamRound([
      '{"text": "门外传来三声轻叩。"}',
    ]));

    final deltas = _deltas(events);
    expect(deltas, hasLength(1), reason: '只有收尾这一次');
    expect(deltas.single.text, scenario.args.single['text'] as String);
  });

  test('流式期间已发全：收尾不产生多余事件', () async {
    // 24 字分两帧各 12 字：第一帧 isFirst 必发，第二帧增长 ≥12 触发 emit，
    // 之后参数不再增长 → 收尾无缺口，不应再发
    final (events, _) = await _run(_streamRound([
      '{"text": "屋外的雨停了整整一夜，檐',
      '角的水珠还在往下落个不停。"}',
    ]));

    final deltas = _deltas(events);
    expect(deltas, hasLength(2));
    expect(deltas.last.text, '屋外的雨停了整整一夜，檐角的水珠还在往下落个不停。');
  });

  test('speak 同享收尾：台词尾字同样补齐', () async {
    final (events, scenario) = await _run(_streamRound([
      '{"character": "林昭", "text": "你终究还是来了。',
      '我等这句话，等了三年。"}',
    ], name: 'speak', id: 'call_s1'));

    final deltas = _deltas(events);
    expect(deltas.last.text, scenario.args.single['text'] as String);
    expect(deltas.last.character, '林昭');
  });
}

/// AgentLoop 终止工具（AgentScenario.terminalToolNames）测试
///
/// 背景（用户反馈 #10「出现重复内容重复渲染」）：文字游戏的 present_choices
/// 提交选项即回合终点，但 AgentLoop 只认"本轮零工具调用"为结束条件，GM 交完
/// 选项后又被 onNoToolCalls 的协议提醒推着续写——把同一段剧情重演一遍并第二次
/// 提交选项。终止工具让交付型工具成功后立即结束回合。
///
/// 覆盖：
/// - 终止工具成功 → 立即 AgentDone，不再请求下一轮
/// - 终止工具返回 error → 不终止，LLM 自行纠偏重调
/// - 未声明终止工具的场景行为与引入该机制前一致
///
/// 运行:
///   flutter test test/unit/services/novel_agent/agent_loop_terminal_tool_test.dart
library;

import 'dart:convert';

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

  /// 每次调用的 messages 快照（供断言注入内容到达了下一轮载荷）
  final List<List<ChatMessage>> calls = [];

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
      throw StateError('轮次脚本已耗尽：循环多发起了第 ${callCount + 1} 轮请求');
    }
    calls.add(List.of(messages));
    final frames = rounds[callCount];
    callCount++;
    yield* Stream.fromIterable(frames);
  }
}

/// 一轮 present_choices 工具调用（3 个选项）
List<LlmStreamChunk> _choicesRound() => [
      LlmStreamChunk(
        toolCallDeltas: [
          {
            'index': 0,
            'id': 'call_choice_1',
            'function': {
              'name': 'present_choices',
              'arguments': jsonEncode({
                'choices': [
                  {'label': '拔剑'},
                  {'label': '按兵不动'},
                ]
              }),
            },
          }
        ],
        finishReason: null,
      ),
      const LlmStreamChunk(finishReason: 'tool_calls'),
    ];

/// 一轮裸文本输出（若未被终止就会出现，模拟 GM 被推着续写）
List<LlmStreamChunk> _bareTextRound(String text) => [
      LlmStreamChunk(contentChunk: text),
      const LlmStreamChunk(finishReason: 'stop'),
    ];

/// 声明 present_choices 为终止工具的场景（presentChoicesError 控制返回结果）
class _TerminalScenario extends BaseFakeAgentScenario {
  _TerminalScenario({this.presentChoicesError = false});

  final bool presentChoicesError;
  final List<String> executed = [];

  @override
  String get id => 'fake_terminal';

  @override
  Set<String> get terminalToolNames => const {'present_choices'};

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    executed.add(name);
    if (presentChoicesError) {
      return jsonEncode({
        'error': 'too_few_choices',
        'message': '至少需要 2 个选项，请补足后重新调用',
      });
    }
    return '{"ok":true}';
  }
}

/// 对照组：不声明终止工具（走 mixin 默认空集）
class _NonTerminalScenario extends _TerminalScenario {
  @override
  String get id => 'fake_non_terminal';

  @override
  Set<String> get terminalToolNames => const {};
}

void main() {
  test('终止工具成功 → 立即结束回合，不再请求下一轮', () async {
    final llm = _ScriptedLlm([
      _choicesRound(),
      // 若循环多跑一轮，这里会被消费（并导致 GM 再演一遍）
      _bareTextRound('请选择接下来的行动。'),
    ]);
    final scenario = _TerminalScenario();
    final loop = AgentLoop(llm: llm, scenario: scenario);

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '我推门而入')],
      systemPrompt: 'sys',
      emit: events.add,
    );

    expect(llm.callCount, 1, reason: '终止工具成功后不应再发第二轮请求');
    expect(scenario.executed, ['present_choices']);
    expect(events.last, isA<AgentDoneEvent>());
    final done = events.whereType<ToolCallEndEvent>().toList();
    expect(done.single.success, isTrue);
  });

  test('终止工具返回 error → 不终止，让 LLM 自行纠偏', () async {
    final llm = _ScriptedLlm([
      _choicesRound(),
      _bareTextRound('已补足两个选项。'),
    ]);
    final scenario = _TerminalScenario(presentChoicesError: true);
    final loop = AgentLoop(llm: llm, scenario: scenario);

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '我推门而入')],
      systemPrompt: 'sys',
      emit: events.add,
    );

    expect(llm.callCount, 2, reason: '工具报错时必须继续下一轮等它重调');
    expect(scenario.executed, ['present_choices']);
    expect(
      events.whereType<ToolCallEndEvent>().single.success,
      isFalse,
      reason: '错误结果原样回给 LLM 纠偏',
    );
    expect(events.last, isA<AgentDoneEvent>());
  });

  test('未声明终止工具：行为不变（工具后继续下一轮）', () async {
    final llm = _ScriptedLlm([
      _choicesRound(),
      _bareTextRound('请选择。'),
    ]);
    final scenario = _NonTerminalScenario();
    final loop = AgentLoop(llm: llm, scenario: scenario);

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '我推门而入')],
      systemPrompt: 'sys',
      emit: events.add,
    );

    expect(llm.callCount, 2);
    expect(events.last, isA<AgentDoneEvent>());
  });

  test('终止时队列有补充输入 → 注入并继续回合，不丢弃玩家发言', () async {
    // 真实时序：补充消息只在每轮 LLM 调用前 drain，玩家在 present_choices
    // 执行期间发的言此刻才进队列——若终止工具直接收尾，该输入会随运行
    // 结束被清队丢弃（用户报告「agent 完全看不到自定义输入」的根因）。
    final queue = <String>[];
    final llm = _ScriptedLlm([
      _choicesRound(),
      _bareTextRound('收到，停下了。'),
    ]);
    final scenario = _TerminalWithLateInjectionScenario(queue);
    final loop = AgentLoop(llm: llm, scenario: scenario);

    final events = <AgentEvent>[];
    await loop.run(
      initialMessages: const [ChatMessage(role: 'user', content: '我推门而入')],
      systemPrompt: 'sys',
      emit: events.add,
      pendingInjections: () {
        final out = List<String>.from(queue);
        queue.clear();
        return out;
      },
    );

    expect(llm.callCount, 2, reason: '有排队补充输入时回合必须继续一轮');
    final round1 = llm.calls[1].map((m) => m.content ?? '').join('\n');
    expect(round1, contains('我改主意了，先别动。'),
        reason: '补充输入必须进入下一轮载荷，GM 才能看到');
    expect(queue, isEmpty, reason: '注入后队列必须被 drain 干净');
    expect(events.last, isA<AgentDoneEvent>());
  });
}

/// present_choices 执行期间玩家发言的场景（模拟晚于本轮 drain 时机的补充输入）
class _TerminalWithLateInjectionScenario extends _TerminalScenario {
  _TerminalWithLateInjectionScenario(this.queue);
  final List<String> queue;

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    final result =
        await super.executeTool(name, args, toolCallId: toolCallId);
    if (name == 'present_choices') queue.add('我改主意了，先别动。');
    return result;
  }
}

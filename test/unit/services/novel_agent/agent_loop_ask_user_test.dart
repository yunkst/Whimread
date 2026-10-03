/// AgentLoop × ask_user 阻塞提问集成测试
///
/// 验证 ask_user 的核心运行时语义：
/// - executeTool 挂起时整轮暂停（下一轮 LLM 不被调用）
/// - 用户作答后答案以 tool message 回灌，循环继续并正常结束
/// - 挂起中取消令牌（用户点停止）能唤醒挂起项，run 及时结束不悬挂
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/services/novel_agent/ask_user_registry.dart';
import 'package:novel_app/utils/cancellation_token.dart';
import '../../../helpers/fake_agent_scenario.dart';
import '../../../helpers/noop_llm_http_client.dart';

/// 与 agent_loop_pending_injections_test 同款的脚本化 LLM
class CapturingLlmProvider extends LlmProvider {
  CapturingLlmProvider(this.script)
      : super(const LlmConfig(
          baseUrl: 'http://localhost',
          apiKey: 'test',
          defaultModel: 'test-model',
        ), httpClient: NoopLlmHttpClient());

  final List<ScriptedResponse> script;
  int callCount = 0;
  final List<List<ChatMessage>> receivedMessages = [];

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
    receivedMessages.add(List<ChatMessage>.from(messages));
    if (callCount > script.length) {
      throw StateError('CapturingLlmProvider 脚本耗尽 (call=$callCount)');
    }
    final resp = script[callCount - 1];
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

class ScriptedResponse {
  final List<String> contentChunks;
  final List<Map<String, dynamic>>? toolCallDeltas;
  const ScriptedResponse({
    this.contentChunks = const [],
    this.toolCallDeltas,
  });
}

/// executeTool 里复刻 WritingScenario ask_user 分支的挂起协议
/// （register → token 注册取消回调 → await → 回答案 JSON）
class _AskUserFakeScenario extends BaseFakeAgentScenario {
  final AskUserRegistry registry;
  final CancellationToken? token;

  /// executeTool 进入挂起等待时置位（测试用它确定 run 已暂停）
  final Completer<void> paused = Completer<void>();

  _AskUserFakeScenario(this.registry, [this.token]);

  @override
  String get id => 'fake';

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    if (name != 'ask_user') return '{"ok":true}';
    final callId = toolCallId ?? 'call_fallback';
    final entry = registry.register(
      scenarioId: 'fake',
      toolCallId: callId,
      question: (args['question'] as String?) ?? '',
      options: const [],
      multiSelect: false,
      allowFreeText: true,
    );
    final unregister = token?.register(
      () => entry.complete(const AskUserAnswer.cancelled()),
    );
    if (!paused.isCompleted) paused.complete();
    try {
      final answer = await entry.future;
      if (!answer.isAnswered) {
        return jsonEncode({
          'success': true,
          'status': answer.status.name,
          'question': entry.question,
        });
      }
      return jsonEncode({
        'success': true,
        'question': entry.question,
        if (answer.selected.isNotEmpty) 'selected': answer.selected,
        if (answer.freeText != null) 'free_text': answer.freeText,
      });
    } finally {
      unregister?.call();
      registry.remove('fake', callId);
    }
  }
}

ScriptedResponse _askUserCall(String toolCallId, String argsJson) =>
    ScriptedResponse(toolCallDeltas: [
      {
        'index': 0,
        'id': toolCallId,
        'function': {'name': 'ask_user', 'arguments': argsJson},
      },
    ]);

void main() {
  group('AgentLoop ask_user 阻塞提问', () {
    test('挂起期间不进入下一轮；作答后答案作为 tool message 回灌并完成', () async {
      final registry = AskUserRegistry();
      final llm = CapturingLlmProvider([
        _askUserCall('call_1', '{"question":"用第几人称？","options":["第一","第三"]}'),
        const ScriptedResponse(contentChunks: ['好的，已按第一人称。']),
      ]);
      final scenario = _AskUserFakeScenario(registry);
      final loop = AgentLoop(llm: llm, scenario: scenario);

      final events = <AgentEvent>[];
      final run = loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: '开写')],
        systemPrompt: 'sys',
        emit: events.add,
      );

      // 等 run 挂进 ask_user；挂起期间第二轮 LLM 不应被调用
      await scenario.paused.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(llm.callCount, 1, reason: '挂起等待用户作答时不应进入下一轮 LLM 调用');
      expect(events.whereType<ToolCallStartEvent>().single.name, 'ask_user');

      // 用户作答 → run 继续
      expect(
        registry.answer(
          scenarioId: 'fake',
          toolCallId: 'call_1',
          selected: ['第一'],
        ),
        isTrue,
      );
      await run.timeout(const Duration(seconds: 5));

      expect(events.last, isA<AgentDoneEvent>());
      expect(llm.callCount, 2);

      // 第二轮 LLM 看到的 messages：tool 结果含所选答案
      final secondRound = llm.receivedMessages[1];
      final toolMsg = secondRound
          .where((m) => m.role == 'tool' && m.toolCallId == 'call_1')
          .single;
      final result = jsonDecode(toolMsg.content!) as Map<String, dynamic>;
      expect(result['selected'], ['第一']);
      expect(result['success'], true);

      // UI 侧：ToolCallEndEvent 成功收尾
      final endEvents = events.whereType<ToolCallEndEvent>().toList();
      expect(endEvents, isNotEmpty);
      expect(endEvents.last.success, isTrue);
    });

    test('挂起中取消令牌：挂起项被放行为 cancelled，run 及时结束不悬挂', () async {
      final registry = AskUserRegistry();
      final token = CancellationToken();
      final llm = CapturingLlmProvider([
        _askUserCall('call_1', '{"question":"要继续吗？"}'),
      ]);
      final scenario = _AskUserFakeScenario(registry, token);
      final loop = AgentLoop(llm: llm, scenario: scenario);

      final events = <AgentEvent>[];
      final run = loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: '开写')],
        systemPrompt: 'sys',
        emit: events.add,
        cancellationToken: token,
      );

      await scenario.paused.future;
      token.cancel(reason: '用户主动取消');

      // 关键断言：run 能在超时内返回（取消回调唤醒了挂起的 executeTool，
      // loop 在下一检查点退出），而不是永久卡在 await 上
      await run.timeout(const Duration(seconds: 5));
      expect(events.last, isA<AgentDoneEvent>());
      expect(registry.pendingCount, 0);
      expect(llm.callCount, 1, reason: '取消后不应再发起下一轮 LLM 调用');
    });
  });
}

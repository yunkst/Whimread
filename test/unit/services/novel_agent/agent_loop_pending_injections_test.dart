/// AgentLoop 运行中补充消息（注入）测试
///
/// 验证 [AgentLoop.run] 的 `pendingInjections` 回调：
/// - 每轮 LLM 调用前 drain 队列，append 到 messages
/// - 同一回调被多次调用也能正确 drain（多轮）
/// - 空队列时不影响正常 ReAct
/// - 注入内容被 LLM 在本轮看到（messages 已包含注入文本）
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/utils/cancellation_token.dart';
import '../../../helpers/fake_agent_scenario.dart';
import '../../../helpers/noop_llm_http_client.dart';

/// 记录 LLM 调用时收到 messages 的内容（用于断言"注入已生效"）
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
    // 深拷贝记录，避免循环引用（这里 messages 顶层只含 ChatMessage，不含 callable）
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

class _FakeScenario extends BaseFakeAgentScenario {
  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  String buildSystemPrompt(AgentScenarioContext context) => 'sys';

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
  group('AgentLoop pendingInjections', () {
    test('空队列：正常 ReAct 完成', () async {
      final llm = CapturingLlmProvider([
        const ScriptedResponse(contentChunks: ['hi']),
      ]);
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());

      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hello')],
        systemPrompt: 'sys',
        emit: events.add,
        pendingInjections: () => const <String>[],
      );

      expect(events.last, isA<AgentDoneEvent>());
      expect(llm.callCount, 1);
    });

    test('注入单条消息：本轮 LLM 看到', () async {
      final llm = CapturingLlmProvider([
        const ScriptedResponse(contentChunks: ['看到了补充']),
      ]);
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());

      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: '首条')],
        systemPrompt: 'sys',
        emit: events.add,
        // 第一轮前注入一条 user
        pendingInjections: () => ['补充的 user 文本'],
      );

      expect(events.last, isA<AgentDoneEvent>());
      expect(llm.callCount, 1);

      // 断言：LLM 收到的 messages 包含补充 user
      final msgs = llm.receivedMessages.first;
      final roles = msgs.map((m) => '${m.role}:${m.content}').toList();
      expect(
        roles,
        contains('user:首条'),
        reason: '初始 user 应在 messages 里',
      );
      expect(
        roles,
        contains('user:补充的 user 文本'),
        reason: '注入的 user 应在本轮 LLM 调用前出现在 messages 里',
      );
      expect(
        roles.indexOf('user:补充的 user 文本'),
        greaterThan(roles.indexOf('user:首条')),
        reason: '补充消息应排在初始 user 之后（drain 在 initialMessages 之后追加）',
      );
    });

    test('注入多条消息：按返回顺序追加', () async {
      final llm = CapturingLlmProvider([
        const ScriptedResponse(contentChunks: ['ok']),
      ]);
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());

      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: '首条')],
        systemPrompt: 'sys',
        emit: events.add,
        pendingInjections: () => ['补充A', '补充B', '补充C'],
      );

      expect(llm.callCount, 1);
      final msgs = llm.receivedMessages.first;
      final userContents = msgs
          .where((m) => m.role == 'user')
          .map((m) => m.content)
          .toList();
      expect(
        userContents,
        ['首条', '补充A', '补充B', '补充C'],
        reason: '注入消息按队列顺序追加到末尾，保持 FIFO',
      );
    });

    test('drain 在多轮间反复触发（回调每次都被调）', () async {
      // 验证：第 1 轮后队列注入新内容，第 2 轮 LLM 应看到
      final llm = CapturingLlmProvider([
        const ScriptedResponse(
          contentChunks: ['第一轮'],
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'noop', 'arguments': ''},
            },
          ],
        ),
        const ScriptedResponse(contentChunks: ['看到了']),
      ]);

      final scenario = _FakeScenario()..id;
      final loop = AgentLoop(llm: llm, scenario: scenario);

      // 用一个共享队列模拟：第 1 轮前空，第 1 轮 LLM 调用后填入新消息
      final queue = <String>[];
      int drainCount = 0;

      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: '首条')],
        systemPrompt: 'sys',
        emit: events.add,
        pendingInjections: () {
          drainCount++;
          if (drainCount == 2) {
            // 第 2 轮前填入
            return ['第二轮前注入'];
          }
          return const <String>[];
        },
      );

      expect(llm.callCount, 2);
      // 第 2 轮 LLM 调用收到的 messages 应含"第二轮前注入"
      final secondRoundMsgs = llm.receivedMessages[1];
      final userContents = secondRoundMsgs
          .where((m) => m.role == 'user')
          .map((m) => m.content)
          .toList();
      expect(userContents, contains('第二轮前注入'));
    });

    test('空字符串注入：被过滤（trim 后空）', () async {
      final llm = CapturingLlmProvider([
        const ScriptedResponse(contentChunks: ['ok']),
      ]);
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());

      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: '首条')],
        systemPrompt: 'sys',
        emit: events.add,
        pendingInjections: () => ['', '   ', '实际内容'],
      );

      final msgs = llm.receivedMessages.first;
      final userContents = msgs
          .where((m) => m.role == 'user')
          .map((m) => m.content)
          .toList();
      // 应只剩 2 条 user（首条 + 实际内容），空串被 trim 过滤
      expect(userContents.length, 2);
      expect(userContents, ['首条', '实际内容']);
    });

    test('pendingInjections 为 null：不抛错，按无注入处理', () async {
      final llm = CapturingLlmProvider([
        const ScriptedResponse(contentChunks: ['ok']),
      ]);
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());

      // 子 Agent 场景：传 null（不传 pendingInjections）
      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hello')],
        systemPrompt: 'sys',
        emit: events.add,
        // 不传 pendingInjections → 退化为无注入（子 Agent 行为）
      );

      expect(events.last, isA<AgentDoneEvent>());
      expect(llm.callCount, 1);
    });

    test('cancel 路径下注入不会被处理（检查点 A 先 cancel → return）', () async {
      // 验证：cancellationToken 先 cancel → loop return → 即使回调返回
      // 内容也不会被加入 messages（因为根本没进 try 块的 drain 分支）。
      final llm = CapturingLlmProvider(const []);
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());
      final token = CancellationToken()..cancel(reason: '预取消');

      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hello')],
        systemPrompt: 'sys',
        emit: events.add,
        cancellationToken: token,
        pendingInjections: () {
          // 永远不会被调用（因为检查点 A 已 cancel，drain 不执行）
          return ['不会注入'];
        },
      );

      expect(llm.callCount, 0, reason: '预取消时不应调 LLM');
      expect(events.last, isA<AgentDoneEvent>());
    });
  });
}

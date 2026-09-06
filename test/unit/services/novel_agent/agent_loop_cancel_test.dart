/// AgentLoop 取消语义单元测试
///
/// 验证 [AgentLoop.run] 接收 [CancellationToken] 后的温和取消行为：
/// - 检查点 A：进入新一轮前取消 → 立即结束，不再调用 LLM
/// - 检查点 B：本轮 LLM 输出完后取消 → 不执行工具、不进入下一轮（核心诉求）
/// - 检查点 C：批量工具执行中取消 → 跳过剩余工具
/// - 未取消时正常多轮 ReAct 完成
///
/// 通过 FakeLlmProvider + FakeAgentScenario 隔离真实 LLM/HTTP/DB 依赖。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/novel_agent/agent_loop_cancel_test.dart
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

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// 按预设脚本返回流式响应的假 LLM Provider
///
/// 每调用一次 [chatStreamWithTools]，消费一条 [ScriptedResponse]。
/// 可通过 [delay] 模拟流式耗时，便于测试在输出过程中/后取消。
class FakeLlmProvider extends LlmProvider {
  FakeLlmProvider()
      : super(const LlmConfig(
          baseUrl: 'http://localhost',
          apiKey: 'test',
          defaultModel: 'test-model',
        ), httpClient: NoopLlmHttpClient());

  final List<ScriptedResponse> _script = [];
  int callCount = 0;

  void enqueue(ScriptedResponse response) => _script.add(response);

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
      throw StateError('FakeLlmProvider 脚本已耗尽');
    }
    final resp = _script.removeAt(0);
    if (resp.delay != null) {
      await Future<void>.delayed(resp.delay!);
    }
    for (final chunk in resp.contentChunks) {
      yield LlmStreamChunk(contentChunk: chunk);
      if (resp.delay != null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
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
  final Duration? delay;

  const ScriptedResponse({
    this.contentChunks = const [],
    this.toolCallDeltas,
    this.delay,
  });
}

/// 记录工具调用、可注入延时的假场景
class FakeAgentScenario extends BaseFakeAgentScenario {
  @override
  final String id = 'fake';

  @override
  final String displayName = 'Fake Scenario';

  /// 每次工具执行前的延时（模拟慢工具）
  final Duration? toolDelay;

  /// 已执行的工具调用记录（name, args）
  final List<({String name, Map<String, dynamic> args})> executed = [];

  /// 自定义工具结果，key=工具名；未配置则返回 {"ok": true}
  final Map<String, Map<String, dynamic>> toolResults = {};

  /// Completer 列表，工具执行时若非空则等待对应 completer（用于精确控制时序）
  final List<Completer<void>> toolGateCompleters = [];

  FakeAgentScenario({this.toolDelay});

  @override
  String buildSystemPrompt(AgentScenarioContext context) => 'system-prompt';

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    if (toolDelay != null) {
      await Future<void>.delayed(toolDelay!);
    }
    executed.add((name: name, args: Map<String, dynamic>.from(args)));
    final result = toolResults[name] ?? {'ok': true};
    return jsonEncodeHelper(result);
  }
}

String jsonEncodeHelper(Map<String, dynamic> m) {
  // 简单 JSON 编码（避免顶层 import 冲突）
  return _encode(m);
}

String _encode(Object? v) {
  if (v == null) return 'null';
  if (v is String) return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  if (v is num || v is bool) return '$v';
  if (v is List) {
    return '[${v.map(_encode).join(',')}]';
  }
  if (v is Map) {
    return '{${v.entries.map((e) => '"${e.key}":${_encode(e.value)}').join(',')}}';
  }
  return '"$v"';
}

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

Future<List<AgentEvent>> runLoop(
  AgentLoop loop, {
  CancellationToken? token,
}) async {
  final events = <AgentEvent>[];
  await loop.run(
    initialMessages: [const ChatMessage(role: 'user', content: 'hello')],
    systemPrompt: 'system-prompt',
    emit: events.add,
    cancellationToken: token,
  );
  return events;
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

void main() {
  group('AgentLoop 取消语义', () {
    test('未传入 token 时正常多轮 ReAct 完成', () async {
      final llm = FakeLlmProvider()
        ..enqueue(const ScriptedResponse(
          contentChunks: ['正在'],
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'list_novels', 'arguments': ''},
            },
          ],
        ))
        ..enqueue(const ScriptedResponse(
          contentChunks: ['已', '完成'],
        ));
      final scenario = FakeAgentScenario();
      final loop = AgentLoop(llm: llm, scenario: scenario);

      final events = await runLoop(loop);

      expect(llm.callCount, 2, reason: '应执行 2 轮 LLM 调用');
      expect(scenario.executed.length, 1, reason: '应执行 1 次工具');
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('检查点 A：进入新一轮前已取消 → 不再调用 LLM', () async {
      final llm = FakeLlmProvider()
        ..enqueue(const ScriptedResponse(
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'list_novels', 'arguments': ''},
            },
          ],
        ))
        // 第二轮永远不会被调用
        ..enqueue(const ScriptedResponse(contentChunks: ['不该出现']));

      final scenario = FakeAgentScenario();
      final loop = AgentLoop(llm: llm, scenario: scenario);
      final token = CancellationToken()..cancel(reason: '测试预先取消');

      final events = await runLoop(loop, token: token);

      expect(llm.callCount, 0, reason: '预先取消时不应调用 LLM');
      expect(scenario.executed, isEmpty);
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('检查点 B：本轮 LLM 输出完后取消 → 不执行工具、不进入下一轮', () async {
      // 这是核心测试：满足"让 agent 输出完，但不继续下一个循环"
      final llm = FakeLlmProvider()
        ..enqueue(const ScriptedResponse(
          contentChunks: ['第一', '轮', '完整', '输出'],
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'list_novels', 'arguments': ''},
            },
          ],
        ))
        // 第二轮（本应被触发）的响应，取消后不应被消费
        ..enqueue(const ScriptedResponse(contentChunks: ['不该出现']));

      final scenario = FakeAgentScenario();
      final loop = AgentLoop(llm: llm, scenario: scenario);
      final token = CancellationToken();

      // 用一个带 gate 的变体：本轮 LLM 输出完后触发取消
      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: [const ChatMessage(role: 'user', content: 'hello')],
        systemPrompt: 'system-prompt',
        emit: (e) {
          events.add(e);
          // 收到第一个 TextDelta 后即取消，但本轮仍会输出完
          if (e is TextDeltaEvent && !token.isCancelled) {
            token.cancel(reason: '本轮输出后停止');
          }
        },
        cancellationToken: token,
      );

      final textEvents = events.whereType<TextDeltaEvent>().toList();
      final fullText = textEvents.map((e) => e.text).join();

      expect(llm.callCount, 1, reason: '只应调用 1 次 LLM（本轮输出完），不进第二轮');
      expect(scenario.executed, isEmpty, reason: '取消后不应执行工具');
      expect(fullText, '第一轮完整输出', reason: '本轮 LLM 输出应完整保留');
      expect(events.last, isA<AgentDoneEvent>(), reason: '应以 Done 结束');
    });

    test('检查点 C：批量工具执行中取消 → 跳过剩余工具', () async {
      final llm = FakeLlmProvider()
        ..enqueue(const ScriptedResponse(
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'tool_a', 'arguments': ''},
            },
            {
              'index': 1,
              'id': 'call_2',
              'function': {'name': 'tool_b', 'arguments': ''},
            },
            {
              'index': 2,
              'id': 'call_3',
              'function': {'name': 'tool_c', 'arguments': ''},
            },
          ],
        ));

      final scenario = FakeAgentScenario(
        // 每个工具执行前等待，给取消留时间窗
        toolDelay: const Duration(milliseconds: 20),
      );
      final token = CancellationToken();

      // 第一个工具执行完后立即取消
      final events = <AgentEvent>[];
      final firstToolDone = Completer<void>();

      // 包装 scenario 以便在首次工具执行后通知（精确命中检查点 C）
      final wrappedScenario = _CancelAfterFirstToolScenario(
        inner: scenario,
        token: token,
        onFirstExecuted: () => firstToolDone.complete(),
      );
      final loop2 = AgentLoop(llm: llm, scenario: wrappedScenario);

      final runFuture = loop2.run(
        initialMessages: [const ChatMessage(role: 'user', content: 'hello')],
        systemPrompt: 'system-prompt',
        emit: events.add,
        cancellationToken: token,
      );

      // 等首个工具执行完，再取消（精确命中检查点 C）
      await firstToolDone.future;
      token.cancel(reason: '工具执行中途取消');

      await runFuture;

      expect(llm.callCount, 1, reason: '只在第一轮调用了 LLM');
      expect(scenario.executed.length, lessThan(3),
          reason: '中途取消后不应执行全部 3 个工具');
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('取消不会触发 maxRounds 强制总结', () async {
      // 即使已用完轮数预算前的轮次被取消，也不应进入末尾的强制总结分支
      final llm = FakeLlmProvider()
        ..enqueue(const ScriptedResponse(
          toolCallDeltas: [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'list_novels', 'arguments': ''},
            },
          ],
        ));

      final scenario = FakeAgentScenario();
      // 限制 1 轮：正常情况下会触发强制总结，但取消应优先 return
      final loop = AgentLoop(
        llm: llm,
        scenario: scenario,
        config: const AgentLoopConfig(maxRounds: 1),
      );
      final token = CancellationToken()..cancel(reason: '预取消');

      final events = await runLoop(loop, token: token);

      expect(llm.callCount, 0, reason: '预取消，LLM 根本没被调用');
      expect(scenario.executed, isEmpty);
      expect(events.last, isA<AgentDoneEvent>());
    });
  });
}

/// 在首次工具执行后触发取消的装饰场景
class _CancelAfterFirstToolScenario with AgentScenarioCleanupMixin
    implements AgentScenario {
  final AgentScenario inner;
  final CancellationToken token;
  final void Function() onFirstExecuted;
  bool _firstDone = false;

  _CancelAfterFirstToolScenario({
    required this.inner,
    required this.token,
    required this.onFirstExecuted,
  });

  @override
  String get id => inner.id;
  @override
  String get displayName => inner.displayName;
  @override
  List<Map<String, dynamic>> get tools => inner.tools;
  @override
  String buildSystemPrompt(AgentScenarioContext context) =>
      inner.buildSystemPrompt(context);

  @override
  Future<List<String>> getMemories() => inner.getMemories();

  @override
  Future<MemoryPatchResult> patchMemory(int? index, String newText) =>
      inner.patchMemory(index, newText);

  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) =>
      inner.onNoToolCalls(messages);

  @override
  Future<void> cleanup() => inner.cleanup();

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    final result = await inner.executeTool(name, args);
    if (!_firstDone) {
      _firstDone = true;
      onFirstExecuted();
    }
    return result;
  }
}

/// AgentLoop round-level 网络重试单元测试
///
/// 验证 PR2 引入的 round-level 重试：
/// - 瞬态网络错误（SocketException / RetryableHttpException / TimeoutException）
///   触发 round 重试，最终成功 → AgentDoneEvent
/// - 非瞬态错误（FormatException）→ 立即终止，emit AgentErrorEvent
/// - 超过 networkRetryPerRound → 终止
/// - 重试退避期间收到 CancellationToken → 优雅结束
///
/// 沿用 agent_loop_cancel_test.dart 的 Fake 模式，扩展 enqueue(throwMode: ...)
/// 以支持"某轮直接抛错而非 yield"。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/novel_agent/agent_loop_retry_test.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/context_compactor.dart';
import 'package:novel_app/utils/cancellation_token.dart';
import 'package:novel_app/utils/retry_helper.dart';
import '../../../helpers/fake_agent_scenario.dart';
import '../../../helpers/noop_llm_http_client.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// 可注入"抛错"脚本的假 LLM Provider
class _ScriptedErrorLlm extends LlmProvider {
  _ScriptedErrorLlm()
      : super(
          const LlmConfig(
            baseUrl: 'http://localhost',
            apiKey: 'test',
            defaultModel: 'test-model',
          ),
          httpClient: NoopLlmHttpClient(),
        );

  final List<_ScriptedItem> _script = [];
  int callCount = 0;

  /// 每次调用的 messages 快照（供断言 LLM 上下文内容）
  final List<List<ChatMessage>> calls = [];

  /// 入队一条脚本：throwMode 非 null 表示该轮直接抛错；否则按 response yield。
  /// [partialChunks] 配合 throwMode：抛错前先 yield 这些 partial 文本，
  /// 模拟"流式中途断开"（LLM 已输出部分内容后连接失败）。
  void enqueue({
    Object? throwMode,
    _ScriptedResponse? response,
    List<String> partialChunks = const [],
  }) {
    assert(
        throwMode != null || response != null, 'throwMode 与 response 至少一个非空');
    _script.add(_ScriptedItem(
      throwMode: throwMode,
      response: response,
      partialChunks: partialChunks,
    ));
  }

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
    calls.add(List.of(messages));
    if (_script.isEmpty) {
      throw StateError('_ScriptedErrorLlm 脚本已耗尽');
    }
    final item = _script.removeAt(0);
    if (item.throwMode != null) {
      // 短暂延迟模拟网络抖动后抛错（此前先流出 partial chunks）
      await Future<void>.delayed(const Duration(milliseconds: 1));
      for (final chunk in item.partialChunks) {
        yield LlmStreamChunk(contentChunk: chunk);
      }
      await Future<void>.error(item.throwMode!);
      return;
    }
    final resp = item.response!;
    for (final chunk in resp.contentChunks) {
      yield LlmStreamChunk(contentChunk: chunk);
    }
    if (resp.toolCallDeltas != null) {
      yield LlmStreamChunk(
        toolCallDeltas: resp.toolCallDeltas!,
        finishReason: resp.finishReason ?? 'tool_calls',
      );
    } else {
      yield LlmStreamChunk(finishReason: resp.finishReason ?? 'stop');
    }
  }
}

class _ScriptedItem {
  final Object? throwMode;
  final _ScriptedResponse? response;

  /// throwMode 非 null 时，抛错前先 yield 的 partial 文本
  final List<String> partialChunks;
  const _ScriptedItem({
    this.throwMode,
    this.response,
    this.partialChunks = const [],
  });
}

class _ScriptedResponse {
  final List<String> contentChunks;
  final List<Map<String, dynamic>>? toolCallDeltas;

  /// finish_reason 覆盖（默认 stop）。'length' 用于触发强制压缩路径。
  final String? finishReason;
  const _ScriptedResponse({
    this.contentChunks = const [],
    this.toolCallDeltas,
    this.finishReason,
  });
}

/// 无参可调的最小假场景
class _FakeScenario extends BaseFakeAgentScenario {
  final List<({String name, Map<String, dynamic> args})> executed = [];

  @override
  String buildSystemPrompt(AgentScenarioContext context) => 'sys';

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    executed.add((name: name, args: Map<String, dynamic>.from(args)));
    return jsonEncode({'ok': true});
  }
}

Future<List<AgentEvent>> runLoop(
  AgentLoop loop, {
  CancellationToken? token,
}) async {
  final events = <AgentEvent>[];
  await loop.run(
    initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
    systemPrompt: 'sys',
    emit: events.add,
    cancellationToken: token,
  );
  return events;
}

/// 首次 set value 时抛异常的 notifier：模拟 RetrySignals 横幅写入瞬时故障。
/// 只抛一次 —— agent_loop 对 clear() 没有守卫，持续抛会误伤正常收尾路径。
class _FailOnceNotifier extends ValueNotifier<RetryState?> {
  _FailOnceNotifier() : super(null);

  bool firstSetThrew = false;
  bool _armed = true;

  @override
  set value(RetryState? newValue) {
    if (_armed) {
      _armed = false;
      firstSetThrew = true;
      throw StateError('模拟 reportRound 阶段横幅写入故障');
    }
    super.value = newValue;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentLoop round-level 重试', () {
    test('SocketException → round 重试 → 第 2 次成功 → AgentDoneEvent', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const SocketException('连接被重置'))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['完成']),
        );
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(
          maxRounds: 5,
          // 缩短退避以提速测试
          networkRetryPerRound: 2,
        ),
      );
      final events = await runLoop(loop);
      expect(llm.callCount, 2, reason: '首次抛错 → 重试 → 第二次成功');
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('RetryableHttpException(503) → round 重试 → 成功', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const RetryableHttpException(503, 'mt', ''))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['已恢复']),
        );
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());
      final events = await runLoop(loop);
      expect(llm.callCount, 2);
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('TimeoutException → 判为瞬态 → round 重试 → 成功', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(
          throwMode: TimeoutException(
            'stream timeout',
            const Duration(milliseconds: 1),
          ),
        )
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['恢复了']),
        );
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());
      final events = await runLoop(loop);
      expect(llm.callCount, 2);
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('FormatException → 立即终止 → AgentErrorEvent，callCount=1', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const FormatException('JSON 损坏'));
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());
      final events = await runLoop(loop);
      expect(llm.callCount, 1, reason: '非瞬态错误不重试');
      expect(events.last, isA<AgentErrorEvent>());
      expect((events.last as AgentErrorEvent).error, contains('JSON 损坏'));
    });

    test('连续 3 次 SocketException → 超 networkRetryPerRound=2 → 终止', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const SocketException('x'))
        ..enqueue(throwMode: const SocketException('x'))
        ..enqueue(throwMode: const SocketException('x'));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);
      // 首次 + 2 次重试 = 3 次 LLM 调用均失败
      expect(llm.callCount, 3);
      expect(events.last, isA<AgentErrorEvent>());
    });

    test('重试退避期间收到取消 → 优雅结束（AgentDoneEvent），第 2 轮不调用', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const SocketException('x'));
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());
      final token = CancellationToken();

      final events = <AgentEvent>[];
      // 异步在短延迟后取消（在 round_retry 退避等待期间）
      final runFuture = loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: events.add,
        cancellationToken: token,
      );
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () => token.cancel(reason: '测试取消'),
      );
      await runFuture;

      expect(token.isCancelled, true);
      expect(events.last, isA<AgentDoneEvent>(),
          reason: '退避期间取消应优雅结束而非 AgentError');
      // 第 1 次抛错 → 退避等待 → 取消 → 不再调第 2 次
      expect(llm.callCount, 1);
    });

    test('重试成功后 roundRetryCount 重置（连续两轮瞬态错误均能恢复）', () async {
      // 第 1 轮：抛错 → 重试 → 成功（带 tool_call）
      // 第 2 轮（工具返回后）：抛错 → 重试 → 成功（文本结束）
      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const SocketException('round0 失败'))
        ..enqueue(
          response: const _ScriptedResponse(
            toolCallDeltas: [
              {
                'index': 0,
                'id': 'c1',
                'function': {'name': 'foo', 'arguments': '{}'},
              },
            ],
          ),
        )
        ..enqueue(throwMode: const SocketException('round1 失败'))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['最终完成']),
        );
      final scenario = _FakeScenario();
      final loop = AgentLoop(
        llm: llm,
        scenario: scenario,
        config: const AgentLoopConfig(maxRounds: 10, networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);
      // 4 次 LLM 调用：round0 失败+成功，round1 失败+成功
      expect(llm.callCount, 4);
      // 工具被调用过
      expect(scenario.executed, hasLength(1));
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('RetryableHttpException(429) → round 重试 → 成功', () async {
      // 自 2026-07-17 起所有 4xx/5xx 统一重试，429/408 只是历史最先纳入白名单的两种
      final llm = _ScriptedErrorLlm()
        ..enqueue(
            throwMode: const RetryableHttpException(
          429,
          'rate limited',
          '',
          retryAfterMs: 50,
        ))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['限流后恢复']),
        );
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);
      expect(llm.callCount, 2, reason: '429 已被 RetryableHttpException 统一兜住');
      expect(events.last, isA<AgentDoneEvent>(), reason: '最终应完成而非 AgentError');
    });

    test(
        'RetryableHttpException(408) → round 重试 → 成功（Request Timeout 同 429 路径）',
        () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(
            throwMode: const RetryableHttpException(
          408,
          'request timeout',
          '',
          retryAfterMs: 50,
        ))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['timeout 后恢复']),
        );
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
      );
      final events = await runLoop(loop);
      expect(llm.callCount, 2);
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('RetryableHttpException(400) → round 重试 → 成功（业务 4xx 也统一重试）', () async {
      // 自 2026-07-17 起所有 4xx 统一重试：这里模拟代理网关偶发 400。
      final llm = _ScriptedErrorLlm()
        ..enqueue(
            throwMode: const RetryableHttpException(
          400,
          'bad request',
          '',
          retryAfterMs: 50,
        ))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['400 后恢复']),
        );
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);
      expect(llm.callCount, 2,
          reason: '400 已被 round-level 接住，不再立即报 AgentError');
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('RetryableHttpException(401) → round 重试 → 成功（鉴权 4xx 也统一重试）', () async {
      // 模拟 token 偶发过期 → round-level 兜底重试。
      final llm = _ScriptedErrorLlm()
        ..enqueue(
            throwMode: const RetryableHttpException(
          401,
          'unauthorized',
          '',
          retryAfterMs: 50,
        ))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['鉴权后恢复']),
        );
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);
      expect(llm.callCount, 2);
      expect(events.last, isA<AgentDoneEvent>());
    });
  });

  group('Round-level 重试 + RetrySignals 接线', () {
    setUp(() => RetrySignals.instance.resetForTest());
    tearDown(() => RetrySignals.instance.resetForTest());

    test(
        'RetryableHttpException(503) → reportRound → 成功后 clear',
        () async {
      // 记录 notifier 的完整值变化历史：若 agent_loop 的 reportRound 调用
      // 被整体删掉（重试横幅静默失效），历史为空，本测试必须翻红
      final seen = <RetryState?>[];
      void listener() => seen.add(RetrySignals.instance.notifier.value);
      RetrySignals.instance.notifier.addListener(listener);
      addTearDown(
          () => RetrySignals.instance.notifier.removeListener(listener));

      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const RetryableHttpException(503, 'mt', ''))
        ..enqueue(
          response: const _ScriptedResponse(contentChunks: ['已恢复']),
        );
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(maxRounds: 5, networkRetryPerRound: 2),
      );
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: (e) {},
      );

      // 中间态：round-level reportRound 确实写入了横幅状态
      final roundStates = seen
          .whereType<RetryState>()
          .where((s) => s.level == RetryLevel.round)
          .toList();
      expect(roundStates, isNotEmpty,
          reason: '重试必须通过 RetrySignals.reportRound 写入 round 级横幅状态');
      expect(roundStates.first.attempt, 1);
      expect(roundStates.first.maxAttempts, 2);

      // loop 成功结束 → AgentDoneEvent 已 clear,横幅消失。
      expect(seen.last, isNull,
          reason: 'AgentDoneEvent 后 RetrySignals.clear()');
    });

    test('SocketException 抛尽 → AgentErrorEvent → RetrySignals.clear()',
        () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const SocketException('a'))
        ..enqueue(throwMode: const SocketException('b'))
        ..enqueue(throwMode: const SocketException('c'));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(networkRetryPerRound: 2),
      );
      // 先制造一个 active state,验证 loop 结束(AgentErrorEvent)时被 clear
      RetrySignals.instance.reportRound(
        attempt: 1,
        maxAttempts: 2,
        delayMs: 1000,
        error: const SocketException('before-loop'),
      );
      expect(RetrySignals.instance.notifier.value, isNotNull,
          reason: 'sanity: signal 在 loop 前是 active');

      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: (e) {},
      );

      expect(RetrySignals.instance.notifier.value, isNull,
          reason: 'AgentErrorEvent 后 RetrySignals.clear()');
    });

    test('成功后 AgentDoneEvent → RetrySignals.clear()', () async {
      // 同上：记录完整历史，防止 reportRound 接线被删后本测试仍绿
      final seen = <RetryState?>[];
      void listener() => seen.add(RetrySignals.instance.notifier.value);
      RetrySignals.instance.notifier.addListener(listener);
      addTearDown(
          () => RetrySignals.instance.notifier.removeListener(listener));

      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const RetryableHttpException(503, 'mt', ''))
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['ok']));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(maxRounds: 5, networkRetryPerRound: 2),
      );
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: (e) {},
      );

      expect(
        seen.any((v) => v is RetryState && v.level == RetryLevel.round),
        isTrue,
        reason: '本用例跑的是 round 级重试路径，必须观察到 reportRound 写入',
      );
      expect(seen.last, isNull,
          reason: 'AgentDoneEvent 后 RetrySignals.clear()');
    });

    test('max_rounds 退出 → RetrySignals.clear()', () async {
      // 无限输出 → 每轮无工具调用 → 触发 AgentDoneEvent → clear
      final llm = _ScriptedErrorLlm()
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['ok']));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(maxRounds: 2),
      );
      // 先制造 active signal
      RetrySignals.instance.reportRound(
        attempt: 1,
        maxAttempts: 2,
        delayMs: 100,
        error: const SocketException('before'),
      );
      expect(RetrySignals.instance.notifier.value, isNotNull);

      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: (e) {},
      );

      expect(RetrySignals.instance.notifier.value, isNull,
          reason: 'AgentDoneEvent(max_rounds) 后 RetrySignals.clear()');
    });

    test('reportRound 抛异常 → 被吞掉，重试主流程继续', () async {
      // 注入一个"首次 set 抛异常"的 notifier，让 agent_loop.dart 的
      // reportRound 调用真正抛错（此前该 catch 块覆盖率为零：没有任何
      // 手段让 RetrySignals 单例抛异常，本测试只是又一个"503 重试成功"）。
      // 只抛一次：clear() 无守卫调用，若持续抛会误伤收尾路径。
      final failingNotifier = _FailOnceNotifier();
      final original = RetrySignals.instance.notifier;
      RetrySignals.instance.notifier = failingNotifier;
      addTearDown(() => RetrySignals.instance.notifier = original);

      final llm = _ScriptedErrorLlm()
        ..enqueue(throwMode: const RetryableHttpException(503, 'mt', ''))
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['ok']));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(maxRounds: 5, networkRetryPerRound: 2),
      );
      // reportRound 抛的异常必须被 agent_loop 的 try/catch 吞掉：
      // run() 正常返回、第二次 LLM 调用成功、最终 clear 落地
      final events = await runLoop(loop);

      expect(llm.callCount, 2, reason: 'reportRound 异常后必须继续重试');
      expect(failingNotifier.firstSetThrew, isTrue,
          reason: '前置条件：notifier 的首次 set 必须真的抛过异常，否则本测试没测到 catch 块');
      expect(events.last, isA<AgentDoneEvent>());
    });
  });

  group('修复回归（contentChunks 累积 / RetryEvent / nudge / length 压缩）', () {
    test('流式中途断开 → RetryEvent.emittedChars = 本轮已流出字符数', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(
          throwMode: const SocketException('中途断开'),
          partialChunks: const ['你好', '世界'],
        )
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['完整输出']));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);

      final retry = events.whereType<RetryEvent>().single;
      expect(retry.emittedChars, '你好世界'.length,
          reason: 'partial 已流出 4 字符，session 据此截断 streamingSegments');
      expect(retry.attempt, 1);
      expect(retry.maxAttempts, 2);
      expect(retry.delayMs, greaterThan(0));
      expect(retry.errorText, contains('中途断开'));
      expect(events.last, isA<AgentDoneEvent>());
      expect(llm.callCount, 2);
    });

    test('assistant 文本随消息入栈（回归 v1.7.3 contentChunks 未累积 bug）', () async {
      // 修复前 listener 不累积 contentChunks → fullContent 恒空 →
      // assistant.content 恒 null → 多轮 ReAct 中 LLM 看不到自己说过的话
      final llm = _ScriptedErrorLlm()
        ..enqueue(
          response: const _ScriptedResponse(
            contentChunks: ['我来', '查一下'],
            toolCallDeltas: [
              {
                'index': 0,
                'id': 'c1',
                'function': {'name': 'foo', 'arguments': '{}'},
              },
            ],
          ),
        )
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['完成']));
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());
      await runLoop(loop);

      expect(llm.callCount, 2);
      // 第 2 次调用的上下文应含第 1 轮 assistant 完整文本
      final assistantMsgs = llm.calls[1]
          .where((m) =>
              m.role == 'assistant' && (m.toolCalls?.isNotEmpty ?? false))
          .toList();
      expect(assistantMsgs, hasLength(1));
      expect(assistantMsgs.single.content, '我来查一下');
    });

    test('异常空响应 → 注入一次 nudge；持续空响应不再注入 → Done', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(response: const _ScriptedResponse()) // 空响应 1 → nudge
        ..enqueue(response: const _ScriptedResponse()); // 空响应 2 → 不再 nudge
      final loop = AgentLoop(llm: llm, scenario: _FakeScenario());
      final events = await runLoop(loop);

      expect(llm.callCount, 2, reason: '第 1 次空 → nudge 续跑；第 2 次空 → Done');
      expect(events.last, isA<AgentDoneEvent>());
      // nudge user 消息恰好 1 条
      final nudges = llm.calls[1]
          .where((m) => m.role == 'user' && (m.content ?? '').contains('空内容'))
          .toList();
      expect(nudges, hasLength(1));
    });

    test('finish_reason=length + tool_calls → 下一轮强制压缩检查；'
        '无可丢内容时跳过（不 emit CompactionEvent，messages 原样）', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(
          response: const _ScriptedResponse(
            contentChunks: ['截断文本'],
            finishReason: 'length',
            toolCallDeltas: [
              {
                'index': 0,
                'id': 'c1',
                'function': {'name': 'foo', 'arguments': '{}'},
              },
            ],
          ),
        )
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['完成']));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);

      expect(llm.callCount, 2);
      expect(events.last, isA<AgentDoneEvent>());
      // 消息太少 → compact 无可丢（dropped=0 且无改写）→ 跳过：不 emit 空压缩提示
      expect(events.whereType<CompactionEvent>(), isEmpty);
      // 未压缩 → 第 2 次调用的 messages 仍含原始 user 'hi'
      expect(llm.calls[1].any((m) => m.role == 'user' && m.content == 'hi'),
          isTrue);
    });

    test('字符阈值触发压缩 → emit CompactionEvent，messages 被重组', () async {
      final llm = _ScriptedErrorLlm()
        ..enqueue(
          response: const _ScriptedResponse(
            toolCallDeltas: [
              {
                'index': 0,
                'id': 'c1',
                'function': {'name': 'foo', 'arguments': '{}'},
              },
            ],
          ),
        )
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['完成']));
      final loop = AgentLoop(
        llm: llm,
        scenario: _FakeScenario(),
        config: const AgentLoopConfig(
          // 极小字符阈值：第 2 轮 0b 必触发压缩
          compaction: CompactorConfig(maxContextChars: 1, preserveTailChars: 1),
        ),
      );
      final events = await runLoop(loop);

      expect(llm.callCount, 2);
      expect(events.whereType<CompactionEvent>(), isNotEmpty,
          reason: '超过 maxContextChars=1 应触发压缩');
      expect(events.last, isA<AgentDoneEvent>());
    });
  });

  // ========================================================================
  // P0 回归：tool 配对不变量
  //
  // 旧实现：一轮多个 tool_calls，前面的工具成功、后面的抛异常 →
  // 异常冒泡到回合级 catch → 被判瞬态 → continue 整轮重试 → messages
  // 残留 assistant(tool_calls=[c1,c2]) + tool(c1)，c2 无配套结果 →
  // 重发非法载荷被网关 400（400 又被判可重试，重试预算全部复现）。
  //
  // 修复后：工具异常在 _executeSingleTool 统一转 error JSON（不再冒泡），
  // 回合重试前另有 _repairUnpairedToolResults 兜底（覆盖 dispatch_subagent
  // Future.wait 部分失败等残余路径）。本测试锁定「每个已声明 toolCallId
  // 必有配套 tool 结果」这一不变量——旧代码在此场景必然失败。
  // ========================================================================
  group('tool 配对不变量（P0 回归）', () {
    test('一轮多工具中途异常 → 下一轮请求仍配对完整', () async {
      final llm = _ScriptedErrorLlm()
        // 第 1 轮：一次声明两个 tool_calls，第二个执行时抛瞬态网络错误
        ..enqueue(
          response: const _ScriptedResponse(
            toolCallDeltas: [
              {
                'index': 0,
                'id': 'c1',
                'function': {'name': 'ok_tool', 'arguments': '{}'},
              },
              {
                'index': 1,
                'id': 'c2',
                'function': {'name': 'boom_tool', 'arguments': '{}'},
              },
            ],
          ),
        )
        ..enqueue(response: const _ScriptedResponse(contentChunks: ['完成']));
      final loop = AgentLoop(
        llm: llm,
        scenario: _SecondToolThrowsScenario(),
        config: const AgentLoopConfig(maxRounds: 5, networkRetryPerRound: 2),
      );
      final events = await runLoop(loop);

      expect(events.last, isA<AgentDoneEvent>(),
          reason: '工具异常转 error JSON 后 LLM 应能自行收尾');

      // 不变量：最后一次请求中，每个已声明的 toolCallId 都有配套 tool 结果
      final lastMessages = llm.calls.last;
      final declared = <String>{};
      for (final m in lastMessages) {
        for (final tc in m.toolCalls ?? const <ToolCall>[]) {
          declared.add(tc.id);
        }
      }
      final answered = lastMessages
          .where((m) => m.role == 'tool' && m.toolCallId != null)
          .map((m) => m.toolCallId!)
          .toSet();
      expect(answered, containsAll(declared),
          reason: 'toolCall 缺配套 tool 结果 → OpenAI 兼容网关 400');

      // 失败工具的显式 error 结果送达 LLM（可自行纠正），成功工具结果保留
      final repaired =
          lastMessages.where((m) => m.role == 'tool' && m.toolCallId == 'c2');
      expect(repaired, isNotEmpty);
      expect(repaired.first.content, contains('execution_failed'));
      final ok =
          lastMessages.where((m) => m.role == 'tool' && m.toolCallId == 'c1');
      expect(ok, isNotEmpty);
      expect(ok.first.content, contains('"ok"'));
    });
  });
}

/// 第二个工具执行时抛瞬态网络错误：复现「一轮多工具，前一个成功、
/// 后一个异常」场景（旧实现会打破 tool 配对触发 400）。
class _SecondToolThrowsScenario extends BaseFakeAgentScenario {
  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    if (name == 'boom_tool') {
      throw const SocketException('工具执行中断');
    }
    return jsonEncode({'ok': true});
  }
}

/// AgentLoop immediate cancel 测试
///
/// 任务 21：cancelBehavior=immediate 时，收到 cancel 应立即 cancel stream
/// subscription（不等待本轮 LLM 输出完），子 Agent 秒级退出。
///
/// 与 graceful（默认）模式对比：graceful 等本轮输出完再停止（主 Agent 现有行为）。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/utils/cancellation_token.dart';
import '../../../helpers/fake_agent_scenario.dart';
import '../../../helpers/noop_llm_http_client.dart';

class _SlowLlm extends LlmProvider {
  _SlowLlm()
      : super(
          const LlmConfig(
            baseUrl: 'http://localhost',
            apiKey: 'test',
            defaultModel: 'test-model',
          ),
          httpClient: NoopLlmHttpClient(),
        );

  bool cancelled = false;

  @override
  Stream<LlmStreamChunk> chatStreamWithTools({
    required List<ChatMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
  }) async* {
    // 模拟流式：每 chunk 之间 sleep 50ms
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      yield LlmStreamChunk(contentChunk: 'chunk-$i');
    }
    yield const LlmStreamChunk(finishReason: 'stop');
  }
}

class _GatedLlm extends LlmProvider {
  _GatedLlm(this.gate)
      : super(
          const LlmConfig(
            baseUrl: 'http://localhost',
            apiKey: 'test',
            defaultModel: 'test-model',
          ),
          httpClient: NoopLlmHttpClient(),
        );

  final Completer<void> gate;
  bool cancelled = false;

  @override
  Stream<LlmStreamChunk> chatStreamWithTools({
    required List<ChatMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
  }) async* {
    // 等待外部 gate，再 yield 1 个 chunk（用于验证 cancel 时 sub.cancel
    // 能中断流，使我们不让 stream 走到自然结束）。
    await gate.future;
    yield const LlmStreamChunk(contentChunk: 'one');
    yield const LlmStreamChunk(finishReason: 'stop');
  }
}

class _NoopScenario extends BaseFakeAgentScenario {
  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async =>
      '{"ok":true}';
}

void main() {
  group('AgentLoopCancelBehavior.immediate', () {
    test('cancel 立即中断 stream subscription，秒级退出（不等待本轮输出完）',
        () async {
      final llm = _SlowLlm();
      final loop = AgentLoop(
        llm: llm,
        scenario: _NoopScenario(),
        config: const AgentLoopConfig(
          cancelBehavior: AgentLoopCancelBehavior.immediate,
        ),
      );
      final token = CancellationToken();

      // 50ms 内（流刚开始就）取消
      final start = DateTime.now();
      final runFuture = loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: (_) {},
        cancellationToken: token,
      );
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () => token.cancel(reason: '测试立即 cancel'),
      );

      await runFuture;
      final elapsed = DateTime.now().difference(start);

      // 10 个 chunk × 50ms = 500ms 才走完。立即 cancel 应在远小于此时间内退出
      expect(elapsed.inMilliseconds, lessThan(300),
          reason: 'immediate cancel 应秒级退出，不等 500ms 流走完');
    });

    test('未取消时 immediate 模式仍正常走完本轮 LLM', () async {
      final llm = _SlowLlm();
      final loop = AgentLoop(
        llm: llm,
        scenario: _NoopScenario(),
        config: const AgentLoopConfig(
          cancelBehavior: AgentLoopCancelBehavior.immediate,
        ),
      );

      final events = <AgentEvent>[];
      await loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: events.add,
      );

      // 10 个 TextDeltaEvent
      final textEvents = events.whereType<TextDeltaEvent>().toList();
      expect(textEvents.length, 10);
      expect(textEvents.first.text, 'chunk-0');
      expect(textEvents.last.text, 'chunk-9');
      expect(events.last, isA<AgentDoneEvent>());
    });

    test('cancel 时 cancel subscription：under-lying stream 不再 yield',
        () async {
      // 用 GatedLlm 验证：cancel 后即使 gate.complete() 触发，stream
      // subscription 也已被 cancel，不再 yield 出 chunk-1。
      final gate = Completer<void>();
      final llm = _GatedLlm(gate);
      final loop = AgentLoop(
        llm: llm,
        scenario: _NoopScenario(),
        config: const AgentLoopConfig(
          cancelBehavior: AgentLoopCancelBehavior.immediate,
        ),
      );
      final token = CancellationToken();

      final events = <AgentEvent>[];
      final runFuture = loop.run(
        initialMessages: const [ChatMessage(role: 'user', content: 'hi')],
        systemPrompt: 'sys',
        emit: events.add,
        cancellationToken: token,
      );

      // 让 loop 进入 await streamCompleter.future
      await Future<void>.delayed(const Duration(milliseconds: 20));
      token.cancel(reason: '测试');

      // 释放 gate，让 _GatedLlm 尝试 yield
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await runFuture;

      // 取消后 stream subscription 已被 cancel，yield 的 'one' 不应被消费
      final textEvents = events.whereType<TextDeltaEvent>().toList();
      expect(textEvents, isEmpty,
          reason: 'cancel 后 stream subscription 应已断开，'
              '即使 _GatedLlm yield chunk 也不应收到');
      expect(events.last, isA<AgentDoneEvent>());
    });
  });
}

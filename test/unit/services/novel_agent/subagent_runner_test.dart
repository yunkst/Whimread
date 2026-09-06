/// SubagentRunner 单元测试
///
/// 覆盖：
/// - 4/30 并发上限（30 拒绝、5 入队）
/// - EventTagger + SubagentStateProjector 投影行为
/// - 单个子 Agent 跑完返回 summary（mock LLM）
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/novel_agent/subagent_runner_test.dart
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/subagent_run.dart';
import 'package:novel_app/services/novel_agent/subagent_registry.dart';
import 'package:novel_app/services/novel_agent/subagent_runner.dart';
import 'package:novel_app/services/novel_agent/subagent_state_projector.dart';
import 'package:novel_app/utils/cancellation_token.dart';
import '../../../helpers/noop_llm_http_client.dart';

void main() {
  group('SubagentRunner 并发控制', () {
    test('单轮 30 个以内全部入队（不立即拒绝）', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      for (var i = 0; i < 5; i++) {
        await runner.enqueueForTest('s1',
            task: 't$i', allowedTools: const ['get_outline']);
      }
      expect(registry.countActiveBySession('s1'), 5);
    });

    test('单轮第 31 个返回 max_subagents_reached 错误', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      for (var i = 0; i < 30; i++) {
        await runner.enqueueForTest('s1',
            task: 't$i', allowedTools: const ['get_outline']);
      }
      final result = await runner.enqueueForTest('s1',
          task: 't31', allowedTools: const ['get_outline']);
      expect(result.contains('max_subagents_reached'), isTrue);
    });

    test('dispatch 空任务立即返回 missing_param 错误', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      // dispatch 路径会触发 _runOne（依赖 LLM），空任务短路在 _runOne 之前。
      // 用 dispatch 直接验证：空 task 应该立即返回错误，不进入 loop。
      final result = await runner.dispatchForTest(
        parentSessionId: 's1',
        task: '   ',
        allowedTools: const ['get_outline'],
      );
      expect(result.contains('missing_param'), isTrue);
    });
  });

  group('EventTagger', () {
    test('给 7 类 AgentEvent 都打上 runId', () {
      const runId = 'sub-xyz-1';

      final tagged1 =
          EventTagger.tag(const TextDeltaEvent('hi'), runId) as TextDeltaEvent;
      expect(tagged1.runId, runId);
      expect(tagged1.text, 'hi');

      final tagged2 = EventTagger.tag(
          const ToolCallStartEvent('get_outline', {'k': 'v'}, 'tc1'),
          runId) as ToolCallStartEvent;
      expect(tagged2.runId, runId);

      final tagged3 = EventTagger.tag(
          const ToolCallEndEvent('get_outline', 'tc1', 'result', success: true),
          runId) as ToolCallEndEvent;
      expect(tagged3.runId, runId);

      final tagged4 = EventTagger.tag(
          const ToolProgressEvent('tc1', 100),
          runId) as ToolProgressEvent;
      expect(tagged4.runId, runId);

      final tagged5 =
          EventTagger.tag(const AgentDoneEvent(), runId) as AgentDoneEvent;
      expect(tagged5.runId, runId);

      final tagged6 = EventTagger.tag(
          const AgentErrorEvent('boom'), runId) as AgentErrorEvent;
      expect(tagged6.runId, runId);
      expect(tagged6.error, 'boom');

      final tagged7 = EventTagger.tag(
          const CompactionEvent(
            removedChars: 1,
            originalChars: 2,
            compactedChars: 1,
            keptMessageCount: 3,
            droppedMessageCount: 4,
            droppedAgentFromIndex: 0,
            compactionNote: '[上下文压缩|removedChars=1|originalChars=2|compactedChars=1|rewrittenCount=0|timestamp=0]\n早期 4 条消息已被压缩移除。',
          ),
          runId) as CompactionEvent;
      expect(tagged7.runId, runId);
    });

    test('CompactionEvent.rewrittenContent 经 tag 转发不丢失（issue #11 回归）', () {
      const runId = 'sub-xyz-2';
      final tagged = EventTagger.tag(
        const CompactionEvent(
          removedChars: 1000,
          originalChars: 4000,
          compactedChars: 800,
          keptMessageCount: 6,
          droppedMessageCount: 4,
          droppedAgentFromIndex: 5,
          compactionNote:
              '[上下文压缩|removedChars=1000|originalChars=4000|compactedChars=800|rewrittenCount=1|timestamp=0]\n早期 4 条消息已被压缩移除。',
          rewrittenContent: [
            (index: 5, newContent: '[read_chapter_content dup of idx#ab12] 精简为 1-liner'),
          ],
        ),
        runId,
      ) as CompactionEvent;

      expect(tagged.runId, runId);
      expect(tagged.rewrittenContent.length, 1,
          reason: '子 Agent 压缩事件的改写记录必须随 runId 转发，'
              '否则主 session 无法把 1-liner 版落库（issue #11）');
      expect(tagged.rewrittenContent.first.index, 5);
      expect(tagged.rewrittenContent.first.newContent,
          '[read_chapter_content dup of idx#ab12] 精简为 1-liner');
    });
  });

  group('SubagentStateProjector', () {
    SubagentRun newRun() => SubagentRun(
          runId: 'sub-test-1',
          parentSessionId: 's1',
          task: 't',
          allowedTools: const [],
          toolCallId: 'tc1',
        );

    test('TextDeltaEvent 追加文本到末尾 TextSegment', () {
      final run = newRun();
      SubagentStateProjector.project(const TextDeltaEvent('hello'), run);
      SubagentStateProjector.project(const TextDeltaEvent(' world'), run);
      expect(run.chatState.streamingSegments.length, 1);
      expect(run.chatState.streamingSegments.first, isA<TextSegment>());
      expect(
          (run.chatState.streamingSegments.first as TextSegment).content,
          'hello world');
      expect(run.lastThought, 'hello world');
    });

    test('ToolCallStartEvent 追加 ToolCallSegment 并更新 lastToolName', () {
      final run = newRun();
      SubagentStateProjector.project(
          const ToolCallStartEvent('get_outline', {}, 'tc-1'), run);
      expect(run.chatState.streamingSegments.last, isA<ToolCallSegment>());
      final seg = run.chatState.streamingSegments.last as ToolCallSegment;
      expect(seg.call.name, 'get_outline');
      expect(seg.call.status, AgentToolStatus.running);
      expect(run.lastToolName, 'get_outline');
    });

    test('ToolProgressEvent 更新对应 ToolCallSegment 的 progressChars', () {
      final run = newRun();
      SubagentStateProjector.project(
          const ToolCallStartEvent('create_chapter', {}, 'tc-1'), run);
      SubagentStateProjector.project(
          const ToolProgressEvent('tc-1', 250), run);
      final seg = run.chatState.streamingSegments.last as ToolCallSegment;
      expect(seg.call.progressChars, 250);
    });

    test('ToolCallEndEvent 标记 ToolCallSegment 为 completed/error', () {
      final run = newRun();
      SubagentStateProjector.project(
          const ToolCallStartEvent('get_outline', {}, 'tc-1'), run);
      SubagentStateProjector.project(
          const ToolCallEndEvent('get_outline', 'tc-1', 'ok', success: true),
          run);
      final seg = run.chatState.streamingSegments.last as ToolCallSegment;
      expect(seg.call.status, AgentToolStatus.completed);
      expect(seg.call.result, 'ok');
    });

    test('TextDelta 在 ToolCall 之间会新建 TextSegment', () {
      final run = newRun();
      SubagentStateProjector.project(const TextDeltaEvent('思考'), run);
      SubagentStateProjector.project(
          const ToolCallStartEvent('get_outline', {}, 'tc-1'), run);
      SubagentStateProjector.project(const TextDeltaEvent('结果说明'), run);
      // [TextSegment('思考'), ToolCallSegment, TextSegment('结果说明')]
      expect(run.chatState.streamingSegments.length, 3);
      expect(run.chatState.streamingSegments.first, isA<TextSegment>());
      expect(run.chatState.streamingSegments[1], isA<ToolCallSegment>());
      expect(run.chatState.streamingSegments.last, isA<TextSegment>());
    });

    test('AgentDoneEvent 把 streamingSegments 落到 messages 并清空', () {
      final run = newRun();
      SubagentStateProjector.project(const TextDeltaEvent('答'), run);
      SubagentStateProjector.project(const AgentDoneEvent(), run);
      expect(run.chatState.streamingSegments, isEmpty);
      expect(run.chatState.messages.length, 1);
      expect(run.chatState.messages.first.role, AgentChatRole.assistant);
    });

    test('AgentErrorEvent 落为 user 消息（标注错误）', () {
      final run = newRun();
      SubagentStateProjector.project(const AgentErrorEvent('boom'), run);
      expect(run.chatState.streamingSegments, isEmpty);
      expect(run.chatState.messages.length, 1);
      expect(run.chatState.messages.first.role, AgentChatRole.user);
      final text = (run.chatState.messages.first.segments.first as TextSegment)
          .content;
      expect(text.contains('boom'), isTrue);
    });

    test('CompactionEvent 不改变 chatState（无操作）', () {
      final run = newRun();
      SubagentStateProjector.project(const TextDeltaEvent('内容'), run);
      SubagentStateProjector.project(
          const CompactionEvent(
            removedChars: 1,
            originalChars: 2,
            compactedChars: 1,
            keptMessageCount: 1,
            droppedMessageCount: 1,
            droppedAgentFromIndex: 0,
            compactionNote: '[上下文压缩|removedChars=1|originalChars=2|compactedChars=1|rewrittenCount=0|timestamp=0]\n早期 1 条消息已被压缩移除。',
          ),
          run);
      // streamingSegments 保持不变
      expect(run.chatState.streamingSegments.length, 1);
    });
  });

  group('SubagentRunner._buildResultJson', () {
    test('completed 返回 success + summary', () {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      final run = registry.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const [],
      );
      run.state = SubagentRunState.completed;
      run.finalSummary = '## 最终结论\n完成。';
      final json = runner.buildResultJsonForTest(run);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['success'], true);
      expect(decoded['summary'], '## 最终结论\n完成。');
      expect(decoded['runId'], run.runId);
    });

    test('failed 返回 subagent_failed', () {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      final run = registry.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const [],
      );
      run.state = SubagentRunState.failed;
      run.errorMessage = 'oops';
      final json = runner.buildResultJsonForTest(run);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['error'], 'subagent_failed');
      expect(decoded['message'], 'oops');
    });

    test('cancelled 返回 cancelled', () {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      final run = registry.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const [],
      );
      run.state = SubagentRunState.cancelled;
      final json = runner.buildResultJsonForTest(run);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['error'], 'cancelled');
    });
  });

  group('SubagentRunner.cancelAllForSession', () {
    test('级联取消未终态 run 的 tokenSource', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      final r1 = registry.create(
          parentSessionId: 's1', task: 't1', allowedTools: const []);
      final r2 = registry.create(
          parentSessionId: 's1', task: 't2', allowedTools: const []);
      r1.state = SubagentRunState.running;
      r1.token = CancellationToken();
      r2.state = SubagentRunState.completed; // 已终态，不应再取消

      await runner.cancelAllForSession('s1');

      expect(r1.token!.isCancelled, isTrue);
    });

    test('cancel 后 await 返回时所有活跃 run 已终止（done 已 complete）', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      final r1 = registry.create(
          parentSessionId: 's1', task: 't1', allowedTools: const []);
      final r2 = registry.create(
          parentSessionId: 's1', task: 't2', allowedTools: const []);
      r1.state = SubagentRunState.running;
      r1.token = CancellationToken();
      r2.state = SubagentRunState.running;
      r2.token = CancellationToken();

      // 模拟子 Agent 收到 cancel 后 done 完成
      Future<void>.delayed(const Duration(milliseconds: 10), () {
        r1.state = SubagentRunState.cancelled;
        r1.completeDone();
        r2.state = SubagentRunState.cancelled;
        r2.completeDone();
      });

      await runner.cancelAllForSession('s1');

      expect(r1.isDone, isTrue);
      expect(r2.isDone, isTrue);
      expect(r1.isTerminal, isTrue);
      expect(r2.isTerminal, isTrue);
    });

    test('无活跃 run 时 cancelAllForSession 立即返回', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      // 没有创建任何 run
      await runner.cancelAllForSession('s-empty');
      // 不抛错、不卡死
    });

    test('run done 永远不完成时 cancelAllForSession 15s 超时兜底（不抛错）', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      final r1 = registry.create(
          parentSessionId: 's1', task: 't1', allowedTools: const []);
      r1.state = SubagentRunState.running;
      r1.token = CancellationToken();
      // 故意不调用 r1.completeDone()，模拟"工具执行卡死 / 路径异常"
      // 这里用 1s 短超时做测试，避免真等 15s
      // 实际兜底时间是常量 Duration(seconds: 15)
      await runner.cancelAllForSession('s1', doneTimeout: const Duration(seconds: 1));
      // 超时后 r1.isDone 仍为 false（未完成），但 cancelAllForSession 不抛错
      expect(r1.isDone, isFalse);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('pending 子 Agent 在 cancelAllForSession 时被标记为 cancelled', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(registry: registry);
      final r1 = registry.create(
          parentSessionId: 's1', task: 't1', allowedTools: const []);
      r1.state = SubagentRunState.pending;

      await runner.cancelAllForSession('s1');

      expect(r1.state, SubagentRunState.cancelled,
          reason: 'pending 子 Agent 应被标记为 cancelled');
      expect(r1.isDone, isTrue,
          reason: 'cancelled 后 done 应立即完成');
    });
  });

  group('SubagentRunner.dispatch 端到端（mock LLM）', () {
    test('单个子 Agent 跑完返回 success + summary', () async {
      final llm = FakeSubagentLlm()
        ..enqueueResponse(const ScriptedLlmResponse(
          contentChunks: ['## 最终结论\n已完成。\n无更多内容。'],
        ));

      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(
        registry: registry,
        llmProviderFactory: (_) => llm,
      );

      // 真实 dispatch 路径：forTest 内部仍调 SubagentScenario.executeTool，
      // 但允许的工具若未被 LLM 调用，则不会真的调到 ToolExecutor。
      final result = await runner.dispatch(
        parentSessionId: 's1',
        task: '分析大纲',
        allowedTools: const ['get_outline'],
        parentToolCallId: 'parent-tc-1',
      );

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['success'], isTrue,
          reason: '应返回 success=true，实际: $result');
      expect((decoded['summary'] as String).contains('最终结论'), isTrue,
          reason: 'summary 应含「最终结论」，实际: $result');
      expect(decoded['runId'], isNotNull);

      // 验证子 Agent 的 run 状态符合预期
      final runs = registry.listForSession('s1');
      expect(runs.length, 1);
      expect(runs.first.state, SubagentRunState.completed);
      expect(runs.first.chatState.messages, isNotEmpty);
    });

    test('同轮 5 个 dispatch（4 槽 + 1 排队）按 FIFO 顺序启动', () async {
      // 验证修复 1：Completer 队列版并发控制
      // - 5 个 dispatch 同时派发（Future.wait）
      // - 前 4 个立即进入 running（_runOne 调度）
      // - 第 5 个排队等待，前 4 个中任一完成时自动唤起
      //
      // 用 GateLlm 控制 LLM 完成时序：前 4 个 LLM 各持有 completer 不结束，
      // 直到测试主动 complete 第 1 个，验证第 5 个随后被唤起。
      final llm = GateSubagentLlm();
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(
        registry: registry,
        llmProviderFactory: (_) => llm,
      );

      final futures = <Future<String>>[];
      for (var i = 0; i < 5; i++) {
        futures.add(runner.dispatch(
          parentSessionId: 's1',
          task: 'task-$i',
          allowedTools: const [],
          parentToolCallId: 'parent-tc-$i',
        ));
      }

      // 让 sync 部分（create + 入队）全部跑完
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 前 4 个 run 应处于 running（GateSubagentLlm 已被调用 4 次）
      // 第 5 个应处于 pending（等待 completer）
      final runs = registry.listForSession('s1');
      expect(runs, hasLength(5));
      final runningCount =
          runs.where((r) => r.state == SubagentRunState.running).length;
      final pendingCount =
          runs.where((r) => r.state == SubagentRunState.pending).length;
      expect(runningCount, 4, reason: '前 4 个应立即 running');
      expect(pendingCount, 1, reason: '第 5 个应 pending 等待槽位');
      expect(llm.callCount, 4, reason: '只有前 4 个调了 LLM');

      // 释放第 1 个 LLM gate → 第 1 个 run 完成 → _releaseSlot 唤起第 5 个
      llm.release(0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 第 5 个应已被唤起进入 running
      expect(llm.callCount, 5, reason: '第 5 个应已调 LLM');
      final pendingAfter =
          registry.listForSession('s1').where((r) => r.state == SubagentRunState.pending).length;
      expect(pendingAfter, 0, reason: '不应再有 pending 的 run');

      // 清理：释放剩余 gate 让所有 dispatch 完成
      for (var i = 1; i < 5; i++) {
        llm.release(i);
      }
      await Future.wait(futures);

      // 全部应完成
      final allCompleted = registry.listForSession('s1').every(
          (r) => r.state == SubagentRunState.completed);
      expect(allCompleted, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// 端到端测试专用 fake
// ---------------------------------------------------------------------------

/// 复用现有 FakeLlmProvider 范式：override chatStreamWithTools 不发真实请求。
class FakeSubagentLlm extends LlmProvider {
  FakeSubagentLlm()
      : super(
          const LlmConfig(
            baseUrl: 'http://localhost',
            apiKey: 'test',
            defaultModel: 'test-model',
          ),
          httpClient: NoopLlmHttpClient(),
        );

  final List<ScriptedLlmResponse> _script = [];
  int callCount = 0;

  void enqueueResponse(ScriptedLlmResponse resp) => _script.add(resp);

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
      throw StateError('FakeSubagentLlm 脚本已耗尽');
    }
    final resp = _script.removeAt(0);
    for (final chunk in resp.contentChunks) {
      yield LlmStreamChunk(contentChunk: chunk);
    }
    yield const LlmStreamChunk(finishReason: 'stop');
  }
}

class ScriptedLlmResponse {
  final List<String> contentChunks;
  final List<Map<String, dynamic>>? toolCallDeltas;
  const ScriptedLlmResponse({
    this.contentChunks = const [],
    this.toolCallDeltas,
  });
}

/// 可控时序的子 Agent LLM：每次 chatStreamWithTools 调用挂起在 completer 上，
/// 直到测试调用 [release]。
///
/// 用途：精确控制子 Agent 完成的相对顺序，验证 FIFO 唤醒语义
/// （第 5 个 dispatch 在前 N 个完成时依次唤起）。
class GateSubagentLlm extends LlmProvider {
  GateSubagentLlm()
      : super(
          const LlmConfig(
            baseUrl: 'http://localhost',
            apiKey: 'test',
            defaultModel: 'test-model',
          ),
          httpClient: NoopLlmHttpClient(),
        );

  final List<Completer<void>> _gates = [];
  int callCount = 0;

  /// 释放第 [index] 个 LLM 调用的 gate（0-based），让该子 Agent 完成。
  void release(int index) {
    while (_gates.length <= index) {
      _gates.add(Completer<void>());
    }
    if (!_gates[index].isCompleted) {
      _gates[index].complete();
    }
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
    final myIndex = callCount - 1;
    while (_gates.length <= myIndex) {
      _gates.add(Completer<void>());
    }
    await _gates[myIndex].future;
    yield const LlmStreamChunk(contentChunk: 'ok', finishReason: 'stop');
  }
}

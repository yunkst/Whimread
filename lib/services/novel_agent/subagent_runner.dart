/// 子 Agent 运行调度器
///
/// 职责：
/// - 4 并发 + 30 排队上限（按 parentSessionId 隔离计数）
/// - 起子 AgentLoop，emit 包装打 runId
/// - 聚合子 Agent AgentChatState（供详情页）
/// - 提取 finalSummary 返回给主 Agent
///
/// 并发模型：同一 parentSessionId 内，running < 4 立即启动，
/// 4 ≤ total ≤ 29 入队 FIFO，total ≥ 30 立即返回 max_subagents_reached。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger_service.dart';
import '../dsl_engine/llm_provider.dart';
import '../../utils/cancellation_token.dart';
import '../../core/providers/services/ai_service_providers.dart';
import '../../core/providers/agent_chat_state.dart';
import '../../models/agent_chat_message.dart';
import 'agent_event.dart';
import 'agent_loop.dart';
import 'agent_scenario.dart';
import 'novel_agent_service.dart';
import 'subagent_registry.dart';
import 'subagent_scenario.dart';
import 'subagent_run.dart';
import 'subagent_state_projector.dart';
import 'tool_executor.dart';

class SubagentRunner {
  static const int maxConcurrent = 4;
  static const int maxQueue = 30;

  final Ref ref;
  final SubagentRegistry registry;

  /// 主 Agent 服务：用于把打标后事件直接发到全局流。
  ///
  /// 决策 1：子 Agent 事件不再依赖 emitParent 转发，
  /// 直接 `agentService.events.add(tagged)` 走全局流（主 session 已订阅）。
  final NovelAgentService agentService;

  /// LLM Provider 工厂覆盖（仅测试用）。
  ///
  /// 非空时 [dispatch] 用本工厂构造 LLM；为 null 走 [_buildLlmForScenario] 默认链路。
  final LlmProvider Function(String scenarioId)? _llmProviderFactoryOverride;

  /// 按 sessionId 隔离的 FIFO 等待队列：超 [maxConcurrent] 的 dispatch 在此排队。
  ///
  /// 每个 entry 是一个 [Completer]，[_runOne] 完成后在 finally 调 [_releaseSlot]
  /// 按 FIFO 唤起下一个等待者。替代旧版 50ms 轮询 + 5 分钟 TimeoutException：
  /// 无 busy-wait、无超时防御、确定性 FIFO。
  final Map<String, List<Completer<void>>> _waitingQueues = {};

  SubagentRunner({
    required this.ref,
    required this.registry,
    required this.agentService,
    LlmProvider Function(String scenarioId)? llmProviderFactory,
  }) : _llmProviderFactoryOverride = llmProviderFactory;

  /// 测试用工厂：注入 [registry] + 可选 [agentService]，不依赖完整 [Ref]。
  ///
  /// - 不传 [agentService] 时自动构造一个 NovelAgentService(_ThrowRef())：
  ///   NovelAgentService 构造只创建 broadcast 流，不立即触发 ref 调用；
  ///   forTest 路径若意外走到 sendMessage / resumeFromMessages 会抛 StateError，
  ///   但 `_onSubagentEvent` 直接 events.add 不会触发 ref。
  /// - 测试如需注入 mock LLM 走真实 [dispatch] 链路，可传 [llmProviderFactory]。
  factory SubagentRunner.forTest({
    required SubagentRegistry registry,
    NovelAgentService? agentService,
    LlmProvider Function(String scenarioId)? llmProviderFactory,
  }) {
    return SubagentRunner(
      ref: _ThrowRef(),
      registry: registry,
      agentService: agentService ?? NovelAgentService(_ThrowRef()),
      llmProviderFactory: llmProviderFactory,
    );
  }

  /// 入队一个子任务。
  ///
  /// 超过 [maxQueue] 立即返回错误 JSON；否则返回 run 后的结果 JSON。
  /// 调用方通常是主 Agent 的 WritingScenario.executeTool 路径，
  /// 把 [parentToolCallId] 透传。
  ///
  /// 决策 1：子 Agent 事件**直接通过 [agentService].events.add 发到全局流**，
  /// 不再依赖 emitParent 转发——主 session 已订阅 agentService.events，
  /// 子 Agent 事件能被主 session 看到。
  Future<String> dispatch({
    required String parentSessionId,
    required String task,
    required List<String> allowedTools,
    required String parentToolCallId,
    int? parentCurrentNovelId,
  }) async {
    // 单轮上限（含 running + pending）：
    // 由于 pending run 已占 _waitingQueues 中的位置，
    // countActiveBySession 会自然把它们计入（state 不变）。
    if (registry.countActiveBySession(parentSessionId) >= maxQueue) {
      LoggerService.instance.w(
        'dispatch_subagent 拒绝：已达单轮上限 $maxQueue (session=$parentSessionId)',
        category: LogCategory.ai,
        tags: ['agent', 'subagent', 'max_reached'],
      );
      return jsonEncode({
        'error': 'max_subagents_reached',
        'message': '当前已有 $maxQueue 个子 Agent 在跑或排队，请等其中一些完成后再派。',
      });
    }

    final run = registry.create(
      parentSessionId: parentSessionId,
      task: task,
      allowedTools: allowedTools,
      toolCallId: parentToolCallId,
    );

    if (task.trim().isEmpty) {
      run.state = SubagentRunState.failed;
      run.errorMessage = 'task 不能为空';
      LoggerService.instance.w(
        'dispatch_subagent 拒绝：task 为空 (session=$parentSessionId)',
        category: LogCategory.ai,
        tags: ['agent', 'subagent', 'empty_task'],
      );
      return jsonEncode({'error': 'missing_param', 'message': 'task 不能为空'});
    }

    // 并发控制（Completer 队列版）：
    // - count 包含本次新建的 run（同 session 内 pending + running）
    // - ≤ maxConcurrent 立即放行（Dart 单线程 + sync create/check 原子，前 N 个依次放行）
    // - 超 maxConcurrent 入队 FIFO，等待前序 run 完成时 [_releaseSlot] 唤起
    Completer<void>? waiter;
    if (registry.countActiveBySession(parentSessionId) > maxConcurrent) {
      waiter = Completer<void>();
      (_waitingQueues[parentSessionId] ??= <Completer<void>>[]).add(waiter);
    }

    try {
      if (waiter != null) {
        LoggerService.instance.d(
          'dispatch_subagent 排队等待槽位 (runId=${run.runId}, session=$parentSessionId, '
          'queuePos=${_waitingQueues[parentSessionId]!.length})',
          category: LogCategory.ai,
          tags: ['agent', 'subagent', 'queued'],
        );
        await waiter.future;
      }
      await _runOne(
        run,
        parentCurrentNovelId: parentCurrentNovelId,
      );
    } catch (e, stack) {
      // 异常路径兜底：避免 registry 留僵尸 run
      // 例如 LLM 抛错 / 取消 / 异常时 run 还是 pending 或 running，会导致
      // countActiveBySession 误判后续 dispatch 达 30 上限。
      if (run.state == SubagentRunState.pending ||
          run.state == SubagentRunState.running) {
        run.state = SubagentRunState.failed;
        run.errorMessage = e.toString();
      }
      LoggerService.instance.e(
        '子 Agent dispatch 失败 (runId=${run.runId}): $e',
        stackTrace: stack.toString(),
        category: LogCategory.ai,
        tags: ['agent', 'subagent', 'dispatch_error'],
      );
      // 任务 19：异常路径兜底 ensure done（_runOne 的 finally 也覆盖，但
      // 比如 LLM 构造抛错时 _runOne 根本没进，dispatch catch 提前收到）。
      run.completeDone();
      // 重新抛给主 Agent（WritingScenario.executeTool 会 catch 转 error JSON）
      rethrow;
    } finally {
      // 无论如何都要释放槽位：成功/失败/取消都让下一个 waiter 跑起来。
      _releaseSlot(parentSessionId);
    }

    return _buildResultJson(run);
  }

  /// 释放一个槽位：唤醒 FIFO 队首等待者（若存在）。
  ///
  /// 由 [_runOne] 的 finally 调用（成功/失败/取消路径都会走）。
  /// Completer 模型下无超时需求：只要有 run 终结就能推进队列。
  void _releaseSlot(String sessionId) {
    final queue = _waitingQueues[sessionId];
    if (queue == null || queue.isEmpty) {
      _waitingQueues.remove(sessionId);
      return;
    }
    final next = queue.removeAt(0);
    if (!next.isCompleted) {
      next.complete();
    }
    // 队列清空时主动清理 map，避免内存泄漏（按 session 维度）
    if (queue.isEmpty) {
      _waitingQueues.remove(sessionId);
    }
  }

  Future<void> _runOne(
    SubagentRun run, {
    int? parentCurrentNovelId,
  }) async {
    if (run.state == SubagentRunState.cancelled) {
      run.completeDone();
      return;
    }
    run.state = SubagentRunState.running;
    run.token = CancellationToken();

    try {
      final scenario = SubagentScenario(
        task: run.task,
        allowedTools: run.allowedTools,
      );
      scenario.setToolDelegate((name, args, onProgress) async {
        return _executeToolForSubagent(
            name, args, onProgress, run, parentCurrentNovelId);
      });

      final llm = await _buildLlmForScenario('writing');
      final loop = AgentLoop(
        llm: llm,
        scenario: scenario,
        config: const AgentLoopConfig(
          cancelBehavior: AgentLoopCancelBehavior.immediate,
        ),
      );

      await loop.run(
        initialMessages: [
          ChatMessage(role: 'user', content: run.task),
        ],
        systemPrompt: scenario.buildSystemPrompt(AgentScenarioContext(
          currentNovelId: parentCurrentNovelId,
        )),
        emit: (event) => _onSubagentEvent(event, run),
        cancellationToken: run.token,
      );

      run.finalSummary = _extractSummary(run.chatState);
      run.state = run.token?.isCancelled == true
          ? SubagentRunState.cancelled
          : SubagentRunState.completed;
    } catch (e, stack) {
      LoggerService.instance.e(
          '子 Agent 运行失败 (runId=${run.runId}): $e',
          stackTrace: stack.toString(),
          category: LogCategory.ai,
          tags: ['agent', 'subagent', 'error']);
      run.state = SubagentRunState.failed;
      run.errorMessage = e.toString();
    } finally {
      // 任务 17：终态信号（成功/失败/取消均走此路径），
      // 供 cancelAllForSession / 详情页停止按钮 await 真正退出。
      run.completeDone();
      await run.eventSub?.cancel();
      run.eventSub = null;
    }
  }

  /// 子 Agent 事件处理器：打标 + 投影 + 直接发到全局流。
  ///
  /// 决策 1：通过 [agentService.addEvent] 直接发全局流（主 session 已订阅路径），
  /// 不再依赖调用方传入 emitParent。
  void _onSubagentEvent(AgentEvent event, SubagentRun run) {
    final tagged = EventTagger.tag(event, run.runId);
    SubagentStateProjector.project(tagged, run);
    agentService.addEvent(tagged);
  }

  /// 从最终 chatState 倒序找首条非空 assistant 消息文本作为 finalSummary。
  String _extractSummary(AgentChatState state) {
    final msgs = state.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == AgentChatRole.assistant) {
        final text = msgs[i].content;
        if (text.trim().isNotEmpty) return text;
      }
    }
    return '';
  }

  String _buildResultJson(SubagentRun run) {
    switch (run.state) {
      case SubagentRunState.completed:
        return jsonEncode({
          'success': true,
          'summary': run.finalSummary ?? '',
          'runId': run.runId,
        });
      case SubagentRunState.cancelled:
        return jsonEncode({
          'error': 'cancelled',
          'message': '子 Agent 被取消。',
          'runId': run.runId,
        });
      case SubagentRunState.failed:
        return jsonEncode({
          'error': 'subagent_failed',
          'message': run.errorMessage ?? '子 Agent 运行失败',
          'runId': run.runId,
        });
      default:
        return jsonEncode({'error': 'unknown_state', 'runId': run.runId});
    }
  }

  /// 为子 Agent 构造 LlmProvider。
  ///
  /// - 默认走 [llmConfigServiceProvider] 拿 writing 场景激活配置；
  /// - 测试可通过 [_llmProviderFactoryOverride] 注入 mock provider。
  Future<LlmProvider> _buildLlmForScenario(String scenarioId) async {
    final factoryOverride = _llmProviderFactoryOverride;
    if (factoryOverride != null) {
      return factoryOverride(scenarioId);
    }
    final configService = ref.read(llmConfigServiceProvider);
    final llm = await configService.buildActiveProvider(scenarioId);
    if (llm == null) {
      throw StateError('LLM 未配置（scenarioId=$scenarioId），子 Agent 无法启动');
    }
    return llm;
  }

  Future<String> _executeToolForSubagent(
    String name,
    Map<String, dynamic> args,
    void Function(int)? onProgress,
    SubagentRun run,
    int? parentCurrentNovelId,
  ) async {
    final executor = ToolExecutor(ref);
    return executor.execute(
      name,
      args,
      scenarioContext: AgentScenarioContext(
        scenarioId: 'writing',
        currentNovelId: parentCurrentNovelId,
      ),
      onProgress: onProgress,
    );
  }

  /// 取消某 session 全部活跃 run（主 Agent cancel 时级联）。
  ///
  /// 任务 18：返回 [Future] 并 await 所有活跃 run 的 `done` 信号，
  /// 使 cancel 调用方能确定性等待子 Agent 真正退出（根治资源泄露 + 竞态）。
  /// AgentLoop 在 cancel 时会中断底层 LLM stream（任务 21），秒级退出；
  /// 若因工具执行等无法中断的阶段卡住，[doneTimeout] 总超时兜底 warn 放弃，
  /// 避免卡死 cancel 链路。
  ///
  /// [doneTimeout] 默认 15s；测试可短超时快速验证兜底路径。
  Future<void> cancelAllForSession(
    String sessionId, {
    Duration doneTimeout = const Duration(seconds: 15),
  }) async {
    final activeRuns = registry
        .listForSession(sessionId)
        .where((r) => !r.isTerminal)
        .toList();
    // 标记 pending run 为 cancelled，避免唤醒后进入 _runOne
    for (final run in activeRuns) {
      if (run.state == SubagentRunState.pending) {
        run.state = SubagentRunState.cancelled;
        run.completeDone();
      }
    }
    for (final run in activeRuns) {
      if (run.state != SubagentRunState.cancelled) {
        run.token?.cancel(reason: '主 Agent 取消');
      }
    }
    // 清掉等待队列里未触发的 completer，避免测试或 session 关闭后泄漏
    final queue = _waitingQueues.remove(sessionId);
    if (queue != null) {
      for (final c in queue) {
        if (!c.isCompleted) c.complete();
      }
    }
    if (activeRuns.isEmpty) return;
    final notDone = activeRuns.where((r) => !r.isDone).toList();
    if (notDone.isEmpty) return;
    try {
      await Future.wait(notDone.map((r) => r.done)).timeout(doneTimeout);
    } on TimeoutException {
      LoggerService.instance.w(
        'cancelAllForSession 等子 Agent done 超时 ${doneTimeout.inSeconds}s '
        '(session=$sessionId, unfinished=${activeRuns.where((r) => !r.isDone).length})',
        category: LogCategory.ai,
        tags: ['agent', 'subagent', 'cancel_timeout'],
      );
    }
  }

  /// 测试专用：只入队 registry 不真跑。
  Future<String> enqueueForTest(
    String sessionId, {
    required String task,
    required List<String> allowedTools,
  }) async {
    if (registry.countActiveBySession(sessionId) >= maxQueue) {
      return jsonEncode({
        'error': 'max_subagents_reached',
        'message': '已达上限',
      });
    }
    final run = registry.create(
      parentSessionId: sessionId,
      task: task,
      allowedTools: allowedTools,
    );
    return jsonEncode({'success': true, 'runId': run.runId});
  }

  /// 测试专用：清掉全部等待队列的 completer（避免跨测试状态污染）。
  void clearWaitingQueuesForTest() {
    for (final queue in _waitingQueues.values) {
      for (final c in queue) {
        if (!c.isCompleted) c.complete();
      }
    }
    _waitingQueues.clear();
  }

  /// 测试专用：暴露 dispatch 入口但不要求 parentToolCallId（用空字符串占位）。
  Future<String> dispatchForTest({
    required String parentSessionId,
    required String task,
    required List<String> allowedTools,
  }) {
    return dispatch(
      parentSessionId: parentSessionId,
      task: task,
      allowedTools: allowedTools,
      parentToolCallId: 'test-tc',
    );
  }

  /// 测试专用：暴露 _buildResultJson。
  String buildResultJsonForTest(SubagentRun run) => _buildResultJson(run);
}

/// 测试用 Ref：forTest 路径若意外触发真实 ref 调用会立即抛错，便于定位。
class _ThrowRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('forTest Ref 不支持真实调用: ${invocation.memberName}');
}

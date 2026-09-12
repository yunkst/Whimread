/// 本地小说写作 Agent 门面服务
///
/// Phase 2: 封装 AgentLoop，提供面向 UI 的接口
/// 重构: 支持多场景切换，通过 scenarioId 和 AgentScenarioContext 分派
///
/// 隔离改造: 去掉全局 _isRunning 互斥锁，改为按 scenarioId 跟踪运行状态。
/// 不同场景可以并行运行 Agent，同场景内串行（拒绝并发请求）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/core/providers/services/ai_service_providers.dart';
import 'package:novel_app/services/llm_config_service.dart';

import '../../utils/cancellation_token.dart';
import '../dsl_engine/llm_provider.dart' show LlmProvider;
import 'agent_event.dart';
import 'agent_loop.dart';
import 'agent_scenario.dart';
import 'agent_scenario_factory.dart';
import 'agent_system_prompt.dart';

/// 给一个未打标的事件打上 [runId]，原样保留其它字段。
///
/// 由 NovelAgentService.sendMessage/resumeFromMessages 在 runId 非空时把
/// loop emit 包装一层（emit 回调本身没法做"加字段"，必须重新构造），
/// 让 ScenarioSession 端的 [shouldMainSessionHandleEvent] 能用 runId 精确
/// 区分本 session 与其它并发 session，避免跨场景事件污染。
AgentEvent _tagEventWithRunId(AgentEvent event, String runId) {
  return switch (event) {
    TextDeltaEvent() => TextDeltaEvent(event.text, runId: runId),
    ToolCallStartEvent() =>
      ToolCallStartEvent(event.name, event.args, event.toolCallId, runId: runId),
    ToolCallEndEvent() => ToolCallEndEvent(
        event.name,
        event.toolCallId,
        event.result,
        fullResult: event.fullResult,
        success: event.success,
        runId: runId,
      ),
    ToolProgressEvent() =>
      ToolProgressEvent(event.toolCallId, event.generatedChars, runId: runId),
    AgentDoneEvent() => AgentDoneEvent(runId: runId),
    AgentErrorEvent() =>
      AgentErrorEvent(event.error, quotaExhausted: event.quotaExhausted, runId: runId),
    InjectedUserInputEvent() =>
      InjectedUserInputEvent(event.text, scenarioId: event.scenarioId, runId: runId),
    RetryEvent() => RetryEvent(
        attempt: event.attempt,
        maxAttempts: event.maxAttempts,
        delayMs: event.delayMs,
        errorText: event.errorText,
        emittedChars: event.emittedChars,
        runId: runId,
      ),
    CompactionEvent() => CompactionEvent(
        removedChars: event.removedChars,
        originalChars: event.originalChars,
        compactedChars: event.compactedChars,
        keptMessageCount: event.keptMessageCount,
        droppedMessageCount: event.droppedMessageCount,
        droppedAgentFromIndex: event.droppedAgentFromIndex,
        compactionNote: event.compactionNote,
        rewrittenContent: event.rewrittenContent,
        runId: runId,
      ),
  };
}

class NovelAgentService {
  final Ref ref;
  final StreamController<AgentEvent> _controller =
      StreamController<AgentEvent>.broadcast();

  /// 按场景跟踪运行状态（替代全局 _isRunning 互斥锁）
  ///
  /// 对应 Agent 的同会话串行化：同一个 session_key 同时只有一个 AIAgent 在跑。
  /// 但不同 session_key 之间完全并行。
  final Map<String, bool> _runningByScenario = {};

  /// 按场景跟踪取消令牌
  final Map<String, CancellationToken> _tokensByScenario = {};

  /// 按场景排队的运行中补充消息（A 方案）。
  ///
  /// 当 `sendMessage` 检测到本场景已在运行时，把 user 文本追加到此队列，
  /// 由 `AgentLoop.run` 通过 `pendingInjections` 回调 drain 到 messages，
  /// 让下一轮 LLM 调用看到（不打断当前 LLM stream / 当前 tool 调用）。
  ///
  /// 取消（[cancelFor] / [cancelAll]）时清空对应队列，避免孤狼消息。
  final Map<String, List<String>> _pendingInjectionsByScenario = {};

  NovelAgentService(this.ref);

  /// 是否有指定场景正在运行
  bool isRunningFor(String scenarioId) => _runningByScenario[scenarioId] == true;

  /// 是否有任何场景正在运行
  bool get isRunning => _runningByScenario.values.any((v) => v);

  /// 运行中补充消息入口（A 方案）。
  ///
  /// 由 [ScenarioSession.sendMessage] 在 `_isRunning == true` 时调用：
  /// 把 user 文本排队，等当前 loop 下一轮通过 `pendingInjections` 回调
  /// drain 到 messages，让本轮 LLM 看到（不打断当前 LLM stream / tool 调用）。
  /// emit [InjectedUserInputEvent] 让 UI 立刻反馈"已补充 N 条"。
  void injectUserMessage(String scenarioId, String text) {
    _enqueueInjection(scenarioId, text);
  }

  /// 排队一条补充消息 + emit UI 反馈事件（sendMessage/injectUserMessage 共用）。
  void _enqueueInjection(String scenarioId, String text) {
    if (text.trim().isEmpty) return;
    _pendingInjectionsByScenario
        .putIfAbsent(scenarioId, () => <String>[])
        .add(text);
    LoggerService.instance.i(
      'Agent 排队补充消息 (scenario=$scenarioId, length=${text.length})',
      category: LogCategory.ai,
      tags: ['agent', 'service', 'inject', 'queue', scenarioId],
    );
    _controller.add(InjectedUserInputEvent(text, scenarioId: scenarioId));
  }

  /// drain 本场景排队的补充消息（供 loop.run 的 pendingInjections 回调）。
  /// 取出并清空队列；空队列返回 const [] 避免 alloc。
  List<String> _drainInjections(String scenarioId) {
    final list = _pendingInjectionsByScenario[scenarioId];
    if (list == null || list.isEmpty) return const <String>[];
    final out = List<String>.from(list);
    list.clear();
    return out;
  }

  /// 事件流
  Stream<AgentEvent> get events => _controller.stream;

  /// 公开的事件写入入口（供 SubagentRunner 等子组件回流事件到主 Agent 流）
  ///
  /// 决策 1（任务 7）：子 Agent 不再由 emitParent 转发事件，
  /// 直接调本方法把打标后事件发到全局流（主 session 已订阅）。
  /// 内部就是 `_controller.add`，只是把 StreamController 私有封装。
  void addEvent(AgentEvent event) {
    _controller.add(event);
  }

  /// 取消指定场景的 Agent 回合
  ///
  /// 只取消目标场景，不影响其他场景的运行。
  /// 对应 Agent 的线程局部中断：只中断目标线程，不误杀其他会话。
  void cancelFor(String scenarioId) {
    // 取消 = 用户撤回本回合，排队的补充消息一并丢弃（避免孤狼）
    _pendingInjectionsByScenario.remove(scenarioId);
    _runningByScenario.remove(scenarioId);
    final token = _tokensByScenario[scenarioId];
    if (token != null) {
      LoggerService.instance.i(
        'Agent 已取消（场景 $scenarioId）',
        category: LogCategory.ai,
        tags: ['agent', 'service', 'cancel', scenarioId],
      );
      token.cancel(reason: '用户主动取消 (scenario=$scenarioId)');
      _tokensByScenario.remove(scenarioId);
    }
  }

  /// 取消所有正在运行的 Agent
  void cancelAll() {
    _pendingInjectionsByScenario.clear();
    for (final entry in _tokensByScenario.entries) {
      entry.value.cancel(reason: '取消所有 (scenario=${entry.key})');
    }
    _tokensByScenario.clear();
    _runningByScenario.clear();
  }

  /// 发送消息给 Agent
  ///
  /// [userInput] 用户输入
  /// [history] 之前的对话历史（agent 视角的完整 messages，含 tool/system，不含本轮 user）
  /// [scenarioId] 场景标识（'writing' | 'webview_extract' | ...）
  /// [scenarioContext] 场景上下文参数
  /// [runId] 非空时给本次运行 emit 的所有事件打上 runId 标签，
  /// 让调用方持有的 ScenarioSession 用 [shouldMainSessionHandleEvent] 精确
  /// 接收本 run 的事件，避免与其它并发运行的 session 互相污染。
  /// 通常由 startAnnotationRewrite 这类「运行实例 ≠ scenarioId」的入口使用，
  /// 传入 sessionId.toString()；普通 sendMessage 留空（保持原 untagged 行为）。
  Future<void> sendMessage({
    required String userInput,
    required List<ChatMessage> history,
    required String scenarioId,
    required AgentScenarioContext scenarioContext,
    String? runId,
  }) async {
    // A 方案：运行中不再拒绝，改为排队补充消息。消息由 AgentLoop.run 的
    // pendingInjections 回调在下一轮 drain 到 messages，让本轮 LLM 看到
    // （不打断当前 LLM stream / 当前 tool 调用）。UI 计数由 _enqueueInjection
    // emit 的 InjectedUserInputEvent 完成。
    if (_runningByScenario[scenarioId] == true) {
      _enqueueInjection(scenarioId, userInput);
      return;
    }

    _runningByScenario[scenarioId] = true;
    final token = CancellationToken();
    _tokensByScenario[scenarioId] = token;
    // 记录本次运行的注入队列身份：cancelFor 后新 run 可能换上自己的队列，
    // 旧 run 的 finally 不能把新 run 的队列/token 一并清掉（2026-09 审查 P2 竞态）
    final myInjections =
        _pendingInjectionsByScenario.putIfAbsent(scenarioId, () => <String>[]);

    try {
      final env = await _buildAgentEnv(scenarioId, scenarioContext);
      if (env == null) return; // _buildAgentEnv 已 emit notConfiguredMessage

      try {
        // 构造循环
        final loop = AgentLoop(llm: env.llm, scenario: env.scenario);

        // 加载场景经验记忆（在 buildSystemPrompt 前调用，让场景有缓存）
        await env.scenario.getMemories();

        // 构造 system prompt（由场景生成；用户上下文/当前工作小说由下面 user message 注入）
        final systemPrompt = env.scenario.buildSystemPrompt(scenarioContext);

        // 构造本轮 user message：把"用户正在阅读 / 当前工作小说"作为临时上下文
        // 注入到用户输入头部。history 保持原文（落库的也是原文）。
        final contextPrefix = AgentSystemPrompt.buildUserContextPrefix(
          readingContext: scenarioContext.readingContext,
          currentNovelTitle: scenarioContext.currentNovelTitle,
        );
        final userContent = contextPrefix.isEmpty
            ? userInput
            : '$contextPrefix$userInput';

        // 构造初始消息
        final initialMessages = [
          ...history,
          ChatMessage(role: 'user', content: userContent),
        ];

        // runId 非空时包装 emit：每个事件在 _controller.add 前打标，
        // 让本 run 的事件只被 runId 匹配的 ScenarioSession 接收。
        final emit = runId == null
            ? (AgentEvent event) => _controller.add(event)
            : (AgentEvent event) =>
                _controller.add(_tagEventWithRunId(event, runId));

        // 运行循环
        await loop.run(
          initialMessages: initialMessages,
          systemPrompt: systemPrompt,
          emit: emit,
          cancellationToken: token,
          pendingInjections: () => _drainInjections(scenarioId),
        );

        final cancelledTag = token.isCancelled ? ' (cancelled)' : '';
        LoggerService.instance.i(
          'Agent 请求处理完成$cancelledTag (scenario=$scenarioId)',
          category: LogCategory.ai,
          tags: ['agent', 'service', 'complete', scenarioId],
        );
      } finally {
        // 场景资源清理（如释放 HeadlessWebViewPool 使用权）+
        // LLM 传输释放（io.HttpClient 连接池随消息累积，2026-09 审查 P1）
        await env.scenario.cleanup();
        env.llm.dispose();
      }
    } catch (e, stack) {
      LoggerService.instance.e('Agent 请求处理失败: $e',
          stackTrace: stack.toString(),
          category: LogCategory.ai,
          tags: ['agent', 'service', 'error', scenarioId]);
      _controller.add(AgentErrorEvent(e.toString()));
    } finally {
      // 只清理仍属于本次运行的条目：cancelFor 后新 run 可能已换上自己的
      // token/队列，旧 run 的 finally 不能把新 run 的一并清掉
      //（否则新 run 不可取消、注入消息丢失，2026-09 审查 P2 竞态）
      if (identical(_tokensByScenario[scenarioId], token)) {
        _runningByScenario.remove(scenarioId);
        _tokensByScenario.remove(scenarioId);
      }
      if (identical(_pendingInjectionsByScenario[scenarioId], myInjections)) {
        _pendingInjectionsByScenario.remove(scenarioId);
      }
    }
  }

  /// 从给定的消息序列继续运行 Agent 循环，不 append user。
  ///
  /// 用于 ScenarioSession.retryLastRound：失败轮的 partial 已砍除，
  /// 调用方把剩余（含末尾 user）的 messages 直接交给 loop.run。
  /// 不调用 buildUserContextPrefix：retry 时阅读上下文应保持 user 当时的样子，
  /// 否则会污染 LLM 看到的历史。
  /// [runId] 语义同 sendMessage。
  Future<void> resumeFromMessages({
    required String scenarioId,
    required List<ChatMessage> initialMessages,
    required AgentScenarioContext scenarioContext,
    String? runId,
  }) async {
    // A 方案：与 sendMessage 对称。retryLastRound 调本方法前应已确保
    // _isRunning=false（失败轮 finalize 后 _isRunning 被设回 false），
    // 正常不会撞；万一上层 race 兜底走 inject 路径（传空串 = noop，
    // _enqueueInjection 会 trim 过滤），不抛错不丢。
    if (_runningByScenario[scenarioId] == true) {
      _enqueueInjection(scenarioId, '');
      return;
    }

    _runningByScenario[scenarioId] = true;
    final token = CancellationToken();
    _tokensByScenario[scenarioId] = token;
    // 身份守卫用途同 sendMessage（旧 run finally 不得清新 run 的条目）
    final myInjections =
        _pendingInjectionsByScenario.putIfAbsent(scenarioId, () => <String>[]);

    try {
      final env = await _buildAgentEnv(scenarioId, scenarioContext);
      if (env == null) return; // _buildAgentEnv 已 emit notConfiguredMessage

      try {
        final loop = AgentLoop(llm: env.llm, scenario: env.scenario);
        await env.scenario.getMemories();
        final systemPrompt = env.scenario.buildSystemPrompt(scenarioContext);

        // ★ 与 sendMessage 的关键差异：不 append user，不注入 contextPrefix
        final emit = runId == null
            ? (AgentEvent event) => _controller.add(event)
            : (AgentEvent event) =>
                _controller.add(_tagEventWithRunId(event, runId));

        await loop.run(
          initialMessages: initialMessages,
          systemPrompt: systemPrompt,
          emit: emit,
          cancellationToken: token,
          pendingInjections: () => _drainInjections(scenarioId),
        );

        final cancelledTag = token.isCancelled ? ' (cancelled)' : '';
        LoggerService.instance.i(
          'Agent 续跑完成$cancelledTag (scenario=$scenarioId, initialMessages=${initialMessages.length})',
          category: LogCategory.ai,
          tags: ['agent', 'service', 'resume_complete', scenarioId],
        );
      } finally {
        await env.scenario.cleanup();
        env.llm.dispose();
      }
    } catch (e, stack) {
      LoggerService.instance.e('Agent 续跑失败: $e',
          stackTrace: stack.toString(),
          category: LogCategory.ai,
          tags: ['agent', 'service', 'resume_error', scenarioId]);
      _controller.add(AgentErrorEvent(e.toString()));
    } finally {
      // 身份守卫用途同 sendMessage（旧 run finally 不得清新 run 的条目）
      if (identical(_tokensByScenario[scenarioId], token)) {
        _runningByScenario.remove(scenarioId);
        _tokensByScenario.remove(scenarioId);
      }
      if (identical(_pendingInjectionsByScenario[scenarioId], myInjections)) {
        _pendingInjectionsByScenario.remove(scenarioId);
      }
    }
  }

  /// 构造 Agent 运行所需的 LLM Provider + Scenario。
  ///
  /// sendMessage 与 resumeFromMessages 共用：
  /// - LLM config 拉取（支持场景级覆盖）
  /// - scenario 异步构造（可能需要初始化 Headless WebView）
  ///
  /// 返回 null 表示 LLM 未配置（已 emit notConfiguredMessage error 事件）。
  Future<({LlmProvider llm, AgentScenario scenario})?> _buildAgentEnv(
    String scenarioId,
    AgentScenarioContext scenarioContext,
  ) async {
    final configService = ref.read(llmConfigServiceProvider);
    final llm = await configService.buildActiveProvider(scenarioId);
    if (llm == null) {
      _controller.add(const AgentErrorEvent(
          LlmConfigService.notConfiguredMessage));
      return null;
    }
    final scenario =
        await AgentScenarioFactory(ref).build(scenarioId, scenarioContext);
    return (llm: llm, scenario: scenario);
  }

  /// 取消当前运行（仅关闭流，不中断底层 HTTP）
  void dispose() {
    _controller.close();
  }
}

/// Agent 服务 Provider
final novelAgentServiceProvider = Provider<NovelAgentService>((ref) {
  LoggerService.instance.i('NovelAgentService 初始化',
      category: LogCategory.ai, tags: ['agent', 'service', 'init']);
  final service = NovelAgentService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

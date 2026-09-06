/// Agent ReAct 循环核心
///
/// Phase 2: 实现思考-行动循环，管理 LLM 对话和工具调用
/// 重构: 依赖 AgentScenario 抽象，支持多场景切换
library;

import 'dart:async';
import 'dart:convert';

import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/utils/cancellation_token.dart';
import 'package:novel_app/utils/retry_helper.dart'
    show RetryPolicy, RetryableHttpException, isTransientNetworkError;

import '../dsl_engine/llm_provider.dart';
import '../dsl_engine/retry_signals.dart';
import 'agent_event.dart';
import 'agent_scenario.dart';
import 'context_compactor.dart';
import 'tool_result_formatter.dart';

/// Agent 循环取消行为
///
/// - [graceful]：默认。收到 cancel 后不中断底层 LLM stream，等本轮输出完
///   再停止（主 Agent 现有行为，保留 check-point B 语义）。
/// - [immediate]：cancel 时立即 cancel stream subscription，中断底层 LLM 连接，
///   子 Agent 秒级退出。不会等待本轮输出完。
enum AgentLoopCancelBehavior {
  graceful,
  immediate,
}

/// Agent 循环配置
class AgentLoopConfig {
  final int maxRounds;

  /// 给 LLM 的工具结果最大字符数（截断阈值）
  ///
  /// 默认 50000 字符 ≈ 12.5K tokens，覆盖单章正文（通常 3000-8000 字）。
  /// 实际截断逻辑委托给 [ToolResultFormatter]。LLM 始终拿到合法 JSON。
  final int toolResultMaxChars;

  /// 上下文压缩配置（默认启用）
  final CompactorConfig compaction;

  /// 单轮 LLM 流式调用总耗时上限
  ///
  /// 流式响应无事件到达此上限即触发 [TimeoutException]，
  /// 由 [isTransientNetworkError] 判定为瞬态错误，触发 round 重试。
  /// 默认 5min，覆盖单章正文生成（3000-8000 字约 30s-2min）。
  final Duration llmStreamTimeout;

  /// 单轮内网络错误最大重试次数
  ///
  /// 仅当异常是瞬态网络错误（[isTransientNetworkError] 返回 true）时触发；
  /// JSON 解析失败、空响应等逻辑错误不重试，立即终止。
  /// 重试计数与外层 round 独立：成功后 [roundRetryCount] 重置。
  final int networkRetryPerRound;

  /// 重试退避策略（可注入用于测试）。
  ///
  /// 回合层退避复用 [RetryPolicy]（与传输层 [withRetry] 同一退避算法），
  /// 含 jitter + Retry-After 感知，避免两套退避漂移。
  /// 默认 [RetryPolicy] 与传输层行为一致（maxDelay=60s, initialDelay=500ms,
  /// multiplier=2.0, jitterFactor=0.25）。
  final RetryPolicy retryPolicy;

  /// 收到取消信号后的行为（主 Agent 默认 gentle，子 Agent 传 immediate）。
  final AgentLoopCancelBehavior cancelBehavior;

  const AgentLoopConfig({
    this.maxRounds = 50,
    this.toolResultMaxChars = 50000,
    this.compaction = const CompactorConfig(),
    this.llmStreamTimeout = const Duration(minutes: 5),
    this.networkRetryPerRound = 2,
    this.retryPolicy = const RetryPolicy(),
    this.cancelBehavior = AgentLoopCancelBehavior.graceful,
  });
}

/// Agent ReAct 循环
///
/// 管理 LLM 对话、工具调用、确认流程。
/// 通过 [AgentScenario] 抽象支持不同场景的工具集和 system prompt。
class AgentLoop {
  final LlmProvider _llm;
  final AgentScenario _scenario;
  final AgentLoopConfig _config;
  final ContextCompactor _compactor;
  late final ToolResultFormatter _toolResultFormatter;

  /// 最近一次 LLM 响应携带的 usage.prompt_tokens（网关支持时才有值）。
  ///
  /// 作为下一轮压缩判定的真实 token 依据（被动消费：不主动发
  /// `stream_options`，兼容不支持的网关；DeepSeek 等默认在末帧带 usage）。
  int? _lastPromptTokens;

  /// finish_reason=length 后置位：下一轮 LLM 调用前强制压缩（绕过阈值）。
  ///
  /// length 说明输出被截断，上下文压力是常见诱因之一；主动压缩一轮缓解。
  /// 压缩后（或确认无可压缩内容）清位，避免每轮重复强制压缩。
  bool _forceCompaction = false;

  /// 本次 run 内是否已对"异常空响应"注入过 nudge。
  ///
  /// 整个 run 只 nudge 一次，防止 LLM 持续返回空内容导致死循环。
  bool _emptyResponseNudged = false;

  AgentLoop({
    required LlmProvider llm,
    required AgentScenario scenario,
    AgentLoopConfig? config,
  })  : _llm = llm,
        _scenario = scenario,
        _config = config ?? const AgentLoopConfig(),
        _compactor = ContextCompactor(
            config: (config ?? const AgentLoopConfig()).compaction) {
    _toolResultFormatter =
        ToolResultFormatter(maxChars: _config.toolResultMaxChars);
  }

  /// 运行 Agent 循环
  ///
  /// [initialMessages] 初始消息列表（不含 system prompt）
  /// [systemPrompt] 系统提示词
  /// [emit] 事件回调
  /// [cancellationToken] 取消令牌；触发取消后，当前这轮 LLM 输出完成，
  ///   但循环不再执行后续工具、不再进入下一轮（不中断底层 LLM HTTP）。
  /// [pendingInjections] 运行中补充消息源：每轮 LLM 调用前调用一次，
  ///   返回当前排队的 user 补充文本列表（可能为空）。loop 把它们 append 到
  ///   messages，让本轮 LLM 看到补充消息（不打断上一轮已在进行的 LLM 流）。
  ///   由 [NovelAgentService] 维护的 per-scenario 队列提供。null = 无注入能力（子 Agent）。
  /// [messageOwners] 可选对齐信息：长度 = [initialMessages] 的长度，
  ///   元素为对应 AgentMessage 在 UI 列表中的索引，-1 表示 system 消息不映射。
  ///   压缩时透传给 [ContextCompactor.compact]，用于反推被丢弃的 AgentMessage 区间，
  ///   通过 [CompactionEvent.droppedHermesRange] 通知 UI 同步裁剪。
  Future<void> run({
    required List<ChatMessage> initialMessages,
    required String systemPrompt,
    required void Function(AgentEvent event) emit,
    CancellationToken? cancellationToken,
    List<String> Function()? pendingInjections,
  }) async {
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: systemPrompt),
      ...initialMessages,
    ];

    LoggerService.instance.i('Agent 循环开始 (scenario=${_scenario.id})',
        category: LogCategory.ai, tags: ['agent', 'loop_start', _scenario.id]);

    int round = 0;
    int roundRetryCount = 0;
    while (round < _config.maxRounds) {
      // 检查点 A：进入新一轮前（例如上一轮工具执行后被取消）
      if (cancellationToken?.isCancelled == true) {
        LoggerService.instance.i(
            'Agent 循环已取消，不再进入第 $round 轮 (scenario=${_scenario.id})',
            category: LogCategory.ai,
            tags: ['agent', 'loop', 'cancelled', _scenario.id]);
        emit(const AgentDoneEvent());
        return;
      }

      // 本轮流式累积结果：提升到 try 外声明，catch 块需要读取
      // fullContent.length（本轮已 emit 的 partial 字符数）以构造
      // RetryEvent.emittedChars，供 session/projector 精确截断。
      final streamingResult = StreamingResult();
      String? streamFinishReason;
      int contentChunkCount = 0;

      try {
        LoggerService.instance.d('Agent 循环第 $round 轮 (${_scenario.id})',
            category: LogCategory.ai, tags: ['agent', 'loop', _scenario.id]);

        // 0a. 运行中补充消息注入（每轮 LLM 调用前 drain）
        //     用户在 agent 运行中追加的消息由 [NovelAgentService] 排队，
        //     此处拉取并 append 到 messages，让本轮 LLM 调用看到。
        //     不打断上一轮（drain 只在两 round 边界执行）；不 emit
        //     InjectedUserInputEvent（UI 计数已在 service.injectUserMessage 完成）。
        final injected = pendingInjections?.call() ?? const <String>[];
        for (final text in injected) {
          if (text.trim().isEmpty) continue;
          messages.add(ChatMessage(role: 'user', content: text));
          LoggerService.instance.i(
            'Agent 注入补充 user: ${text.length} 字 (round $round, scenario=${_scenario.id})',
            category: LogCategory.ai,
            tags: ['agent', 'loop', 'inject', _scenario.id],
          );
        }

        // 0b. 上下文压缩检查（每轮 LLM 调用前）
        //     防止 messages 无限增长导致超出 LLM 上下文窗口。
        //     三种触发：字符阈值 / 启发式 token 阈值（无 usage 时的 fallback）/
        //     真实 promptTokens 超限（上一轮 LLM usage，最准）/ length 强制。
        final forced = _forceCompaction;
        if (forced || _compactor.needsCompaction(messages,
            realPromptTokens: _lastPromptTokens)) {
          final triggerDesc = forced
              ? 'finish_reason=length 强制'
              : (_lastPromptTokens != null
                  ? '真实 promptTokens=$_lastPromptTokens'
                  : '超过阈值 (${_config.compaction.maxContextChars} 字符 / '
                      '${_config.compaction.maxContextTokens} tokens)');
          LoggerService.instance.w(
            '触发上下文压缩: 消息总量 ${messages.length} 条，$triggerDesc',
            category: LogCategory.ai,
            tags: ['agent', 'compaction', 'triggered', _scenario.id],
          );
          final result = _compactor.compact(
            messages: messages,
            systemPrompt: systemPrompt,
          );
          // 无可压缩内容（如首轮即 length：无老消息可丢）→ 不 apply 不 emit，
          // 避免插入"丢弃 0 条"的空压缩提示污染上下文与 DB marker。
          if (result.droppedMessageCount == 0 &&
              result.rewrittenContent.isEmpty) {
            LoggerService.instance.w(
              '压缩无内容可丢弃，跳过 (messages=${messages.length}, '
              'chars=${result.originalChars}, scenario=${_scenario.id})',
              category: LogCategory.ai,
              tags: ['agent', 'compaction', 'skipped', _scenario.id],
            );
          } else {
            messages
              ..clear()
              ..addAll(result.messages);
            emit(CompactionEvent(
              removedChars: result.removedChars,
              originalChars: result.originalChars,
              compactedChars: result.compactedChars,
              keptMessageCount: result.keptMessageCount,
              droppedMessageCount: result.droppedMessageCount,
              droppedAgentFromIndex: result.droppedAgentFromIndex,
              compactionNote: result.messages[1].content ?? '',
              rewrittenContent: result.rewrittenContent,
            ));
          }
          _forceCompaction = false;
        }

        // 1. 调用 LLM（流式 + 工具定义），逐 chunk 实时 emit
        final toolsCount = _scenario.tools.length;
        LoggerService.instance.d(
            '调用 LLM (round $round, $toolsCount 个工具, 流式, scenario=${_scenario.id})',
            category: LogCategory.ai,
            tags: ['agent', 'llm', 'request']);

        // ★ 流式超时：超过 [llmStreamTimeout] 无事件到达 → TimeoutException
        // → 由 catch 块判定为瞬态网络错误，触发 round 重试
        final streamTimeout = _config.llmStreamTimeout;
        final streamSource = _llm
            .chatStreamWithTools(
          messages: messages,
          tools: _scenario.tools,
          toolChoice: 'auto',
        )
            .timeout(
          streamTimeout,
          onTimeout: (EventSink<LlmStreamChunk> sink) {
            sink.addError(TimeoutException(
              'LLM 流式响应超过 ${streamTimeout.inMinutes} 分钟无事件',
              streamTimeout,
            ));
            sink.close();
          },
        );

        // 任务 20/21：显式 subscription + Completer 消费流式响应。
        // - 当 [cancelBehavior] == [AgentLoopCancelBehavior.immediate] 时，注册
        //   cancellationToken 监听器，cancel 时 cancel subscription 立即退出
        //   （子 Agent 秒级退出，不等本轮 LLM 输出完）。
        // - 当 [cancelBehavior] == [AgentLoopCancelBehavior.graceful]（默认/主 Agent）时，
        //   不注册监听器，保持原 await for 的“本轮输出完再停”语义。
        // 处理逻辑与原 await for 完全等价：emit 文本、累积 tool_calls、记 finishReason。
        final streamCompleter = Completer<void>();
        late final StreamSubscription<LlmStreamChunk> streamSub;
        void Function()? unregisterCancel;

        void completeStream() {
          if (!streamCompleter.isCompleted) {
            streamCompleter.complete();
          }
        }

        streamSub = streamSource.listen(
          (chunk) {
            // 实时 emit 文本增量 → UI 流式展示
            if (chunk.isContent) {
              contentChunkCount++;
              // 累积 content chunk：fullContent 供 assistant 消息入栈与
              // RetryEvent.emittedChars 使用。缺失会导致 LLM 上下文丢失
              // 本轮文本（v1.7.3 起遗留 bug，连带 isAbnormalEmpty 误判）。
              streamingResult.contentChunks.add(chunk.contentChunk!);
              emit(TextDeltaEvent(chunk.contentChunk!));
            }
            // 累积 tool_calls delta
            if (chunk.isToolCallDelta) {
              streamingResult.toolCallDeltas.addAll(chunk.toolCallDeltas);
            }
            // 记录 finish_reason
            if (chunk.isFinished) {
              streamFinishReason = chunk.finishReason;
            }
            // 被动消费 usage：网关在末帧附带 prompt/completion tokens，
            // 用于下一轮压缩判定的真实 token 依据。无值时静默忽略。
            final usage = chunk.usage;
            if (usage != null && usage.promptTokens != null) {
              _lastPromptTokens = usage.promptTokens;
            }
          },
          onError: (e, s) {
            unregisterCancel?.call();
            if (!streamCompleter.isCompleted) {
              streamCompleter.completeError(e, s);
            }
          },
          onDone: () {
            unregisterCancel?.call();
            completeStream();
          },
        );

        if (_config.cancelBehavior == AgentLoopCancelBehavior.immediate) {
          unregisterCancel = cancellationToken?.register(() {
            if (!streamCompleter.isCompleted) {
              streamSub.cancel();
              completeStream();
            }
          });
        }

        try {
          await streamCompleter.future;
        } finally {
          unregisterCancel?.call();
        }

        // 2. 流结束后聚合 tool_calls
        final toolCalls = streamingResult.buildToolCalls();
        final fullContent = streamingResult.fullContent;

        // 检查点 B：本轮 LLM 流式输出已完整 emit，若已取消则不再执行工具 / 进入下一轮
        // 满足"让 agent 输出完，但不继续下一个循环"的语义
        if (cancellationToken?.isCancelled == true) {
          LoggerService.instance.i(
              'Agent 循环已取消（本轮 LLM 输出完，跳过工具与下一轮，scenario=${_scenario.id}）',
              category: LogCategory.ai,
              tags: ['agent', 'loop', 'cancelled', _scenario.id]);
          emit(const AgentDoneEvent());
          return;
        }

        // 异常 finishReason（length 截断 / content_filter 审查）独立告警
        if (streamFinishReason == 'length' ||
            streamFinishReason == 'content_filter') {
          LoggerService.instance.w(
            'LLM finish_reason=$streamFinishReason (round $round, scenario=${_scenario.id})',
            category: LogCategory.ai,
            tags: [
              'agent',
              'llm',
              'finish_reason',
              streamFinishReason!,
              _scenario.id,
            ],
          );
          // length 强制下一轮压缩：上限触发说明上下文压力是常见诱因之一，
          // 主动压缩一轮缓解（无论是否达阈值）。content_filter 不触发（与上下文无关）。
          if (streamFinishReason == 'length') {
            _forceCompaction = true;
          }
        }

        // contentLength=0 但 finishReason 不是 tool_calls 时，说明 LLM 异常返回空内容，需要告警
        // contentLength=0 + finishReason=tool_calls 是正常的 ReAct 行为（LLM 决定调用工具）
        final isAbnormalEmpty = fullContent.isEmpty &&
            toolCalls.isEmpty &&
            streamFinishReason != 'tool_calls';
        final logMessage = 'LLM 流式响应 (round $round): '
            'contentChunks=$contentChunkCount, '
            'contentLength=${fullContent.length}, '
            'toolCalls=${toolCalls.length}, '
            'finishReason=$streamFinishReason';
        if (isAbnormalEmpty) {
          LoggerService.instance.w(
            '$logMessage [异常: 响应内容为空]',
            category: LogCategory.ai,
            tags: ['agent', 'llm', 'response', 'abnormal-empty', _scenario.id],
          );
        } else {
          LoggerService.instance.i(
            logMessage,
            category: LogCategory.ai,
            tags: ['agent', 'llm', 'response', _scenario.id],
          );
        }

        // 3. 无工具调用 → 先把本轮 assistant 消息入栈，再检查场景是否要注入提示
        if (toolCalls.isEmpty) {
          // 把本轮 assistant 消息加入 messages
          // （无 tool_calls 时后续不会自动加入，但 follow-up 注入后 LLM 需要看到上文）
          if (fullContent.isNotEmpty) {
            messages.add(ChatMessage(
              role: 'assistant',
              content: fullContent,
            ));
          }

          // 异常空响应（无内容 + 无工具 + finishReason 非 tool_calls）：
          // 注入一次 nudge 让 LLM 重试本轮，而非静默结束让用户困惑。
          // 整个 run 只 nudge 一次（防 LLM 持续返回空内容的死循环）；
          // 置于场景钩子之前——空响应时钩子的"漏步骤"提示文不对题。
          if (isAbnormalEmpty && !_emptyResponseNudged) {
            _emptyResponseNudged = true;
            messages.add(ChatMessage(
              role: 'user',
              content: '你上一轮返回了空内容。请继续完成当前任务，'
                  '直接输出内容或调用工具。',
            ));
            LoggerService.instance.w(
              'LLM 空响应，注入 nudge 重试 (round $round, scenario=${_scenario.id})',
              category: LogCategory.ai,
              tags: ['agent', 'loop', 'empty_response_nudge', _scenario.id],
            );
            roundRetryCount = 0;
            round++;
            continue;
          }

          // 场景注入钩子：允许场景在"即将结束"时追加一条 user 提示
          // 让 Agent 再尝试一轮（例如提示"已生成脚本但未保存，请调 save_script"）
          final injection = await _scenario.onNoToolCalls(messages);
          if (injection != null) {
            messages.add(ChatMessage(role: 'user', content: injection));
            emit(TextDeltaEvent('\n\n$injection\n\n'));
            LoggerService.instance.i(
              'Agent 循环注入场景提示 (round $round, scenario=${_scenario.id})，继续下一轮',
              category: LogCategory.ai,
              tags: ['agent', 'loop', 'injection', _scenario.id],
            );
            // 本轮已成功完成（无 tool_calls 注入场景提示）→ 先递增，再 continue
            roundRetryCount = 0;
            round++;
            continue; // 不结束，继续下一轮
          }

          emit(const AgentDoneEvent());
          RetrySignals.instance.clear();
          LoggerService.instance.i(
              'Agent 循环完成（无工具调用，共 $round 轮, scenario=${_scenario.id}）',
              category: LogCategory.ai,
              tags: ['agent', 'loop_end', _scenario.id]);
          return;
        }

        // 4. 注入 assistant 消息（含 tool_calls）
        messages.add(ChatMessage(
          role: 'assistant',
          content: fullContent.isNotEmpty ? fullContent : null,
          toolCalls: toolCalls,
        ));

        // 5. 执行工具调用
        //
        // 任务 7：拆分「普通工具串行 + dispatch_subagent 并行」
        // - 普通工具（read_chapter / list_novels 等）：保持串行（按 toolCalls 顺序）
        // - dispatch_subagent：先收集再 Future.wait 并行（子 Agent 间互不阻塞）
        // - 普通工具先全部跑完，再并行派发子 Agent（避免子 Agent 与普通工具
        //   并发产生不可预测的时序）
        final subagentCalls = <ToolCall>[];
        for (final call in toolCalls) {
          // 检查点 C：批量工具执行中途被取消，跳过剩余工具
          if (cancellationToken?.isCancelled == true) {
            LoggerService.instance.i(
                'Agent 循环已取消，跳过工具 ${call.name} 及后续工具 (scenario=${_scenario.id})',
                category: LogCategory.ai,
                tags: ['agent', 'loop', 'cancelled', _scenario.id]);
            emit(const AgentDoneEvent());
            return;
          }

          if (call.name == 'dispatch_subagent') {
            subagentCalls.add(call);
            continue;
          }

          messages.add(await _executeSingleTool(call, emit, cancellationToken));
        }

        // 子 Agent 并行派发：同一轮内多个 dispatch_subagent 互不阻塞。
        // 并行结束后按原序 append 到 messages（保持顺序可预测）。
        if (subagentCalls.isNotEmpty) {
          // 检查点 C（再次）：派发子 Agent 前再确认未被取消
          if (cancellationToken?.isCancelled == true) {
            LoggerService.instance.i(
                'Agent 循环已取消，跳过 ${subagentCalls.length} 个 dispatch_subagent (scenario=${_scenario.id})',
                category: LogCategory.ai,
                tags: ['agent', 'loop', 'cancelled', _scenario.id]);
            emit(const AgentDoneEvent());
            return;
          }
          final parallelMessages = await Future.wait(subagentCalls.map(
            (call) => _executeSingleTool(call, emit, cancellationToken),
          ));
          messages.addAll(parallelMessages);
        }

        // 本轮成功执行（含工具调用）→ 进入下一轮，重置重试计数
        roundRetryCount = 0;
        round++;
      } catch (e, stack) {
        // 瞬态网络错误（SocketException / TimeoutException / 5xx 等）
        // → round 级整体重试，保留 messages 上下文，避免多轮 ReAct 白跑
        if (isTransientNetworkError(e) &&
            roundRetryCount < _config.networkRetryPerRound) {
          roundRetryCount++;
          // 统一退避策略（与传输层 withRetry 同一 RetryPolicy）：
          // 含 jitter（防雷鸣群）+ Retry-After 感知（服务端权威指示优先）。
          final retryAfterMs =
              e is RetryableHttpException ? e.retryAfterMs : null;
          final delayMs = _config.retryPolicy.computeDelayMs(
            attempt: roundRetryCount,
            retryAfterMs: retryAfterMs,
          );
          final delay = Duration(milliseconds: delayMs);
          LoggerService.instance.w(
            'Agent 轮级网络重试 (round=$round, $roundRetryCount/${_config.networkRetryPerRound}, '
            '${delay.inMilliseconds}ms, ${e.runtimeType}: $e)',
            category: LogCategory.ai,
            stackTrace: stack.toString(),
            tags: ['agent', 'loop', 'round_retry', _scenario.id],
          );
          // 走事件流 emit RetryEvent：session/projector 据 emittedChars 丢弃
          // 本轮已流出的 partial 文本（不丢的话，重试后的完整输出会与残缺
          // 前缀拼接进 streamingSegments 并落库）。
          emit(RetryEvent(
            attempt: roundRetryCount,
            maxAttempts: _config.networkRetryPerRound,
            delayMs: delayMs,
            errorText: e.toString(),
            emittedChars: streamingResult.fullContent.length,
          ));
          // 直接调 RetrySignals 走 UI 横幅(绕开 shouldMainSessionHandleEvent
          // 过滤,子 Agent 重试也能显示 — spec §3.1.1 方案 B)。
          try {
            RetrySignals.instance.reportRound(
              attempt: roundRetryCount,
              maxAttempts: _config.networkRetryPerRound,
              delayMs: delayMs,
              error: e,
            );
          } catch (_) {
            // report 失败不影响重试主流程
          }
          await Future<void>.delayed(delay);
          // 退避期间收到取消 → 优雅结束，不再重试
          if (cancellationToken?.isCancelled == true) {
            LoggerService.instance.i(
                'Agent 重试退避期间被取消 (round=$round, scenario=${_scenario.id})',
                category: LogCategory.ai,
                tags: [
                  'agent',
                  'loop',
                  'round_retry',
                  'cancelled',
                  _scenario.id
                ]);
            emit(const AgentDoneEvent());
            RetrySignals.instance.clear();
            return;
          }
          continue; // 重试本轮，不递增 round
        }

        LoggerService.instance.e(
            'Agent 循环异常 (round $round, scenario=${_scenario.id}): $e',
            stackTrace: stack.toString(),
            category: LogCategory.ai,
            tags: ['agent', 'loop', 'error', _scenario.id]);
        emit(AgentErrorEvent(e.toString()));
        RetrySignals.instance.clear();
        return;
      }
    }

    LoggerService.instance.i(
        'Agent 达到最大轮数限制 (${_config.maxRounds}, scenario=${_scenario.id})，发起强制总结',
        category: LogCategory.ai,
        tags: ['agent', 'max_rounds', _scenario.id]);
    messages.add(ChatMessage(
      role: 'user',
      content: '请用一句话总结你已完成的操作。',
    ));
    try {
      // 流式总结：逐 chunk emit
      await for (final chunk in _llm.chatStreamWithTools(messages: messages)) {
        if (chunk.isContent) {
          emit(TextDeltaEvent(chunk.contentChunk!));
        }
      }
    } catch (e) {
      // 总结失败也不影响
      LoggerService.instance.w(
        'Agent max_rounds 总结失败: $e',
        category: LogCategory.ai,
        tags: ['agent', 'max_rounds', 'summary_failed'],
      );
    }
    emit(const AgentDoneEvent());
    RetrySignals.instance.clear();
    LoggerService.instance.i('Agent 循环完成（达到最大轮数, scenario=${_scenario.id}）',
        category: LogCategory.ai, tags: ['agent', 'loop_end', _scenario.id]);
  }

  /// 执行单个工具调用（emit 事件 + 格式化结果 + 返回 tool 消息）。
  ///
  /// 任务 7：从原「第 5 步 for 循环体」抽出，使普通串行与 dispatch_subagent 并行
  /// 共用同一段逻辑。**保持与原循环体 100% 一致行为**（含 onProgress 节流、
  /// JSON 解析容错、截断日志、toolSuccess 判断）。
  ///
  /// 统一返回构造好的 [ChatMessage]（role: tool）。串行与并行路径都由
  /// 调用方 append 到 messages（串行原地 add、并行收集后顺序 add），
  /// 消除原 nullable 返回值 + `messagesToAppend` 双重语义的混乱。
  Future<ChatMessage> _executeSingleTool(
    ToolCall call,
    void Function(AgentEvent) emit,
    CancellationToken? cancellationToken,
  ) async {
    LoggerService.instance.d('工具调度: ${call.name} (scenario=${_scenario.id})',
        category: LogCategory.ai,
        tags: ['agent', 'tool', call.name, _scenario.id]);
    emit(ToolCallStartEvent(call.name, call.arguments, call.id));

    // 流式进度节流：仅 create_chapter / update_chapter_content 这类
    // 内部走 LLM 流式的工具会触发 onProgress 回调。
    // - 首个非空 chunk 必发，避免短章节全程无进度
    // - 之后每累计 100 字发一次（一章 ~3000 字约 30 次，UI 刷新可控）
    // - 流结束不强制最后一次 emit：紧随其后的 ToolCallEndEvent 会切到 completed
    const progressThreshold = 100;
    var lastEmittedChars = 0;
    var firstProgressEmitted = false;

    // 执行工具（委托给场景），流式进度按 100 字节流上报
    final rawResult = await _scenario.executeTool(
      call.name,
      call.arguments,
      onProgress: (n) {
        if (!firstProgressEmitted) {
          firstProgressEmitted = true;
          lastEmittedChars = n;
          emit(ToolProgressEvent(call.id, n));
        } else if (n - lastEmittedChars >= progressThreshold) {
          lastEmittedChars = n;
          emit(ToolProgressEvent(call.id, n));
        }
      },
      toolCallId: call.id, // 任务 7 透传父 toolCallId，供 dispatch_subagent 用
    );

    // 工具结果格式化：截断逻辑委托给 ToolResultFormatter。
    // llm = 合法 JSON（可能截断），给 LLM；full = 完整版，给 DB。
    Map<String, dynamic> result;
    try {
      result = jsonDecode(rawResult) as Map<String, dynamic>;
    } catch (_) {
      LoggerService.instance.w(
        '工具结果 JSON 解析失败: ${call.name}, raw=${rawResult.length}字符',
        category: LogCategory.ai,
        tags: ['agent', 'tool', call.name, 'json_parse_failed'],
      );
      result = {'raw': rawResult};
    }

    final formatted = _toolResultFormatter.format(result);
    final resultStr = formatted.llm;
    final fullResultStr = formatted.full;

    if (resultStr.length < fullResultStr.length) {
      LoggerService.instance.d(
        '工具结果截断: ${call.name} originalLen=${fullResultStr.length} → ${resultStr.length}',
        category: LogCategory.ai,
        tags: ['agent', 'tool', call.name, 'truncated'],
      );
    }

    final toolMessage = ChatMessage(
      role: 'tool',
      content: resultStr,
      toolCallId: call.id,
    );

    final toolSuccess = !result.containsKey('error');
    emit(ToolCallEndEvent(
      call.name,
      call.id,
      resultStr,
      fullResult: fullResultStr,
      success: toolSuccess,
    ));
    LoggerService.instance.i(
        '工具完成: ${call.name} (success=$toolSuccess, resultLen=${resultStr.length}, fullLen=${fullResultStr.length}, scenario=${_scenario.id})',
        category: LogCategory.ai,
        tags: [
          'agent',
          'tool',
          call.name,
          toolSuccess ? 'success' : 'error',
          _scenario.id
        ]);

    return toolMessage;
  }
}

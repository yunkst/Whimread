/// ScenarioSession 的消息链与事件路由单元（part of scenario_session.dart）
///
/// 同库 mixin：方法体引用的 `_pendingSegments` / `_state` / `_agentMessages`
/// 等私有成员由应用方 [ScenarioSession] 提供（同库可见）。抽成单元仅为组织性
/// 拆分：把「事件 → _pendingSegments → 消息链 → 落库」这条链路的全部处理
/// 集中在一个文件里读，便于核对 AgentLoop 库头声明的消息链四方同步不变量
/// （新增事件分支请落在这里）。
part of 'scenario_session.dart';

mixin ScenarioSessionMessageChain {
  // 应用方（ScenarioSession）提供的依赖——本单元的全部外部接触面：
  // 事件路由读写的待定稿段、状态镜像、消息链、持久化与运行态标记。
  List<AgentChatSegment> get _pendingSegments;
  AgentChatState get _state;
  set _state(AgentChatState value);
  List<ChatMessage> get _agentMessages;
  List<AgentChatMessage> get _uiMessages;
  AgentSessionPersistence get _persistence;
  int? get _sessionId;
  bool get _isTokenCancelled;
  set _isTokenCancelled(bool value);
  set _failedRoundStartIndex(int? value);
  set _isRunning(bool value);
  set _lifecycle(SessionLifecycle value);
  StreamSubscription<AgentEvent>? get _agentSub;
  set _agentSub(StreamSubscription<AgentEvent>? value);
  void _maybeCompleteRewriteCompleter({String? error});
  Future<CurrentNovel?> selectNovel(int novelId);
  String get scenarioId;
  void _notifyStateChanged();


  void _handleAgentEvent(AgentEvent event) {
    if (!shouldMainSessionHandleEvent(event, _sessionId?.toString())) {
      return; // 子 Agent 或别 session 事件：主 session 忽略
    }
    switch (event) {
      case TextDeltaEvent e:
        if (_pendingSegments.isNotEmpty &&
            _pendingSegments.last is TextSegment) {
          final idx = _pendingSegments.length - 1;
          final last = _pendingSegments[idx] as TextSegment;
          _pendingSegments[idx] = TextSegment(last.content + e.text);
        } else {
          _pendingSegments.add(TextSegment(e.text));
        }
        _state = _state.copyWith(
          streamingSegments:
              List<AgentChatSegment>.unmodifiable(_pendingSegments),
        );

      case ToolCallStartEvent e:
        final call = AgentToolCall(
          id: e.toolCallId,
          name: e.name,
          arguments: e.args,
          status: AgentToolStatus.running,
        );
        _pendingSegments.add(ToolCallSegment(call));
        _state = _state.copyWith(
          streamingSegments:
              List<AgentChatSegment>.unmodifiable(_pendingSegments),
        );

      case ToolCallEndEvent e:
        final idx = _pendingSegments.indexWhere(
          (s) => s is ToolCallSegment && s.call.id == e.toolCallId,
        );
        if (idx >= 0) {
          final old = (_pendingSegments[idx] as ToolCallSegment).call;
          _pendingSegments[idx] = ToolCallSegment(old.copyWith(
            status:
                e.success ? AgentToolStatus.completed : AgentToolStatus.error,
            // 落库用 fullResult（完整原始），UI 展示也用 fullResult（信息更全）
            result: e.fullResult ?? e.result,
            // 工具结束：清空 running 期间的瞬时进度，避免 completed 后残留旧字数
            clearProgress: true,
          ));
        }
        if (e.success &&
            (e.name == 'select_novel' || e.name == 'create_novel')) {
          _handleSelectNovelFromResult(e.result);
        }
        _state = _state.copyWith(
          streamingSegments:
              List<AgentChatSegment>.unmodifiable(_pendingSegments),
        );

      case ToolProgressEvent e:
        // 流式生成中：更新对应 running 态工具卡片的已生成字符数
        final idx = _pendingSegments.indexWhere(
            (s) => s is ToolCallSegment && s.call.id == e.toolCallId);
        if (idx >= 0) {
          final old = (_pendingSegments[idx] as ToolCallSegment).call;
          // 防乱序：进度事件可能晚于 end 到达，仅更新仍处于 running 态的卡片
          if (old.status == AgentToolStatus.running) {
            _pendingSegments[idx] =
                ToolCallSegment(old.copyWith(progressChars: e.generatedChars));
            _state = _state.copyWith(
              streamingSegments:
                  List<AgentChatSegment>.unmodifiable(_pendingSegments),
            );
          }
        }

      case DraftDiscardedEvent e:
        // 【后悔重置】：清掉被撤回的待定稿段——它们已被 loop 从消息链
        // 移除，若不清，回合收尾 finalize 时会汇总写回 _agentMessages/DB，
        // "撤回"失效（玩家会看到作废内容）。
        if (_pendingSegments.isNotEmpty) {
          final ids = e.toolCallIds.toSet();
          _pendingSegments.removeWhere(
            (s) => s is ToolCallSegment && ids.contains(s.call.id),
          );
          _state = _state.copyWith(
            streamingSegments:
                List<AgentChatSegment>.unmodifiable(_pendingSegments),
          );
        }

      case ReasoningDeltaEvent():
        // No-op：思维链仅服务文字游戏"GM 思考"开关（游玩页自订阅事件流），
        // 不落库不进消息链，通用聊天不展示。
        break;

      case CompactionEvent e:
        _handleCompaction(e);

      case AgentDoneEvent _:
        _failedRoundStartIndex = null;
        if (_isTokenCancelled && _pendingSegments.isNotEmpty) {
          _finalizeAgentResponse(partial: true);
        } else {
          _finalizeAgentResponse();
        }
        _isTokenCancelled = false;
        _maybeCompleteRewriteCompleter();

      case AgentErrorEvent e:
        _finalizeAgentResponse(error: e.error, quotaExhausted: e.quotaExhausted);
        _maybeCompleteRewriteCompleter(error: e.error);

      case InjectedUserInputEvent e:
        // 运行中补充消息的 UI 计数 +1。
        // 文本本身已由 sendMessage running 分支 append 到 _agentMessages 并落库，
        // service.injectUserMessage 已把它投到 loop 待 drain 队列；
        // 此处仅更新计数让 UI 展示"已补充 N 条"。不重复 add _agentMessages。
        //
        // 二次过滤：events 是 broadcast 流，多 ScenarioSession 都监听；
        // 只把本 scenario 的 inject 计入本 session（runId 已被
        // shouldMainSessionHandleEvent 放行，这里按 scenarioId 再卡一道）。
        if (e.scenarioId != null && e.scenarioId != scenarioId) break;
        _state = _state.copyWith(
          supplementaryCount: _state.supplementaryCount + 1,
        );

      case RetryEvent e:
        // 回合级网络重试：本轮流式已 emit 的 partial 文本作废（重试后 LLM
        // 会重新输出完整版）。从 _pendingSegments 末尾 TextSegment 砍掉
        // e.emittedChars 个字符，避免两段文本拼接进同一 assistant 消息。
        _truncatePendingText(e.emittedChars);
        _state = _state.copyWith(
          streamingSegments:
              List<AgentChatSegment>.unmodifiable(_pendingSegments),
        );
    }
    _notifyStateChanged();
  }

  /// 完成 Agent 响应 — 把 _pendingSegments 重建为 agent messages 并落库
  ///
  /// 重建规则（一个回合可能含多段 assistant/tool 交替）：
  /// - TextSegment 累积为当前 assistant 的 content
  /// - ToolCallSegment 触发 flush 当前 assistant（含已累积 toolCalls）+ 追加 tool 消息
  /// - [partial]=true（用户取消）时，running 状态的 tool_call 不追加 tool 消息
  void _finalizeAgentResponse({String? error, bool partial = false, bool quotaExhausted = false}) {
    if (error != null) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] Agent 错误: $error',
        category: LogCategory.ai,
        tags: ['session', 'agent-error', scenarioId],
      );
      // 失败轮起点 = 最后一条 user 索引 + 1（保留 user，砍除失败轮 partial/assistant/tool）
      // addAll 之前记录，避免被本轮 finalize 出来的 newMessages 污染
      int lastUserIdx = -1;
      for (int i = _agentMessages.length - 1; i >= 0; i--) {
        if (_agentMessages[i].role == 'user') {
          lastUserIdx = i;
          break;
        }
      }
      _failedRoundStartIndex = lastUserIdx >= 0 ? lastUserIdx + 1 : null;
    }

    final newMessages = <ChatMessage>[];
    var pendingText = StringBuffer();
    var pendingToolCalls = <ToolCall>[];

    void flushAssistant() {
      final hasText = pendingText.isNotEmpty;
      final hasCalls = pendingToolCalls.isNotEmpty;
      if (!hasText && !hasCalls) return;
      newMessages.add(ChatMessage(
        role: 'assistant',
        content: hasText ? pendingText.toString() : null,
        toolCalls: hasCalls ? List<ToolCall>.from(pendingToolCalls) : null,
      ));
      pendingText = StringBuffer();
      pendingToolCalls = [];
    }

    for (final seg in _pendingSegments) {
      if (seg is TextSegment) {
        pendingText.write(seg.content);
      } else if (seg is ToolCallSegment) {
        final call = seg.call;
        pendingToolCalls.add(ToolCall(
          id: call.id,
          name: call.name,
          arguments: call.arguments,
        ));
        flushAssistant();
        if (call.status == AgentToolStatus.completed ||
            call.status == AgentToolStatus.error) {
          newMessages.add(ChatMessage(
            role: 'tool',
            content: call.result ?? '',
            toolCallId: call.id,
          ));
        }
      }
    }
    flushAssistant();

    _agentMessages.addAll(newMessages);

    _state = _state.copyWith(
      messages: _uiMessages,
      isLoading: false,
      streamingSegments: const [],
      error: error,
      quotaExhausted: quotaExhausted,
    );
    _pendingSegments.clear();
    _isRunning = false;
    _agentSub?.cancel();
    _agentSub = null;
    _lifecycle = SessionLifecycle.idle;
    _notifyStateChanged();

    if (newMessages.isNotEmpty) {
      unawaited(_persistence.persistAgentMessages(newMessages, partial: partial));
    }
  }

  /// 从 _pendingSegments 末尾 TextSegment 砍掉 [chars] 个字符。
  ///
  /// RetryEvent 消费用：回合重试时丢弃本轮已作废的 partial 流式文本。
  /// 与 TextDeltaEvent 的追加规则对称——本轮 partial 一定累积在末尾
  /// TextSegment（可能与之前轮次的完整文本同段，如场景注入钩子后的下一轮
  /// 失败），故按字符数精确截断而非整段删除。剩余为空则移除该段。
  void _truncatePendingText(int chars) {
    if (chars <= 0 || _pendingSegments.isEmpty) return;
    final last = _pendingSegments.last;
    if (last is! TextSegment) return; // 本轮无 TextDelta（chars 应为 0），防御
    final remaining = last.content.length - chars;
    if (remaining > 0) {
      _pendingSegments[_pendingSegments.length - 1] =
          TextSegment(last.content.substring(0, remaining));
    } else {
      _pendingSegments.removeLast();
    }
  }

  /// 解析 select_novel / create_novel 工具返回的 JSON，自动同步 currentNovel
  void _handleSelectNovelFromResult(String? result) {
    if (result == null) return;
    try {
      final parsed = jsonDecode(result) as Map<String, dynamic>;
      if (parsed['success'] != true) return;
      final novelId = parsed['novelId'] as int?;
      if (novelId == null) return;
      selectNovel(novelId);
    } catch (e) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 解析 select_novel 结果失败: $result',
        category: LogCategory.ai,
        tags: ['session', 'select_novel', 'parse_failed', scenarioId],
      );
    }
  }

  /// 处理上下文压缩事件 — 同步裁剪内存 + apply 预剪枝改写 + 删/重写 DB
  void _handleCompaction(CompactionEvent e) {
    final cut = e.droppedAgentFromIndex;
    if (cut <= 0) {
      LoggerService.instance.i(
        'ScenarioSession [$scenarioId] 收到压缩事件(无裁剪): ${e.description}',
        category: LogCategory.ai,
        tags: ['session', 'compaction', scenarioId],
      );
      return;
    }
    final removed = cut.clamp(0, _agentMessages.length);

    // 1) 先 removeRange 丢弃前缀
    _agentMessages.removeRange(0, removed);

    // 2) 头部插入压缩提示 system 消息（_agentMessages 不含 sys_prompt，
    //    压缩提示独占头部 index 0）。KV 文本由 ContextCompactor 生成、
    //    CompactionEvent.compactionNote 透传；落库时该条落到 agentMsgIndex=0。
    //    rewrittenContent 的落点换算见下方步骤 3（marker insert 使压缩后
    //    索引为 `压缩前 index - cut + 1`）。
    _agentMessages.insert(0, ChatMessage(role: 'system', content: e.compactionNote));

    // 3) apply P1 预剪枝改写：rewrittenContent 的 index 基于压缩前 messages，
    //    压缩后落点 = index - cut + 1（removeRange 丢掉 [0,cut) 先平移 -cut，
    //    marker 插到头部再整体 +1）。此前误用 `- cut`：每条改写落到前一条
    //    消息上，应裁剪的超长 tool 结果没裁，反而改坏它前面那条。
    //    落在丢弃段（index < cut）的 entry 已随 removeRange 消失，无须处理。
    int appliedRewrite = 0;
    for (final entry in e.rewrittenContent) {
      if (entry.index < cut) continue;
      final newIdx = entry.index - cut + 1; // +1：头部压缩提示占位
      if (newIdx < 0 || newIdx >= _agentMessages.length) continue;
      final old = _agentMessages[newIdx];
      if (old.role != 'tool') continue; // 防御性：仅改 tool result
      _agentMessages[newIdx] = ChatMessage(
        role: old.role,
        content: entry.newContent,
        name: old.name,
        toolCallId: old.toolCallId,
        toolCalls: old.toolCalls,
      );
      appliedRewrite++;
    }

    _state = _state.copyWith(messages: _uiMessages);
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 压缩裁剪: 移除前 $removed 条 agent 消息, '
      '头部插入压缩提示, 改写 $appliedRewrite 条 tool result, 剩余 ${_agentMessages.length} 条',
      category: LogCategory.ai,
      tags: ['session', 'compaction', 'trim', scenarioId],
    );
    // 4) 重写 DB：AgentSessionPersistence.rewriteAgentMessagesInDb 用
    //    replaceMessages 单事务整段重写 _agentMessages（已含 marker 头部 +
    //    改写后的 content），故 marker 自然落到 agentMsgIndex = 0。
    unawaited(_persistence.rewriteAgentMessagesInDb(cut, logTag: 'compaction_db'));
  }
}

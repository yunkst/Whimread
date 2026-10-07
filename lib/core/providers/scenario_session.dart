/// 场景会话 — 每个 scenarioId 对应一个独立运行时
///
/// v32 统一历史模型：
/// - 内部以 agent 视角的 `List<ChatMessage>`（_agentMessages）为真理源，
///   含完整 ReAct 链（system/user/assistant/tool）。
/// - DB 直接存 agent ChatMessage（chat_messages 表 v32），hydrate 时 1:1 还原。
/// - UI 通过 _projectUiMessages 把 agent messages 投影为 AgentChatMessage
///   （含 segments）；同一回合（相邻 user 之间）的连续 assistant 消息合并为
///   一条，与流式气泡结构对齐。
/// - 落库时机：user 消息即时落库；assistant 回合（含 tool 调用/结果）在
///   AgentDoneEvent/cancel 时从 _pendingSegments 重建并批量落库。
/// - 压缩 / retry / rollback 以内存为基准原子重写 DB（replaceMessages 单事务），保证内存与 DB 一致。
///
/// 隔离设计（保留）：
/// - 每个 scenarioId → 独立的 ScenarioSession
/// - 每个 ScenarioSession 有自己的 _pendingSegments、_agentSub、CancellationToken
/// - 切场景不杀 Agent，只是 UI 切到另一个 session 的视图
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/paragraph_annotation.dart';
import '../../repositories/chat_session_repository.dart';
import '../../services/logger_service.dart';
import '../../services/novel_agent/agent_event.dart';
import '../../services/novel_agent/compaction_note_parser.dart';
import '../../services/novel_agent/scenarios/writing_scenario.dart';
import '../../services/novel_agent/tool_result_formatter.dart';
import '../../services/novel_agent/agent_scenario.dart';
import '../../services/novel_agent/agent_scenario_factory.dart';
import '../../services/novel_agent/novel_agent_service.dart';
import '../../services/dsl_engine/llm_provider.dart' show ChatMessage, ToolCall;
import 'chat_session_providers.dart';
import 'current_novel_provider.dart';
import 'database_providers.dart';
import 'agent_chat_state.dart';
import 'agent_session_persistence.dart';
import 'ask_user_providers.dart';
import 'reading_context_providers.dart';
import 'subagent_providers.dart';
import 'webview_providers.dart';

part 'scenario_session_chain.dart';

/// 按标注重写章节的运行结果
///
/// 由 [ScenarioSession.startAnnotationRewrite] 在 agent 回合结束时计算并返回。
/// 调用方（阅读页）据此判断是否清理本章节的段落标注（已重写则清除，失败则保留以便重试）。
class AnnotationRewriteOutcome {
  /// 整体成功：LLM 至少有一次成功的 update_chapter_content 写库 + 没有致命错误。
  final bool success;

  /// 失败原因（仅 success=false 时非空）
  final String? error;

  /// 累计成功写库的 update_chapter_content 次数
  final int updateCount;

  const AnnotationRewriteOutcome({
    required this.success,
    this.error,
    this.updateCount = 0,
  });

  factory AnnotationRewriteOutcome.failure(String error) =>
      AnnotationRewriteOutcome(success: false, error: error);
}

/// 判定主 ScenarioSession 是否应处理某个 [AgentEvent]。
///
/// 任务 8 引入：子 Agent（dispatch_subagent 派出）事件已被 EventTagger 打 runId
/// 后发到全局 `agentService.events` 流，主 ScenarioSession 不能再无差别吸收这些
/// 事件——否则子 Agent 的 TextDelta/ToolCall 会污染主对话历史。
///
/// 规则（简化版，不查 SubagentRegistry）：
/// - [AgentEvent.runId] == null：主 Agent 旧路径事件（service 不改路径）→ 处理
/// - [AgentEvent.runId] == [mainSessionId]：主 Agent 自身打标事件（预留）→ 处理
/// - 其它（带 runId 但非主）：不论是本 session 派的子 Agent 还是别 session 的事件，
///   一律忽略。主 session 只关心"这是不是我自己的事件"。
///
/// [mainSessionId] 为 null 时，只有 runId == null 的事件会被处理；任何带 runId
/// 的事件都被视为子/外部事件而忽略。当前主 Agent 事件 runId 始终为 null，
/// 传 null 仍然正确。
bool shouldMainSessionHandleEvent(AgentEvent event, String? mainSessionId) {
  final runId = event.runId;
  if (runId == null) return true; // 主 Agent 旧路径
  if (runId == mainSessionId) return true; // 主 Agent 自身打标（预留）
  return false; // 子 Agent 或别 session 事件
}

/// 场景会话生命周期状态
enum SessionLifecycle {
  fresh,
  active,
  idle,
  disposed,
}

/// 场景会话 — 每个场景的独立运行时
class ScenarioSession with ScenarioSessionMessageChain {
  @override
  final String scenarioId;
  final Ref _ref;

  /// 当前会话 id（可空：用户从未建过 session / 还没从 DB 选中）
  @override
  int? _sessionId;
  int? get sessionId => _sessionId;

  // ===== agent 视角历史（v32 真理源）=====
  /// 完整 ReAct 链：system(运行时注入不存)/user/assistant/tool。
  /// hydrate 时从 DB 1:1 还原；运行时由 agent 事件流增量更新。
  @override
  final List<ChatMessage> _agentMessages = [];

  /// visibleForTesting：暴露内部 agent 消息列表供测试断言。
  @visibleForTesting
  List<ChatMessage> get agentMessages => List.unmodifiable(_agentMessages);

  // ===== 运行时状态 =====
  bool _isRunning = false;
  @override
  bool _isTokenCancelled = false;
  @override
  final List<AgentChatSegment> _pendingSegments = [];
  @override
  StreamSubscription<AgentEvent>? _agentSub;

  /// 失败轮 partial 起点（_agentMessages 索引）：finalize error 时记录为「最后一条 user 索引 + 1」
  /// retryLastRound 据此砍除失败轮残留。AgentDoneEvent 时清空。
  int? _failedRoundStartIndex;

  // ===== 标注重写（仅 annotation_rewrite 场景使用） =====
  /// 本会话正在跑的标注重写目标（仅 annotation_rewrite 场景在改写运行时设置）。
  /// [_buildScenarioContext] 据此把 rewriteTarget 注入 AgentScenarioContext，
  /// factory 据此构造 AnnotationRewriteScenario 把工具锁死在目标章节上。
  AnnotationRewriteTarget? _pendingRewriteTarget;

  /// 标注重写结果的等待器（startAnnotationRewrite 在 run 启动时设置，
  /// 由 finalize / cancel 路径完成后填充 AnnotationRewriteOutcome 后置 null）。
  Completer<AnnotationRewriteOutcome>? _rewriteCompleter;

  /// 标注重写本轮的起始 agent 消息索引（含本轮 user）。finalize 后从该索引起扫描
  /// _agentMessages 计算成功 update 次数；用来排除历史轮次对本轮结果的干扰。
  int? _rewriteStartAgentIndex;

  // ===== 会话状态 =====
  @override
  late AgentChatState _state;
  SessionLifecycle _lifecycle = SessionLifecycle.fresh;

  /// DB 持久化协作类（从本类拆出，见 agent_session_persistence.dart）。
  /// 通过闭包直接读本类的活状态（sessionId / _currentNovel / _agentMessages），
  /// 不复制列表，保证重写 DB 时看到的与内存真理源一致。
  @override
  late final AgentSessionPersistence _persistence = AgentSessionPersistence(
    ref: _ref,
    scenarioId: scenarioId,
    sessionId: () => _sessionId,
    currentNovel: () => _currentNovel,
    agentMessages: () => _agentMessages,
  );

  // ===== 当前小说（按 Session 隔离）=====
  CurrentNovel? _currentNovel;

  // ===== 状态变更通知回调 =====
  VoidCallback? _onStateChanged;

  ScenarioSession({
    required this.scenarioId,
    required Ref ref,
    int? initialSessionId,
  })  : _ref = ref,
        _sessionId = initialSessionId {
    final info = AgentScenarioFactory.availableScenarios
        .where((s) => s.id == scenarioId)
        .firstOrNull;
    _state = AgentChatState(
      scenarioId: scenarioId,
      scenarioDisplayName: info?.displayName ?? scenarioId,
    );
  }

  /// UI 视图消息：从 _agentMessages 投影出 user/assistant（含 segments）。
  @override
  List<AgentChatMessage> get _uiMessages => _projectUiMessages(_agentMessages);

  /// 把 user 消息的 content（可能含图片占位文本）解析成 segments。
  /// 占位文本 [用户上传了图片 mediaId=xxx] → ImageSegment；其余文本 → TextSegment。
  static List<AgentChatSegment> _parseUserSegments(String content) {
    final segments = <AgentChatSegment>[];
    int lastEnd = 0;
    for (final match in _imagePlaceholderRe.allMatches(content)) {
      // 占位之前的文本（非空才加）
      if (match.start > lastEnd) {
        final text = content.substring(lastEnd, match.start).trim();
        if (text.isNotEmpty) segments.add(TextSegment(text));
      }
      segments.add(ImageSegment(mediaId: match.group(1)!));
      lastEnd = match.end;
    }
    // 尾部剩余文本
    if (lastEnd < content.length) {
      final text = content.substring(lastEnd).trim();
      if (text.isNotEmpty) segments.add(TextSegment(text));
    }
    if (segments.isEmpty) return [TextSegment(content)];
    return segments;
  }

  /// 投影：agent ChatMessage 列表 → UI AgentChatMessage 列表
  ///
  /// 规则：
  /// - system：压缩提示（[上下文压缩|...]）→ AgentChatRole.marker；
  ///   其余 system（sys_prompt 等）跳过。
  /// - user：直接转 AgentChatMessage.user，同时充当回合边界。
  /// - assistant：同一回合（相邻两条 user 之间）的连续 assistant 消息合并为
  ///   一条 AgentChatMessage，segments 按时序拼接（text → tool → text → …），
  ///   与流式态 _pendingSegments 的结构一致，避免回合结束时一个气泡被
  ///   LLM 协议的轮次边界拆成多个气泡。
  /// - tool：已被前一个 assistant 吸收，跳过。
  @visibleForTesting
  static List<AgentChatMessage> projectUiMessagesForTest(List<ChatMessage> msgs) =>
      _projectUiMessages(msgs);

  static List<AgentChatMessage> _projectUiMessages(
      List<ChatMessage> agentMsgs) {
    final ui = <AgentChatMessage>[];

    /// 当前回合的 segments 累积（两条 user / marker 之间）；null = 无进行中回合
    List<AgentChatSegment>? turnSegments;

    void flushTurn() {
      final segs = turnSegments;
      turnSegments = null;
      if (segs == null || segs.isEmpty) return;
      ui.add(AgentChatMessage.assistantFromSegments(segs));
    }

    for (var i = 0; i < agentMsgs.length; i++) {
      final m = agentMsgs[i];
      switch (m.role) {
        case 'system':
          // 压缩提示 system → marker（同时切断当前回合合并组）；
          // 其余 system（sys_prompt 等）仍 continue
          final note = CompactionNoteParser.parse(m.content ?? '');
          if (note != null) {
            flushTurn();
            ui.add(AgentChatMessage.compactionMarker(note));
          }
          continue;
        case 'user':
          flushTurn();
          ui.add(AgentChatMessage.userFromSegments(
              _parseUserSegments(m.content ?? '')));
          break;
        case 'assistant':
          final segs = turnSegments ??= <AgentChatSegment>[];
          if (m.content != null && m.content!.isNotEmpty) {
            segs.add(TextSegment(m.content!));
          }
          for (final tc in m.toolCalls ?? const <ToolCall>[]) {
            final toolMsg = _findToolResult(agentMsgs, i, tc.id);
            segs.add(ToolCallSegment(AgentToolCall(
              id: tc.id,
              name: tc.name,
              arguments: tc.arguments,
              status: toolMsg != null
                  ? AgentToolStatus.completed
                  : AgentToolStatus.running,
              result: toolMsg?.content,
            )));
          }
          break;
        case 'tool':
          // 已被 assistant 吸收
          break;
        default:
          break;
      }
    }
    flushTurn();
    return ui;
  }

  /// 从 fromIndex+1 开始找 role='tool' 且 toolCallId 匹配的消息
  static ChatMessage? _findToolResult(
      List<ChatMessage> msgs, int fromIndex, String toolCallId) {
    for (var i = fromIndex + 1; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.role == 'tool' && m.toolCallId == toolCallId) return m;
      if (m.role == 'assistant' || m.role == 'user') break;
    }
    return null;
  }

  /// 由 ScenarioSessionsNotifier 在 UI 切换 sessionId 时调用。仅在确实改变时清空并重新 hydrate。
  ///
  /// 同 scenario 切不同 sessionId 时必须中断老 agent——避免流式 segment
  /// 落进新 sessionId 的内存/DB 造成数据污染。cancel 时 _sessionId 仍是老的，
  /// partial 正确落库到老会话历史。
  /// 跨 scenario 切场景不杀 Agent（by design，UI 切的是另一个 ScenarioSession 实例）。
  Future<void> adoptSession(int? newSessionId) async {
    if (_sessionId == newSessionId) return;

    // 运行中切会话：先 cancel 老 agent，避免数据污染
    if (_isRunning) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] adoptSession 时中断老 agent, '
        'oldSessionId=$_sessionId → newSessionId=$newSessionId',
        category: LogCategory.ai,
        tags: ['session', 'adopt', 'interrupt', scenarioId],
      );
      await cancel();
    }

    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 切换 sessionId $_sessionId → $newSessionId',
      category: LogCategory.ai,
      tags: ['session', 'switch', scenarioId],
    );
    _sessionId = newSessionId;
    _pendingSegments.clear();
    _agentMessages.clear();
    _lifecycle = SessionLifecycle.fresh;

    // 小说上下文跟随会话走：从 DB 恢复目标会话持久化的 currentNovelId，
    // 而不是一律清空（切历史会话后 LLM 才知道原本书在写哪本）。
    // newSessionId == null 表示开启全新会话，无上下文可恢复，保持清空。
    CurrentNovel? restoredNovel;
    if (newSessionId != null) {
      try {
        final row = await _ref
            .read(chatSessionRepositoryProvider)
            .getSession(newSessionId);
        final novelId = row?.currentNovelId;
        if (novelId != null) {
          restoredNovel = await loadNovel(_ref, novelId);
        }
      } catch (e, st) {
        LoggerService.instance.e(
          'ScenarioSession [$scenarioId] adoptSession 恢复 currentNovel 失败: $e',
          stackTrace: st.toString(),
          category: LogCategory.ai,
          tags: ['session', 'adopt', 'novel', 'failed', scenarioId],
        );
      }
    }
    // 打开历史会话 = 切换工作上下文：恢复的小说同时写入全局选择，
    // 让「当前选择的小说」始终等于用户正在操作的会话的小说
    //（原 issue #24 的「恢复不写全局」决策已按新需求反转；
    // 工具读取仍走会话私有的 _currentNovel，全局仅作为 UI/选择状态）。
    _ref.read(currentNovelProvider.notifier).state = restoredNovel;
    _currentNovel = restoredNovel;
    _state = _state.copyWith(
      messages: const [],
      isLoading: false,
      streamingSegments: const [],
      error: null,
      currentNovel: restoredNovel,
      clearCurrentNovel: restoredNovel == null,
    );
    _notifyStateChanged();
  }

  /// 如果 _sessionId 不为空且 _agentMessages 为空，主动从 DB 加载。
  Future<void> hydrateIfNeeded() async {
    final sid = _sessionId;
    if (sid == null) return;
    if (_agentMessages.isNotEmpty) return;
    try {
      final repo = _ref.read(chatSessionRepositoryProvider);
      final session = await repo.getSession(sid);
      if (session == null) {
        LoggerService.instance.w(
          'ScenarioSession [$scenarioId] hydrate 失败：sessionId=$sid 不存在',
          category: LogCategory.ai,
          tags: ['session', 'hydrate', 'missing', scenarioId],
        );
        return;
      }
      final records = await repo.listMessages(sid);
      _agentMessages.clear();
      for (final r in records) {
        _agentMessages.add(r.toAgentMessage());
      }
      // 恢复小说上下文：内存已有值优先（用户可能在 fire-and-forget hydrate
      // 完成前刚选了书，不能被竞态抹掉）；否则从 DB 持久值恢复；
      // 两处都没有（从未选过 / 小说已删除）才清空。
      // loadNovel 的 await 期间用户/工具可能已调用 selectNovel 抢先改写
      // 内存，返回后必须再读一次内存、非空则保留（issue #22 双向守卫）。
      var novel = _currentNovel;
      if (novel == null && session.currentNovelId != null) {
        final restored = await loadNovel(_ref, session.currentNovelId!);
        novel = _currentNovel ?? restored;
        // 从 DB 恢复成功且未被并发选书抢占 → 全局选择跟随会话
        //（与 adoptSession 一致；identical 排除了"内存已有值"分支）
        if (identical(novel, restored)) {
          _ref.read(currentNovelProvider.notifier).state = novel;
        }
      }
      _currentNovel = novel;
      _state = _state.copyWith(
        messages: _uiMessages,
        currentNovel: novel,
        clearCurrentNovel: novel == null,
        scenarioDisplayName: _state.scenarioDisplayName,
      );
      LoggerService.instance.i(
        'ScenarioSession [$scenarioId] hydrate sessionId=$sid '
        '→ ${_agentMessages.length} 条 agent 消息, novel=${novel?.title ?? "无"}',
        category: LogCategory.ai,
        tags: ['session', 'hydrate', 'success', scenarioId],
      );
      _notifyStateChanged();
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] hydrate 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'hydrate', 'failed', scenarioId],
      );
    }
  }

  /// 冷启动用：sessionId 未知时选最近 session 再 hydrate，找不到则保持空白等用户发消息。
  ///
  /// 注意：此路径只服务"刚进入 scenario 时展示上次聊到哪"的冷启动场景。
  /// 发消息路径走 [_ensureSessionId]，不复用最近 session，避免把新对话悄悄并入旧会话。
  Future<void> hydrateFromRecentIfNeeded() async {
    if (_sessionId != null) {
      await hydrateIfNeeded();
      return;
    }
    if (_agentMessages.isNotEmpty) return;
    try {
      final repo = _ref.read(chatSessionRepositoryProvider);
      final list = await repo.listSessionsByScenario(scenarioId, limit: 1);
      if (list.isEmpty) return;
      _sessionId = list.first.id;
      _ref.read(currentChatSessionIdProvider(scenarioId).notifier).state =
          _sessionId;
      LoggerService.instance.i(
        'ScenarioSession [$scenarioId] 复用最近 session id=$_sessionId',
        category: LogCategory.ai,
        tags: ['session', 'reuse', scenarioId],
      );
      await hydrateIfNeeded();
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] hydrateFromRecentIfNeeded 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'hydrate_recent', 'failed', scenarioId],
      );
    }
  }

  /// 发消息用：已有 sessionId 则沿用，否则强制新建——绝不隐式复用"最近一个 session"。
  ///
  /// 设计原因：若发消息时复用 updatedAt 最近的 session，会把用户预期中的"新对话"
  /// 悄悄追加进上一段可能完全无关的旧会话（甚至跨小说上下文错位），违背用户直觉。
  /// 想继续旧对话请走历史列表显式切换。
  Future<void> _ensureSessionId() async {
    if (_sessionId != null) {
      await hydrateIfNeeded();
      return;
    }
    try {
      final repo = _ref.read(chatSessionRepositoryProvider);
      // 会话名 = 当前选中的小说（用户可随时手动重命名覆盖）
      final id = await repo.createSession(ChatSession(
        scenarioId: scenarioId,
        title: _currentNovel?.title ?? '',
        currentNovelId: _currentNovel?.id,
        currentNovelTitle: _currentNovel?.title,
      ));
      _sessionId = id;
      _ref.read(currentChatSessionIdProvider(scenarioId).notifier).state = id;
      LoggerService.instance.i(
        'ScenarioSession [$scenarioId] 发消息新建 session id=$id',
        category: LogCategory.ai,
        tags: ['session', 'create', 'send', scenarioId],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] _ensureSessionId 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'ensure_id', 'failed', scenarioId],
      );
    }
  }

  AgentChatState get state => _state;
  bool get isRunning => _isRunning;
  SessionLifecycle get lifecycle => _lifecycle;
  CurrentNovel? get currentNovel => _currentNovel;

  void setOnStateChanged(VoidCallback? callback) {
    _onStateChanged = callback;
  }

  /// 占位文本契约：用户上传图片时拼进 content，供 agent 识别 + 投影层还原。
  /// 格式：[用户上传了图片 mediaId=<mediaId>]
  static final RegExp _imagePlaceholderRe =
      RegExp(r'\[用户上传了图片 mediaId=([^\]]+)\]');

  /// 发送消息 — Agent 在本 session 内独立运行
  ///
  /// A 方案：运行中不再 cancel 落 partial，改为把 user 消息落库 +
  /// 投到 service 的 inject 队列，让下一轮 LLM 调用看到（不打断当前轮）。
  /// 非运行中保持原逻辑（_beginAgentRun）。
  Future<void> sendMessage({
    required String content,
    List<String> imageMediaIds = const [],
  }) async {
    final text = content.trim();
    if (text.isEmpty && imageMediaIds.isEmpty) return;

    await _ensureSessionId();

    // 拼接 agent 视角 content：图片占位文本（图在前）+ 用户原文
    final buf = StringBuffer();
    for (final id in imageMediaIds) {
      buf.writeln('[用户上传了图片 mediaId=$id]');
    }
    if (text.isNotEmpty) {
      buf.write(text);
    }
    final agentContent = buf.toString().trim();

    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 发送消息: length=${agentContent.length} '
      'images=${imageMediaIds.length} sessionId=$_sessionId running=$_isRunning',
      category: LogCategory.ai,
      tags: ['session', 'send', scenarioId],
    );

    // user 消息即时进 _agentMessages + 落库（与现状一致；A 方案下这是
    // 即时落库 + 后续 inject 双轨写入，_agentMessages 不重复加）
    final userMsg = ChatMessage(role: 'user', content: agentContent);
    _agentMessages.add(userMsg);
    final isRunningNow = _isRunning;

    _state = _state.copyWith(
      messages: _uiMessages,
      isLoading: true,
      // 真正新一轮 sendMessage（非 inject）清零 supplementaryCount
      supplementaryCount: isRunningNow ? null : 0,
    );
    _notifyStateChanged();
    await _persistence.persistAgentMessage(userMsg);

    // 运行中：把 user 消息投到 service 队列，由 loop 下一轮 drain。
    // 不调 _beginAgentRun（已有 loop 在跑）。queue 立即返回 + emit 反馈事件，
    // 用户在 UI 上看到"已补充"的 supplementaryCount +1。
    //
    // 此处直接读 _isRunning（不缓存 persistAgentMessage 之前的快照），
    // 避免 AgentDoneEvent 在异步落库期间翻转标志导致的窄窗口竞态。
    if (_isRunning) {
      _ref.read(novelAgentServiceProvider).injectUserMessage(
            scenarioId,
            agentContent,
          );
      return;
    }

    await _beginAgentRun(agentContent);
  }

  /// ask_user 工具的 UI 作答入口
  ///
  /// 聊天卡片（AskUserCard）把用户点选/输入的结果投递给挂起的提问：
  /// 委托给 [askUserRegistryProvider] 完成对应 Completer，WritingScenario
  /// 的 ask_user 分支随即以答案 JSON 作为 tool result 返回，run 继续。
  /// 无匹配挂起项（已答过 / 已取消 / 会话重建后失效）返回 false。
  bool answerAskUser(
    String toolCallId, {
    List<String>? selected,
    String? freeText,
  }) {
    final ok = _ref.read(askUserRegistryProvider).answer(
          scenarioId: scenarioId,
          toolCallId: toolCallId,
          selected: selected,
          freeText: freeText,
        );
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] ask_user 作答 toolCallId=$toolCallId '
      'ok=$ok',
      category: LogCategory.ai,
      tags: ['session', 'ask_user', ok ? 'answered' : 'missed', scenarioId],
    );
    return ok;
  }

  /// 启动一轮 Agent 回合
  Future<void> _beginAgentRun(String userInput) async {
    _isTokenCancelled = false;
    _lifecycle = SessionLifecycle.active;
    _isRunning = true;
    _pendingSegments.clear();

    _state = _state.copyWith(
      isLoading: true,
      streamingSegments: const [],
      error: null,
    );
    _notifyStateChanged();

    try {
      await _runAgent(userInput);
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] Agent 启动失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'agent_run', 'failed', scenarioId],
      );
      _finalizeAgentResponse(error: 'Agent 启动失败: $e');
    }
  }

  /// 重试上次失败的 Agent 回合（仅重试当前这一轮 LLM 请求，保留之前成功的多轮 ReAct）。
  ///
  /// 失败轮的 partial 已通过 [_failedRoundStartIndex] 标记：
  /// - 砍除 [_failedRoundStartIndex, _agentMessages.length) 区间（失败轮残留）
  /// - 保留 [0, _failedRoundStartIndex) 即之前所有成功轮 + 失败轮的 user 消息
  /// - 同步删 DB（[AgentSessionPersistence.rewriteAgentMessagesInDb]，logTag=db_rewrite）
  /// - 调用 [_resumeAgentRun] 走 [NovelAgentService.resumeFromMessages] 续跑，
  ///   不 append user、不注入阅读上下文前缀（user 已经是 history 的一部分）。
  ///
  /// 运行中重试 = cancel 当前回合（落库 partial → finalize 错误 → _failedRoundStartIndex 被设置）
  /// → 砍除失败轮 → resumeFromMessages 续跑。
  Future<void> retryLastRound() async {
    // retry 入口（error 状态的重试按钮）此时 _isRunning 必然为 false
    // （_finalizeAgentResponse(error) 已跑、_pendingSegments 已清）。
    // 防御：若仍有残留 pending（状态错乱），落 partial 后再 retry。
    if (_pendingSegments.isNotEmpty) {
      await cancel();
    }

    final failedAt = _failedRoundStartIndex;
    if (failedAt == null) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 拒绝重试：无失败轮记录',
        category: LogCategory.ai,
        tags: ['session', 'retry', 'no_failure', scenarioId],
      );
      _notifyStateError('当前没有可重试的失败轮次');
      return;
    }

    final removedCount = _agentMessages.length - failedAt;
    _agentMessages.removeRange(failedAt, _agentMessages.length);

    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 重试：失败起点=$failedAt, '
      '删掉其后 $removedCount 条 (保留之前的成功 ReAct)',
      category: LogCategory.ai,
      tags: ['session', 'retry', scenarioId],
    );

    _state = _state.copyWith(
      messages: _uiMessages,
      streamingSegments: const [],
      error: null,
    );
    _notifyStateChanged();

    // 同步删 DB：删掉 failedAt 之后的所有消息
    await _persistence.rewriteAgentMessagesInDb(failedAt, logTag: 'db_rewrite');

    // 在触发新一轮前清空失败标记，避免 resume 失败时 finalize 再次覆盖到已被砍掉的位置
    _failedRoundStartIndex = null;

    await _resumeAgentRun();
  }

  /// 重试单个工具调用 — 用新结果原地覆盖旧 tool 消息（不触发新一轮 LLM 思考）。
  ///
  /// 调用入口：UI 在已结束工具卡片（completed / error / rejected）上点击「重试」。
  ///
  /// 行为契约：
  /// - name / arguments / toolCallId **完全不变**（assistant.toolCalls[i].id 关联的就是它）
  /// - 重新执行工具，结果经 [ToolResultFormatter] 截断为 `formatted.llm`，与
  ///   [AgentLoop._executeSingleTool] 落库路径完全一致——保证「用户看到 = LLM 看到」
  /// - 同步更新三处：内存 `_agentMessages`、UI `_state.messages`、DB `chat_messages.content`
  /// - select_novel / create_novel 重试成功后同步 `_currentNovel`（与正常 ToolCallEndEvent 一致）
  ///
  /// 边界：
  /// - 运行中先 [cancel] 落 partial（interrupt-then-act），保证内存与 DB 索引对齐
  /// - dispatch_subagent 不走本路径（UI 渲染 SubagentToolCard，根本不显示重试按钮）
  /// - webview_extract 场景工具不支持重试（页面 DOM 状态已不可知，重试无意义）
  Future<void> retryToolCall(String toolCallId) async {
    // 阶段一：防御取消。retry 入口此时 _isRunning 必然为 false（工具卡片重试
    // 按钮仅在非 loading 完成态显示）；若有残留 pending，落 partial 后再操作。
    if (_pendingSegments.isNotEmpty) {
      await cancel();
    }

    final sid = _sessionId;
    if (sid == null) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 拒绝重试工具：无 sessionId',
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'no_session', scenarioId],
      );
      _notifyStateError('当前会话未保存，无法重试');
      return;
    }

    // 阶段二：倒查目标（assistant 上的 toolCall + 紧随其后的 tool 消息）
    final located = _locateRetryToolCall(toolCallId);
    if (located == null) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 重试失败：找不到 toolCallId=$toolCallId',
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'not_found', scenarioId],
      );
      _notifyStateError('找不到该工具调用');
      return;
    }
    final toolName = located.toolName;
    final toolIdx = located.toolIdx;
    if (toolIdx == null) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 重试失败：toolCallId=$toolCallId 无对应 tool 消息',
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'no_tool_msg', scenarioId],
      );
      _notifyStateError('该工具调用没有结果可替换');
      return;
    }
    // 防御：dispatch_subagent 不走本路径
    if (toolName == 'dispatch_subagent') {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 拒绝重试 dispatch_subagent',
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'subagent_rejected', scenarioId],
      );
      return;
    }
    // 防御：ask_user 不走本路径——历史提问没有"重问用户"的意义
    // （用户当轮已答过或已取消，重新提问只会插入一条孤儿 tool 消息）
    if (toolName == 'ask_user') {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 拒绝重试 ask_user',
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'ask_user_rejected', scenarioId],
      );
      return;
    }
    // 防御：webview_extract 场景工具不支持重试
    if (scenarioId == ScenarioIds.webviewExtract) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 拒绝重试 webview_extract 工具 $toolName',
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'webview_rejected', scenarioId],
      );
      _notifyStateError('网页提取工具依赖当前页面状态，无法重试');
      return;
    }
    // 防御：text_game 场景工具不支持重试——重试路径以 WritingScenario 重建
    // 执行器，游戏工具不在其工具面，会把消息改写成 unknown_tool 污染剧情
    if (scenarioId == ScenarioIds.textGame) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 拒绝重试 text_game 工具 $toolName',
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'text_game_rejected', scenarioId],
      );
      _notifyStateError('文字游戏工具不支持重试');
      return;
    }

    // 从 DB 取该 tool 消息的主键 id（内存 ChatMessage 不带 id）
    final persisted = await _resolveRetryMessageId(sid, toolIdx);
    if (persisted == null) return;

    // 阶段三：重建执行（含"重试工具"日志 + 重跑 + 截断 + 同步 _currentNovel）
    final newResultStr =
        await _reexecuteRetryTool(toolName, located.toolArgs, toolCallId, toolIdx);
    if (newResultStr == null) return;

    // 阶段四：三处更新（内存真理源 / UI / DB）
    _applyRetryResult(
      toolIdx: toolIdx,
      toolCallId: toolCallId,
      newResultStr: newResultStr,
      repo: persisted.repo,
      messageId: persisted.messageId,
    );
  }

  /// retryToolCall 阶段二：从 _agentMessages 倒查目标工具调用。
  ///
  /// 返回 assistant（含该 toolCallId）上的 name/arguments + 紧随其后第一个
  /// role='tool' 且 toolCallId 匹配的消息索引。找不到 assistant → null；
  /// 找到 assistant 但没有 tool 结果消息 → toolIdx 为 null（与原内联逻辑一致）。
  ({String toolName, Map<String, dynamic> toolArgs, int? toolIdx})?
      _locateRetryToolCall(String toolCallId) {
    for (var i = _agentMessages.length - 1; i >= 0; i--) {
      final m = _agentMessages[i];
      final calls = m.toolCalls ?? const <ToolCall>[];
      final hit = calls.where((c) => c.id == toolCallId).firstOrNull;
      if (hit != null) {
        // tool 消息紧跟在 assistant 之后，找第一个 role='tool' && toolCallId 匹配
        int? toolIdx;
        for (var j = i + 1; j < _agentMessages.length; j++) {
          final tm = _agentMessages[j];
          if (tm.role == 'tool' && tm.toolCallId == toolCallId) {
            toolIdx = j;
            break;
          }
          if (tm.role == 'assistant' || tm.role == 'user') break;
        }
        return (toolName: hit.name, toolArgs: hit.arguments, toolIdx: toolIdx);
      }
    }
    return null;
  }

  /// retryToolCall 阶段二收尾：取该 tool 消息的 DB 主键 id。
  ///
  /// 返回 repo（阶段四落库复用同一实例）+ messageId；会话记录与内存不一致
  /// （toolIdx 越界）时提示并返回 null。
  Future<({ChatSessionRepository repo, int? messageId})?> _resolveRetryMessageId(
    int sid,
    int toolIdx,
  ) async {
    final repo = _ref.read(chatSessionRepositoryProvider);
    final records = await repo.listMessages(sid);
    if (toolIdx >= records.length) {
      _notifyStateError('会话记录与内存不一致，无法重试');
      return null;
    }
    return (repo: repo, messageId: records[toolIdx].id);
  }

  /// retryToolCall 阶段三：重建执行。
  ///
  /// 仅支持 writing 场景：直接构造 WritingScenario（构造零成本、无 WebView 池
  /// 副作用），复用 select_novel / create_novel / patch_memory 的后置 hook。
  /// 结果经 [ToolResultFormatter] 截断为 formatted.llm（与 AgentLoop 的落库路径
  /// 一致）；select_novel / create_novel 重试成功后同步 _currentNovel（与
  /// ToolCallEndEvent 一致）。失败已记日志 + 提示 UI，返回 null。
  Future<String?> _reexecuteRetryTool(
    String toolName,
    Map<String, dynamic> toolArgs,
    String toolCallId,
    int toolIdx,
  ) async {
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 重试工具: $toolName (toolCallId=$toolCallId, toolIdx=$toolIdx)',
      category: LogCategory.ai,
      tags: ['session', 'retry_tool', scenarioId, toolName],
    );
    try {
      final scenario = WritingScenario(_ref);
      String rawResult;
      try {
        rawResult = await scenario.executeTool(
          toolName,
          Map<String, dynamic>.from(toolArgs),
          toolCallId: toolCallId,
        );
      } finally {
        await scenario.cleanup();
      }

      // 截断为 formatted.llm（与 AgentLoop._executeSingleTool 落库路径一致）
      Map<String, dynamic> result;
      try {
        result = jsonDecode(rawResult) as Map<String, dynamic>;
      } catch (_) {
        result = {'raw': rawResult};
      }
      final formatted = ToolResultFormatter(maxChars: 50000).format(result);

      if (toolName == 'select_novel' || toolName == 'create_novel') {
        _handleSelectNovelFromResult(rawResult);
      }
      return formatted.llm;
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 重试工具 $toolName 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'retry_tool', 'exec_failed', scenarioId],
      );
      _notifyStateError('重试失败: $e');
      return null;
    }
  }

  /// retryToolCall 阶段四：三处同步更新。
  ///
  /// 1) 内存真理源：原地覆盖旧 tool 消息（name/arguments/toolCallId 不变）
  /// 2) UI：刷新消息投影（用户看到 = LLM 将看到的 content），并清空失败标记
  ///    （避免后续 retryLastRound 误砍 retry 过的消息）
  /// 3) DB：updateMessageContent（LLM 下次 hydrate 看到的 = 用户看到的），
  ///    fire-and-forget，失败仅记日志、UI 已更新结果保持不变
  void _applyRetryResult({
    required int toolIdx,
    required String toolCallId,
    required String newResultStr,
    required ChatSessionRepository repo,
    required int? messageId,
  }) {
    _agentMessages[toolIdx] = ChatMessage(
      role: 'tool',
      content: newResultStr,
      toolCallId: toolCallId,
    );

    _state = _state.copyWith(
      messages: _uiMessages,
      streamingSegments: const [],
    );
    _failedRoundStartIndex = null;
    _notifyStateChanged();

    if (messageId != null) {
      // 落库失败抛异常会被 fire-and-forget 吞掉变成 unhandled async error；
      // 这里显式 catch 仅记录日志，UI 已更新结果保持不变。
      // 返回 0 让 catchError 与原返回类型 Future<int> 保持一致。
      unawaited(repo
          .updateMessageContent(messageId, newResultStr)
          .catchError((Object e, StackTrace st) {
        LoggerService.instance.e(
          'ScenarioSession [$scenarioId] 重写后落库失败: '
          'messageId=$messageId - $e',
          stackTrace: st.toString(),
          category: LogCategory.ai,
          tags: ['session', 'persist', 'failed', scenarioId],
        );
        return 0;
      }));
    }
  }


  /// 续跑 Agent —— 与 [_runAgent] 区别：不 append user、不调 sendMessage、走 resumeFromMessages。
  ///
  /// 调用前置条件：调用方已砍除失败轮残留，[_agentMessages] 末尾是 user（含）或 tool
  /// （之前 ReAct 失败在某 tool 调用之后）。无论哪种情况，service 都会原样传给 loop.run。
  Future<void> _resumeAgentRun() async {
    _lifecycle = SessionLifecycle.active;
    _isRunning = true;
    _isTokenCancelled = false;
    _pendingSegments.clear();

    _state = _state.copyWith(
      isLoading: true,
      streamingSegments: const [],
      error: null,
    );
    _notifyStateChanged();

    try {
      await _launchAgentRun(resume: true);
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 续跑 Agent 启动失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'agent_run', 'resume_failed', scenarioId],
      );
      _finalizeAgentResponse(error: '续跑失败: $e');
    }
  }

  /// 取消本 session 的 Agent（不影响其他 session）
  ///
  /// 返回 Future 以便写操作 `await cancel()` 形成 interrupt-then-act 语义；
  /// 内部仍为同步逻辑（落库走 unawaited fire-and-forget），不引入真实异步等待。
  ///
  /// 任务 8：级联取消本 session 派出的所有活跃子 Agent（dispatch_subagent）。
  /// 主 Agent 中断时，子 Agent 也必须停下，否则它们的事件流仍在写
  /// `agentService.events`，虽然 [shouldMainSessionHandleEvent] 会过滤掉，
  /// 但子 Agent 自身仍在消耗 LLM/工具资源。parentSessionId 与
  /// [WritingScenario.executeTool] 写入侧保持一致，统一为 `sessionId.toString()`。
  Future<void> cancel() async {
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 请求已取消',
      category: LogCategory.ai,
      tags: ['session', 'cancel', scenarioId],
    );

    // 级联取消本 session 派出的所有活跃子 Agent run
    final sessionIdStr = _sessionId?.toString();
    if (sessionIdStr != null) {
      await _ref.read(subagentRunnerProvider).cancelAllForSession(sessionIdStr);
    }

    // 通过 service 层取消 agent_loop 正在检查的 token
    _ref.read(novelAgentServiceProvider).cancelFor(scenarioId);
    _isTokenCancelled = true;
    _agentSub?.cancel();
    _agentSub = null;

    // 把 partial segments 落库为 assistant turn
    if (_pendingSegments.isNotEmpty) {
      _finalizeAgentResponse(partial: true);
    } else {
      _state = _state.copyWith(
        isLoading: false,
        streamingSegments: const [],
      );
      _isRunning = false;
      _lifecycle = SessionLifecycle.idle;
      _notifyStateChanged();
    }
    // 取消路径也要填充 rewrite completer（用户主动取消 → 视为失败，保留标注以便重试）
    _maybeCompleteRewriteCompleter(error: '已取消');
    _pendingRewriteTarget = null;
  }

  /// 统一中断守卫 — 所有写操作的第一道（也是唯一一道）运行中处理。
  ///
  /// 设计契约（interrupt-then-act）：运行中触发任何写操作 = 先 cancel 落库当前
  /// partial，再执行新操作。UI 层不再做业务拦截，只保留纯视觉反馈。
  /// 切场景（跨 scenarioId）不走此路径，保持 by design 的"不杀 Agent"。
  Future<void> _interruptIfRunning() async {
    if (!_isRunning) return;
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 写操作触发中断运行中的 agent',
      category: LogCategory.ai,
      tags: ['session', 'interrupt', scenarioId],
    );
    await cancel();
  }

  /// 切换当前小说（本 session 独享）
  @override
  Future<CurrentNovel?> selectNovel(int novelId) async {
    final novel = await selectCurrentNovel(_ref, novelId);
    if (novel != null) {
      _currentNovel = novel;
      _state = _state.copyWith(currentNovel: novel);
      _notifyStateChanged();
      // await 而非 fire-and-forget：返回时保证 DB（含自动命名）与内存一致，
      // 内部已 try/catch，持久化失败不影响本次选择结果。
      await _persistence.persistCurrentNovel();
    }
    return novel;
  }

  /// 清空对话（保留场景和小说上下文）
  ///
  /// 运行中清空：先清空内存（包括 _pendingSegments）→ 再 cancel。
  /// 此时 cancel 走 else 分支不落库残缺 partial，与"清空"语义一致。
  /// 不走 _interruptIfRunning()，因为该方法的语义是"先 cancel 落 partial"，
  /// 与本方法的"先清空，不留残缺"相反。
  Future<void> clearConversation() async {
    final wasRunning = _isRunning;
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 清空对话 sessionId=$_sessionId (wasRunning=$wasRunning)',
      category: LogCategory.ai,
      tags: ['session', 'clear', scenarioId],
    );
    _pendingSegments.clear();
    _agentMessages.clear();

    _state = AgentChatState(
      scenarioId: scenarioId,
      scenarioDisplayName: _state.scenarioDisplayName,
      currentNovel: _currentNovel,
    );
    _notifyStateChanged();

    // 后台 cancel：因 _pendingSegments 已空，cancel 走 else 分支仅做状态重置，
    // 不会落库残缺 partial。放在 clearMessagesFromDb 之前保证最终 DB 状态 = 清空。
    if (wasRunning) {
      await cancel();
    }

    unawaited(_persistence.clearMessagesFromDb());
  }

  /// 启动按标注重写章节（仅 annotation_rewrite 场景使用）。
  ///
  /// 与 [sendMessage] 的差异：
  /// - 用户消息由调用方决定（带标注列表），不调 buildUserContextPrefix 注入阅读上下文，
  ///   避免 system prompt 与 user 输入语义错位。
  /// - AgentScenarioContext 携带 [_pendingRewriteTarget]，factory 据此构造
  ///   [AnnotationRewriteScenario] 把工具锁死在目标章节上。
  /// - runId 传入 `_sessionId.toString()`，让所有事件打标 —— 本 run 的事件只被
  ///   本 session（id 一致）接收，避免与其它并发场景互相污染。
  /// - 返回 [AnnotationRewriteOutcome]：调用方据此决定是否清理章节标注
  ///   （成功 → 清；失败 → 保留以便重试）。
  ///
  /// 完成时机：返回前确保 _handleAgentEvent 已把 AgentDoneEvent / AgentErrorEvent
  /// 消费完毕（finalize 已把 tool 结果并入 _agentMessages），[_rewriteCompleter]
  /// 在 finalize/cancel/error 路径完成后填充 outcome，await 拿到时 _agentMessages
  /// 已是最终状态，可直接扫描本轮成功 update 次数。
  Future<AnnotationRewriteOutcome> startAnnotationRewrite({
    required String novelUrl,
    required String novelTitle,
    required String chapterUrl,
    required String chapterTitle,
    required int lockedPosition,
    required List<ParagraphAnnotation> annotations,
  }) async {
    if (scenarioId != ScenarioIds.annotationRewrite) {
      throw StateError(
          'startAnnotationRewrite 只能在 annotation_rewrite 场景的 session 上调用，当前 scenarioId=$scenarioId');
    }
    if (_isRunning) {
      throw StateError('session已已有 agent 在运行，请等待完成或取消后再试');
    }

    // 每次改写都是干净开始：清空上一轮历史（内存 + DB），改写会话不积压上下文，
    // 上一轮的章节内容/标注不进入本轮 LLM。顺序有讲究：
    // 1) 先清 DB（此后任何 hydrate 都只能读到空）
    // 2) 再 _ensureSessionId（冷启动 hydrate 读到的必然是空）
    // 3) 最后清内存（兜底掉与 get() 冷启动 hydrateFromRecentIfNeeded
    //    并发竞态时 hydrate 带回的旧消息——其赋值必然发生在本次清空之前）
    // 不走 clearConversation()：它对 DB 清理是 fire-and-forget，无法保证先于 hydrate。
    await _persistence.clearMessagesFromDb();
    await _ensureSessionId();
    _pendingSegments.clear();
    _agentMessages.clear();
    _state = _state.copyWith(
      messages: const [],
      isLoading: false,
      streamingSegments: const [],
      error: null,
    );
    _notifyStateChanged();

    final target = AnnotationRewriteTarget(
      novelUrl: novelUrl,
      novelTitle: novelTitle,
      chapterUrl: chapterUrl,
      chapterTitle: chapterTitle,
      lockedPosition: lockedPosition,
      annotations: annotations,
    );
    _pendingRewriteTarget = target;

    final annText = annotations
        .map((a) =>
            '- 第 ${a.paragraphIndex + 1} 段（"${a.paragraphPreview}"）：${a.content}')
        .join('\n');
    final userContent = '按标注改写《$chapterTitle》（共 ${annotations.length} 条标注）：\n'
        '$annText\n'
        '\n'
        '先 read_chapter_content 读取全文；规划需要联动的修改范围（标注可能牵动上下文与章节走向）；'
        '逐段 update_chapter_content 替换；完成后简短总结结束。';

    final userMsg = ChatMessage(role: 'user', content: userContent);
    _agentMessages.add(userMsg);
    _rewriteStartAgentIndex = _agentMessages.length - 1;
    _state = _state.copyWith(
      messages: _uiMessages,
      isLoading: true,
      streamingSegments: const [],
      error: null,
    );
    _notifyStateChanged();
    await _persistence.persistAgentMessage(userMsg);

    final completer = Completer<AnnotationRewriteOutcome>();
    _rewriteCompleter = completer;

    _isTokenCancelled = false;
    _lifecycle = SessionLifecycle.active;
    _isRunning = true;
    _pendingSegments.clear();

    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 启动标注重写: chapter=$chapterTitle '
      'annotations=${annotations.length} position=$lockedPosition sessionId=$_sessionId',
      category: LogCategory.ai,
      tags: ['session', 'rewrite', 'start', scenarioId],
    );

    try {
      // runId 传 sessionId.toString()：本 run 的事件只被本 session（id 一致）接收
      await _launchAgentRun(
        resume: false,
        userInput: userContent,
        runId: _sessionId?.toString(),
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'ScenarioSession [$scenarioId] 标注重写异常: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['session', 'rewrite', 'exception', scenarioId],
      );
      _finalizeAgentResponse(error: '改写异常: $e');
      _maybeCompleteRewriteCompleter(error: '改写异常: $e');
    }

    // 等待 finalize 把工具结果并入 _agentMessages（completer 在 AgentDoneEvent /
    // AgentErrorEvent / cancel 路径完成后填充）。
    return await completer.future;
  }

  /// finalize / cancel / 异常路径完成后填充 [_rewriteCompleter]（一次性）。
  ///
  /// [error] 非空时整轮视为失败；为空时按本轮 _agentMessages 内的成功
  /// update_chapter_content 工具调用次数判定 success。
  @override
  void _maybeCompleteRewriteCompleter({String? error}) {
    final completer = _rewriteCompleter;
    if (completer == null || completer.isCompleted) return;
    _rewriteCompleter = null;
    _pendingRewriteTarget = null;

    final outcome = _computeAnnotationRewriteOutcome(error: error);
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 标注重写完成: success=${outcome.success} '
      'updateCount=${outcome.updateCount}${outcome.error != null ? ' error=${outcome.error}' : ''}',
      category: LogCategory.ai,
      tags: ['session', 'rewrite', 'done', scenarioId],
    );
    completer.complete(outcome);
  }

  /// 从本轮 agent 消息扫描成功 update_chapter_content 次数。
  ///
  /// - [error] 非空 → 失败（返回 failure）
  /// - 遍历 [_rewriteStartAgentIndex, _agentMessages.length)：
  ///   - assistant 含 toolCalls name=='update_chapter_content'
  ///   - 紧跟其后的 tool 消息 content 解析为 JSON，success==true 视为成功
  /// - 最终 success = error==null && updateCount>0
  AnnotationRewriteOutcome _computeAnnotationRewriteOutcome({String? error}) {
    final startIdx = _rewriteStartAgentIndex;
    _rewriteStartAgentIndex = null;
    if (error != null) {
      return AnnotationRewriteOutcome.failure(error);
    }
    if (startIdx == null) {
      return AnnotationRewriteOutcome.failure('未记录本轮起始索引');
    }

    var updateCount = 0;
    for (var i = startIdx; i < _agentMessages.length; i++) {
      final m = _agentMessages[i];
      if (m.role != 'assistant') continue;
      final calls = m.toolCalls;
      if (calls == null || calls.isEmpty) continue;
      for (final c in calls) {
        if (c.name != 'update_chapter_content') continue;
        // 找紧随的 tool result
        final toolMsg = _findToolResult(_agentMessages, i, c.id);
        if (toolMsg == null) continue;
        try {
          final parsed = jsonDecode(toolMsg.content ?? '') as Map<String, dynamic>;
          if (parsed['success'] == true) updateCount++;
        } catch (_) {
          // 非 JSON 或解析失败 → 不计入成功
        }
      }
    }
    return AnnotationRewriteOutcome(
      success: updateCount > 0,
      updateCount: updateCount,
      error: updateCount == 0 ? '改写未产生任何写库动作' : null,
    );
  }

  /// 回滚到指定 user 消息 — 删除该消息及之后的所有记录,
  /// 并通过 [contentCallback] 把该消息文本回传给 UI。
  ///
  /// [index] 指向 UI messages（AgentChatMessage）中的 user 消息。
  ///
  /// 运行中回滚 = cancel 当前回合（落库 partial 到 _agentMessages 末尾）→ 然后
  /// 按 index 切。partial 会和被回滚的消息一起被 `removeRange` 砍掉，行为干净。
  /// 返回 Future[bool] 是为了与新签名 await 链一致；运行中不再返回 false，
  /// 业务校验失败（越界/非 user）仍返回 false。
  Future<bool> rollbackToMessage(
    int index, {
    required void Function(String content) contentCallback,
  }) async {
    // 运行中：先 cancel 落 partial（partial 在末尾会被下方 removeRange 一并砍掉）
    await _interruptIfRunning();

    final uiMsgs = _uiMessages;
    if (index < 0 || index >= uiMsgs.length) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 回滚索引越界: index=$index, len=${uiMsgs.length}',
        category: LogCategory.ai,
        tags: ['session', 'rollback', 'out_of_bounds', scenarioId],
      );
      return false;
    }
    final target = uiMsgs[index];
    if (target.role != AgentChatRole.user) {
      LoggerService.instance.w(
        'ScenarioSession [$scenarioId] 回滚目标非 user 消息',
        category: LogCategory.ai,
        tags: ['session', 'rollback', 'not_user', scenarioId],
      );
      return false;
    }

    // UI index → agent index：在 _agentMessages 中找到对应 uiMsgs[index] 的位置。
    // _uiMessages 包含 user 和 assistant 回合（system/tool 被跳过/吸收，
    // 且同一回合的连续 assistant 消息合并为一条 UI 消息），因此按投影分组计数：
    // assistant 只有在不处于「上一条可见消息也是 assistant」的合并运行中时
    // 才算新的 UI 条目。
    int agentIdx = -1;
    int uiCount = 0;
    bool inAssistantRun = false;
    for (int i = 0; i < _agentMessages.length; i++) {
      final role = _agentMessages[i].role;
      if (role == 'system' || role == 'tool') continue;
      if (role == 'assistant' && inAssistantRun) continue;
      if (uiCount == index) {
        agentIdx = i;
        break;
      }
      uiCount++;
      inAssistantRun = role == 'assistant';
    }
    if (agentIdx < 0) return false;

    final userContent = _agentMessages[agentIdx].content ?? '';
    LoggerService.instance.i(
      'ScenarioSession [$scenarioId] 回滚至 agentIdx=$agentIdx, '
      '删除之后 ${_agentMessages.length - agentIdx} 条 agent 消息',
      category: LogCategory.ai,
      tags: ['session', 'rollback', scenarioId],
    );

    _agentMessages.removeRange(agentIdx, _agentMessages.length);
    _state = _state.copyWith(
      messages: _uiMessages,
      isLoading: false,
      streamingSegments: const [],
      error: null,
    );
    _notifyStateChanged();

    unawaited(_persistence.rewriteAgentMessagesInDb(agentIdx,
        logTag: 'db_rewrite'));
    // rollback 砍掉了 user 消息及其后所有内容，失败轮标记必然失效 → 清空避免 retry 误用
    _failedRoundStartIndex = null;
    contentCallback(userContent);
    return true;
  }

  void dispose() {
    // 同步通知 agent loop 停止，避免 LLM/工具资源继续消耗；
    // cancelFor 内部用 _isTokenCancelled 做软中断，不会抛错。
    if (_isRunning) {
      try {
        _ref.read(novelAgentServiceProvider).cancelFor(scenarioId);
      } catch (e, st) {
        LoggerService.instance.e(
          'ScenarioSession [$scenarioId] dispose 时取消 Agent 失败: $e',
          stackTrace: st.toString(),
          category: LogCategory.ai,
          tags: ['session', 'dispose', 'cancel-error', scenarioId],
        );
      }
    }
    _agentSub?.cancel();
    _agentSub = null;
    // 兜底：若有调用方正 await _rewriteCompleter.future，dispose 时必须完成，
    // 否则协程永久挂起。
    _maybeCompleteRewriteCompleter(error: 'session disposed');
    _pendingRewriteTarget = null;
    _lifecycle = SessionLifecycle.disposed;
  }

  // ===== 内部实现 =====

  /// 启动一轮 agent run — 三处样板（[_beginAgentRun] / [_resumeAgentRun] /
  /// [startAnnotationRewrite]）的收敛点。
  ///
  /// 统一处理：cancel 老 [_agentSub] → 重新订阅全局事件流 → 组装 history →
  /// [_buildScenarioContext] → 调 service 启动 run。
  ///
  /// - [resume]=true：走 resumeFromMessages 续跑，_agentMessages 原样全量传给
  ///   loop（不 append user、不注入阅读上下文前缀，user 已是 history 的一部分）。
  /// - [resume]=false：走 sendMessage 新建 run，history 去掉末尾的 user
  ///   （service 会 append 一份）；[userInput] 必填；[runId] 可选
  ///   （标注重写传 sessionId 打标做事件过滤，主路径不传走旧路径事件）。
  Future<void> _launchAgentRun({
    required bool resume,
    String? userInput,
    String? runId,
  }) async {
    final agentService = _ref.read(novelAgentServiceProvider);
    await _agentSub?.cancel();
    _agentSub = agentService.events.listen(_handleAgentEvent);

    // history 组装：resume 原样传全量；新建 run 去掉末尾的 user（由 service append）
    final history = List<ChatMessage>.from(_agentMessages);
    if (!resume && history.isNotEmpty && history.last.role == 'user') {
      history.removeLast();
    }

    final scenarioContext = await _buildScenarioContext();

    // text_game 场景：所有运行统一打标 runId=sessionId，游玩页的事件流监听
    // 据此精确接收本局事件（防止与其它场景并发运行时事件互相污染）；
    // 本 session 自身的接收过滤（shouldMainSessionHandleEvent）对
    // runId==sessionId 的事件放行，接收行为不变。
    final effectiveRunId = runId ??
        (scenarioId == ScenarioIds.textGame ? _sessionId?.toString() : null);

    if (resume) {
      await agentService.resumeFromMessages(
        scenarioId: scenarioId,
        initialMessages: history,
        scenarioContext: scenarioContext,
        runId: effectiveRunId,
      );
    } else {
      await agentService.sendMessage(
        userInput: userInput!,
        history: history,
        scenarioId: scenarioId,
        scenarioContext: scenarioContext,
        runId: effectiveRunId,
      );
    }
  }

  /// 运行 Agent — 订阅全局 AgentService 的事件流
  Future<void> _runAgent(String userInput) async {
    await _launchAgentRun(resume: false, userInput: userInput);
  }

  /// 处理 Agent 事件 — 只更新本 session 的 _pendingSegments
  ///
  @override
  void _notifyStateChanged() {
    _onStateChanged?.call();
  }

  void _notifyStateError(String error) {
    _state = _state.copyWith(error: error);
    _notifyStateChanged();
  }

  // ===== 持久化 =====
  //
  // DB 写入已拆分到 AgentSessionPersistence（agent_session_persistence.dart）：
  // - persistAgentMessage        ← 原 _persistAgentMessage（含索引定位修复）
  // - persistAgentMessages       ← 原 _persistAgentMessages
  // - persistCurrentNovel        ← 原 _persistCurrentNovel（含标题自动同步）
  // - rewriteAgentMessagesInDb   ← 原 _deleteAgentMessagesFromDb /
  //                                _deleteAgentMessagesBeforeDb（合并参数化）
  // - clearMessagesFromDb        ← 原 _clearMessagesFromDb

  /// 构造当前场景上下文
  ///
  /// text_game 场景特殊处理：
  /// - 按 chatSessionId 反查 text_games 注入 textGameId（factory 据此
  ///   加载游戏设定构造 TextGameScenario）
  /// - 不注入阅读上下文 / 当前小说（游戏的 user 消息是玩家输入，
  ///   阅读上下文前缀会污染玩家语义）
  Future<AgentScenarioContext> _buildScenarioContext() async {
    final isTextGame = scenarioId == ScenarioIds.textGame;
    final readingContext =
        isTextGame ? null : _ref.read(readingContextProvider);
    final webviewController =
        isTextGame ? null : _ref.read(webviewControllerProvider);
    final currentUrl = isTextGame ? null : _ref.read(webviewCurrentUrlProvider);

    final useHeadless = scenarioId == ScenarioIds.webviewExtract;

    int? textGameId;
    if (isTextGame && _sessionId != null) {
      try {
        final game = await _ref
            .read(textGameRepositoryProvider)
            .getByChatSessionId(_sessionId!);
        textGameId = game?.id;
      } catch (e, st) {
        LoggerService.instance.e(
          'ScenarioSession [$scenarioId] 反查文字游戏失败: sessionId=$_sessionId - $e',
          stackTrace: st.toString(),
          category: LogCategory.ai,
          tags: ['session', 'text_game', 'lookup', 'failed', scenarioId],
        );
      }
    }

    return AgentScenarioContext(
      readingContext: readingContext,
      webviewController: useHeadless ? null : webviewController,
      currentUrl: currentUrl,
      useHeadlessWebView: useHeadless,
      currentNovelId: isTextGame ? null : _currentNovel?.id,
      currentNovelTitle: isTextGame ? null : _currentNovel?.title,
      rewriteTarget: _pendingRewriteTarget,
      textGameId: textGameId,
      chatSessionId: _sessionId,
    );
  }
}

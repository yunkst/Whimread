/// 文字游戏游玩页 — 状态与控制器
///
/// 独立状态层（不依赖 AgentChatState 的段模型）：控制器把 ScenarioSession
/// 的会话状态经游戏投影器重建为 [GameSegment] 剧情流，并把 ToolArgDeltaEvent
/// 事件流（narrate/speak 参数打字机）维护为 [GameStreamingPart]。
///
/// 引擎对接（对 UI 不可见）：
/// - 打开游戏 → switchSession(text_game, game.chatSessionId)（同刻只玩一局，
///   切局自动中断上一局的运行中回合并存档）
/// - 玩家输入 → session.sendMessage（选项 label 与自由输入同路径）
/// - 生图同步完成 → 工具结果自带 mediaIds，经消息链直接渲染
///
/// 离开页面：autoDispose 控制器停止监听，agent 继续在后台跑完（会话全局存活），
/// 回来重放消息链即可。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_chat_message.dart';
import '../../models/text_game.dart';
import '../../services/novel_agent/agent_event.dart';
import '../../services/novel_agent/agent_scenario.dart';
import '../../core/providers/agent_chat_state.dart';
import '../../core/providers/database_providers.dart'
    show
        characterRepositoryProvider,
        novelRepositoryProvider,
        textGameRepositoryProvider;
import '../../core/providers/chat_session_providers.dart';
import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/providers/scenario_session.dart';
import '../../services/novel_agent/novel_agent_service.dart'
    show novelAgentServiceProvider;
import 'game_transcript_projector.dart';

/// 游玩页状态
class TextGamePlayState {
  /// 当前游戏（加载失败为 null + error 非空）
  final TextGame? game;

  /// 定稿剧情流（消息链投影）
  final List<GameSegment> transcript;

  /// 运行中回合的非流式段（生图占位 / 选项预览），拼在 transcript 尾部
  final List<GameSegment> pendingSegments;

  /// 打字机中的流式内容（narrate/speak 参数增量）
  final List<GameStreamingPart> streamingParts;

  /// GM 思维链（当前轮，实时累积；"GM 思考"开关开启时渲染。
  /// 思维链不落库，回合结束/动作开始即清空）
  final String gmThinking;

  /// GM 当前幕后动作（如"正在描写旁白…"，来自工具调用开始事件）
  final String? gmAction;

  /// 角色名/别名 → 头像 mediaId（共享角色卡，进页加载一次；
  /// 台词段据此渲染小圆头像，无头像回退纯彩色名）
  final Map<String, String> avatarByName;

  final bool initializing;
  final bool agentRunning;
  final String? error;

  const TextGamePlayState({
    this.game,
    this.transcript = const [],
    this.pendingSegments = const [],
    this.streamingParts = const [],
    this.gmThinking = '',
    this.gmAction,
    this.avatarByName = const {},
    this.initializing = true,
    this.agentRunning = false,
    this.error,
  });

  /// 是否为从未开始的新游戏（显示「开始游戏」入口）
  bool get isEmptyGame =>
      !initializing &&
      error == null &&
      !agentRunning &&
      transcript.isEmpty &&
      pendingSegments.isEmpty &&
      streamingParts.isEmpty;

  TextGamePlayState copyWith({
    TextGame? game,
    List<GameSegment>? transcript,
    List<GameSegment>? pendingSegments,
    List<GameStreamingPart>? streamingParts,
    String? gmThinking,
    String? gmAction,
    bool clearGmAction = false,
    Map<String, String>? avatarByName,
    bool? initializing,
    bool? agentRunning,
    String? error,
    bool clearError = false,
  }) {
    return TextGamePlayState(
      game: game ?? this.game,
      transcript: transcript ?? this.transcript,
      pendingSegments: pendingSegments ?? this.pendingSegments,
      streamingParts: streamingParts ?? this.streamingParts,
      gmThinking: gmThinking ?? this.gmThinking,
      gmAction: clearGmAction ? null : (gmAction ?? this.gmAction),
      avatarByName: avatarByName ?? this.avatarByName,
      initializing: initializing ?? this.initializing,
      agentRunning: agentRunning ?? this.agentRunning,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 游玩页控制器（family by gameId，autoDispose：离开页面停止监听）
class TextGamePlayController extends StateNotifier<TextGamePlayState> {
  final Ref _ref;
  final int _gameId;

  ScenarioSession? _session;
  String? _runId; // sessionId.toString()，过滤本局事件
  StreamSubscription<AgentEvent>? _eventSub;
  bool _disposed = false;

  TextGamePlayController(this._ref, this._gameId) : super(const TextGamePlayState()) {
    _init();
  }

  Future<void> _init() async {
    // 监听会话状态：定稿/运行状态变化 → 重新投影
    _ref.listen(scenarioSessionsProvider, (_, __) => _reproject());

    final game = await _ref.read(textGameRepositoryProvider).getById(_gameId);
    if (_disposed) return;
    if (game == null) {
      state = state.copyWith(initializing: false, error: '游戏不存在或已被删除');
      return;
    }
    state = state.copyWith(game: game, initializing: false);
    unawaited(_ref.read(textGameRepositoryProvider).touchLastPlayed(_gameId));

    // 切换到该游戏的剧情会话（同刻只玩一局：切局自动中断上一局并存档）。
    // 先写 currentChatSessionIdProvider 再 switchSession：冷启动时 text_game
    // 的 ScenarioSession 尚未创建，switchSession 直接 return（等 get() 初始化），
    // 而 get() 以该 provider 为 initialSessionId——不先写入会回退到
    // 「复用最近更新的 text_game 会话」，挂到别的游戏上造成剧情写串。
    _ref
        .read(currentChatSessionIdProvider(ScenarioIds.textGame).notifier)
        .state = game.chatSessionId;
    final notifier = _ref.read(scenarioSessionsProvider.notifier);
    await notifier.switchSession(ScenarioIds.textGame, game.chatSessionId);
    if (_disposed) return;
    _session = notifier.get(ScenarioIds.textGame);
    _runId = _session?.sessionId?.toString();

    // 台词头像映射（共享角色卡 avatarMediaId；新角色卡无头像不影响渲染）
    final avatars = await _loadAvatars(game);
    if (_disposed) return;
    state = state.copyWith(avatarByName: avatars);

    // 订阅打字机事件流（仅 ToolArgDeltaEvent；本局 runId 打标过滤）
    _eventSub = _ref
        .read(novelAgentServiceProvider)
        .events
        .listen(_handleAgentEvent);

    _reproject();
  }

  /// 台词头像映射：参战角色卡（含玩家，防御性）的 名字/别名 → avatarMediaId
  Future<Map<String, String>> _loadAvatars(TextGame game) async {
    final novelId = game.sourceNovelId;
    if (novelId == null) return const {};
    final novel =
        await _ref.read(novelRepositoryProvider).getNovelById(novelId);
    if (novel == null) return const {};
    final all =
        await _ref.read(characterRepositoryProvider).getCharacters(novel.url);
    final byId = {for (final c in all) c.id: c};
    final map = <String, String>{};
    for (final id in game.settings.characterIds) {
      final card = byId[id];
      final avatar = card?.avatarMediaId;
      if (card == null || avatar == null || avatar.isEmpty) continue;
      map[card.name] = avatar;
      for (final alias in card.aliases ?? const <String>[]) {
        map[alias] = avatar;
      }
    }
    return map;
  }

  // ===== 事件流 =====

  void _handleAgentEvent(AgentEvent event) {
    if (_disposed) return;
    // 回合级网络重试：失败轮已流出的打字机内容整体作废（重试会重新输出
    // 完整版）。新轮 toolCallId 与失败轮不同，不清空会拼接出重复剧情。
    if (event is RetryEvent) {
      if (_runId != null && event.runId == _runId) {
        state = state.copyWith(
          streamingParts: const [],
          gmThinking: '',
          gmAction: null,
          clearGmAction: true,
        );
      }
      return;
    }
    // GM 幕后：思维链实时累积（"GM 思考"开关开启时渲染）
    if (event is ReasoningDeltaEvent) {
      if (_runId != null && event.runId == _runId) {
        state = state.copyWith(gmThinking: state.gmThinking + event.text);
      }
      return;
    }
    // GM 幕后：动作开始 → 用动作标签替换思维链（思维链先于动作流式到达，
    // 不清空会跨轮堆积成文字墙）
    if (event is ToolCallStartEvent) {
      if (_runId != null && event.runId == _runId) {
        // 思维链清空、动作标签替换（勿传 clearGmAction: true——copyWith 里
        // 它优先于 gmAction，会把刚设置的标签无条件置 null）
        state = state.copyWith(
          gmThinking: '',
          gmAction: _actionLabelFor(event),
        );
      }
      return;
    }
    if (event is! ToolArgDeltaEvent) return;
    // 只认本局打标事件（游戏运行统一 runId=sessionId）
    if (_runId == null || event.runId != _runId) return;

    final parts = [...state.streamingParts];
    var idx = parts.indexWhere((p) => p.toolCallId == event.toolCallId);
    if (idx < 0) {
      // 流式参数期间 toolCallId 可能从占位 call_N 切为真实 id（真实 id 帧
      // 后到）：同名且累计文本延续的占位块是同一次调用，原位接管——否则
      // 会留下"冻结的半截块 + 继续增长的新块"
      for (var i = parts.length - 1; i >= 0; i--) {
        final p = parts[i];
        if (p.name == event.name &&
            p.toolCallId.startsWith('call_') &&
            event.text.startsWith(p.text)) {
          idx = i;
          break;
        }
      }
    }
    final part = GameStreamingPart(
      toolCallId: event.toolCallId,
      name: event.name,
      text: event.text,
      character: event.character,
    );
    if (idx >= 0) {
      parts[idx] = part;
    } else {
      parts.add(part);
    }
    state = state.copyWith(streamingParts: parts);
  }

  /// 工具调用开始 → 幕后动作文案（null = 该工具不展示动作）
  String? _actionLabelFor(ToolCallStartEvent event) {
    switch (event.name) {
      case 'narrate':
        return '正在描写旁白…';
      case 'speak':
        final character = event.args['character']?.toString();
        return (character == null || character.isEmpty)
            ? '角色正在说话…'
            : '$character 正在说话…';
      case 'present_choices':
        return '正在整理本回合选项…';
      case 'create_scene_image':
        return '正在生成场景插图…';
      case 'update_game_state':
        return '正在记录剧情状态…';
      case 'roll_random_event':
        return '正在进行概率判定…';
      default:
        return null;
    }
  }

  // ===== 投影 =====

  void _reproject() {
    if (_disposed || state.game == null) return;
    final chatState =
        _ref.read(scenarioSessionsProvider)[ScenarioIds.textGame];
    if (chatState == null) return;

    final transcript = projectGameTranscript(
      chatState.messages,
      agentRunning: chatState.isLoading,
      avatarByName: state.avatarByName,
    );
    final pending = _projectPendingSegments(chatState);

    state = state.copyWith(
      transcript: transcript,
      pendingSegments: pending,
      agentRunning: chatState.isLoading,
      error: chatState.error,
      // error 传 null 是"会话无错误"，需清掉本地旧值（copyWith 的
      // error ?? this.error 语义使 null 无法自然清除）
      clearError: chatState.error == null,
    );

    // 回合结束：清空打字机内容与 GM 幕后（定稿链已包含全部内容）
    if (!chatState.isLoading &&
        (state.streamingParts.isNotEmpty ||
            state.gmThinking.isNotEmpty ||
            state.gmAction != null)) {
      state = state.copyWith(
        streamingParts: const [],
        gmThinking: '',
        gmAction: null,
        clearGmAction: true,
      );
    }
  }

  /// 运行中回合的非流式段：create_scene_image（生图占位）与已完成的
  /// present_choices（选项预览）。narrate/speak 的工具段跳过——其内容
  /// 经 ToolArgDeltaEvent 走 [GameStreamingPart] 打字机。
  List<GameSegment> _projectPendingSegments(AgentChatState chatState) {
    final result = <GameSegment>[];
    for (final seg in chatState.streamingSegments) {
      if (seg is! ToolCallSegment) continue;
      final call = seg.call;
      switch (call.name) {
        case 'create_scene_image':
          final completed = call.status != AgentToolStatus.running;
          result.add(GameSceneImage(
            toolCallId: call.id,
            prompt: call.arguments['prompt']?.toString() ?? '',
            toolResultJson: completed ? call.result : null,
            toolCompleted: completed,
          ));
        case 'present_choices':
          if (call.status == AgentToolStatus.completed) {
            final choices = parseGameChoices(call.arguments['choices']);
            if (choices.isNotEmpty) {
              result.add(GameChoices(
                choices: choices,
                active: false, // 回合结束后由定稿投影接管激活
                toolCallId: call.id,
              ));
            }
          }
        case 'roll_random_event':
          // live=true：结果一出即播揭晓动画（不等回合结束）；未出结果时
          // 呈轮转等待态。回合 finalize 后由定稿投影接管（live=false）
          final completed = call.status != AgentToolStatus.running;
          result.add(rollDiceRollSegment(
            call.id,
            call.arguments,
            completed: completed,
            resultJson: call.result,
            live: true,
          ));
        default:
          break;
      }
    }
    return result;
  }

  // ===== 玩家操作 =====

  /// 发送玩家输入（选项 label 或自由输入同路径）
  Future<void> sendInput(String text) async {
    final session = _session;
    final trimmed = text.trim();
    if (session == null || trimmed.isEmpty) return;
    state = state.copyWith(clearError: true);
    await session.sendMessage(content: trimmed);
    _reproject();
  }

  /// 点选选项（= 发送 label 文本）
  Future<void> sendChoice(GameChoice choice) => sendInput(choice.label);

  /// 回溯到历史选项节点：删除该选项组之后的玩家输入及全部后续剧情，
  /// 该选项组恢复为当前可选项（重选同一项或换一项均可）。
  ///
  /// 复用 session.rollbackToMessage：运行中先取消（partial 会随切尾一并
  /// 砍掉），内存与 DB 同步重写。设定演化（角色近况/玩家状态）不随剧情回退。
  /// 被删消息上未完成的生图任务完成时按 toolCallId 定位失败，安全 no-op。
  Future<bool> rollbackToChoices(GameChoices segment) async {
    final session = _session;
    final anchor = segment.rollbackUiIndex;
    if (session == null || anchor == null) return false;
    final ok =
        await session.rollbackToMessage(anchor, contentCallback: (_) {});
    _reproject();
    return ok;
  }

  /// 开始新游戏（发送开场触发消息）
  Future<void> startGame() => sendInput('开始游戏');

  /// 中断当前回合（运行中 partial 落库存档）
  Future<void> cancelTurn() async {
    await _session?.cancel();
    _reproject();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSub?.cancel();
    super.dispose();
  }
}

/// 游玩页控制器 Provider（autoDispose：离开页面停止监听，agent 不中断）
final textGamePlayControllerProvider = StateNotifierProvider.autoDispose
    .family<TextGamePlayController, TextGamePlayState, int>(
  (ref, gameId) => TextGamePlayController(ref, gameId),
);

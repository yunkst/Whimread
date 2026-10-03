/// 文字游戏游玩页 — 全新独立页面（非聊天 Dialog、不搭聊天壳）
///
/// 结构：
/// - AppBar：游戏标题 + 查看设定 + 菜单（AI 配置 / 删除游戏）
/// - 剧情流 ListView：定稿投影（transcript）+ 运行中段（pendingSegments）
///   + 打字机内容（streamingParts），自动滚到底部
/// - 底部：运行状态条（推进中/停止）→ 活动选项按钮 → 自由输入
/// - 新游戏扉页：标题 + 开场卡（开场情境/世界观，超一屏可滚动）+
///   固定「开始游戏」按钮
///
/// 离开页面不中断 agent（会话全局存活，回来重放）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart'
    show textGameRepositoryProvider;
import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/providers/text_game_providers.dart';
import '../../models/text_game.dart';
import '../../services/novel_agent/agent_scenario.dart';
import '../../widgets/agent_chat/agent_scenario_config_dialog.dart';
import '../../widgets/text_game/game_intro_view.dart';
import '../../widgets/text_game/game_segment_views.dart';
import '../../widgets/text_game/game_settings_sheet.dart';
import 'game_transcript_projector.dart';
import 'text_game_play_controller.dart';

class TextGamePlayScreen extends ConsumerStatefulWidget {
  final int gameId;

  const TextGamePlayScreen({super.key, required this.gameId});

  @override
  ConsumerState<TextGamePlayScreen> createState() => _TextGamePlayScreenState();
}

class _TextGamePlayScreenState extends ConsumerState<TextGamePlayScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  int _lastItemCount = 0;
  int _lastStreamingLen = 0;

  /// 上一帧键盘高度（弹出时剧情流继续贴底）
  double _lastViewInset = 0;

  /// 已播过揭晓动画的判定 toolCallId：ListView 滚动重建/历史回放时
  /// 据此直接静态展示，揭晓扫动只在结果首展时播一次
  final Set<String> _settledRollIds = {};

  /// 已播过入场动画的选项组 toolCallId（同上，只播一次记账）
  final Set<String> _settledChoiceIds = {};

  /// 首次见到非空定稿链时的长度：此前的内容都是历史（含页面重入回放），
  /// 之后新增的玩家输入才播入场动画。-1 = 未播种
  int _seededTranscriptLen = -1;

  /// 历史播种：页面进入时定稿链里已有的内容一律视为已播过，
  /// 保证动画只为"本次到访期间新出现的内容"播放，历史永不重播
  void _seedAnimationBookkeeping(List<GameSegment> transcript) {
    // 回溯重选使定稿链缩短 → 以当前长度重新起算
    if (_seededTranscriptLen >= 0) {
      if (transcript.length < _seededTranscriptLen) {
        _seededTranscriptLen = transcript.length;
      }
      return;
    }
    if (transcript.isEmpty) return; // 新游戏空链，等内容出现再播种
    _seededTranscriptLen = transcript.length;
    for (final seg in transcript) {
      switch (seg) {
        case GameDiceRoll():
          _settledRollIds.add(seg.toolCallId);
        case GameChoices():
          final id = seg.toolCallId;
          if (id != null) _settledChoiceIds.add(id);
        default:
          break;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 跟随底部：条目数增长（新剧情/新选项）或流式文字变长（打字机）
  /// 都触发。打字机期间是"单条目内部文字增长"，只看 itemCount 会完全
  /// 漏掉——输出越长玩家越看不到底。
  void _maybeScrollToBottom(int itemCount, int streamingLen) {
    if (itemCount == _lastItemCount && streamingLen == _lastStreamingLen) {
      return;
    }
    final grew =
        itemCount > _lastItemCount || streamingLen > _lastStreamingLen;
    _lastItemCount = itemCount;
    _lastStreamingLen = streamingLen;
    if (!grew) return;
    _followBottom();
  }

  /// 若处于跟随状态（距底部较近）则滚到底（等一帧布局稳定后执行）。
  /// 用户回看历史（离底部较远）时不打断。
  void _followBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      // 跟随状态下距底部始终很小
      if (position.maxScrollExtent - position.pixels > 480) return;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(textGamePlayControllerProvider(widget.gameId));
    final controller =
        ref.read(textGamePlayControllerProvider(widget.gameId).notifier);

    if (state.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final game = state.game;
    if (game == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(state.error ?? '游戏不存在')),
      );
    }

    // 剧情条目：定稿 + 运行中段 + 打字机（Listenable builder 由整体重建驱动）
    final showGmThinking = ref.watch(gmThinkingVisibleProvider);
    _seedAnimationBookkeeping(state.transcript);
    final items = <Widget>[
      for (var i = 0; i < state.transcript.length; i++)
        _buildSegment(context, state.transcript[i], i),
      for (final seg in state.pendingSegments)
        _buildSegment(context, seg, -1),
      if (state.streamingParts.isNotEmpty)
        GameStreamingPartsView(
          parts: state.streamingParts,
          avatarByName: state.avatarByName,
          showCaret: state.agentRunning,
        ),
      if (showGmThinking &&
          (state.gmThinking.isNotEmpty || state.gmAction != null))
        _GmBehindTheScenesView(
          thinking: state.gmThinking,
          action: state.gmAction,
        ),
      const SizedBox(height: 8),
    ];
    // 流式内容长度：打字机文字 + 思维链增长都应触发跟随
    final streamingLen = state.streamingParts.fold<int>(
          0,
          (sum, p) => sum + p.text.length,
        ) +
        state.gmThinking.length;
    _maybeScrollToBottom(items.length, streamingLen);

    // 键盘弹出：Scaffold 收缩可视区，剧情流末条会被顶出屏幕。
    // 跟随状态下继续贴底（与内容增长同一路径），回看历史时不打断
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    if (viewInset > _lastViewInset) _followBottom();
    _lastViewInset = viewInset;

    return Scaffold(
      appBar: AppBar(
        title: Text(game.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: showGmThinking ? '隐藏 GM 思考' : '显示 GM 思考',
            icon: Icon(
              showGmThinking
                  ? Icons.psychology
                  : Icons.psychology_outlined,
            ),
            onPressed: () =>
                ref.read(gmThinkingVisibleProvider.notifier).toggle(),
          ),
          IconButton(
            tooltip: '查看设定',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => _showSettingsSheet(context, game),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'ai_config') {
                showDialog(
                  context: context,
                  builder: (_) => AgentScenarioConfigDialog(
                    scenarioId: ScenarioIds.textGame,
                  ),
                );
              } else if (value == 'delete') {
                _confirmDelete(context, game);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ai_config', child: Text('AI 模型配置')),
              PopupMenuItem(value: 'delete', child: Text('删除游戏')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: state.isEmptyGame
                  ? _buildEmptyGame(context, state, controller)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      itemCount: items.length,
                      itemBuilder: (_, i) => items[i],
                    ),
            ),
            // 回合级错误横幅：此前只在 game == null 时展示错误，回合失败
            // （首回合失败时 transcript 仍为空）用户完全看不到失败原因
            if (state.error != null) _buildErrorBanner(context, state),
            if (state.agentRunning) _buildRunningStrip(context, controller),
            _buildComposer(context, state, controller),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(BuildContext context, GameSegment seg, int index) {
    switch (seg) {
      case GameNarration():
        return GameNarrationView(text: seg.text);
      case GameDialogue():
        return GameDialogueView(character: seg.character, text: seg.text);
      case GameSceneImage():
        return GameSceneImageView(segment: seg);
      case GameDiceRoll():
        final canAnimate = seg.toolCompleted &&
            seg.error == null &&
            seg.selectedLabel != null &&
            !_settledRollIds.contains(seg.toolCallId);
        return GameDiceRollView(
          segment: seg,
          animate: canAnimate,
          onAnimated: () => _settledRollIds.add(seg.toolCallId),
        );
      case GamePlayerInput():
        // 播种长度之后新增的输入才播入场动画（历史/回放直接静态）
        return GamePlayerInputView(
          text: seg.text,
          animate: _seededTranscriptLen >= 0 && index >= _seededTranscriptLen,
        );
      case GameChoices():
        // 活动选项固定渲染在输入区上方（_buildComposer），剧情流内不重复渲染；
        // 历史选项只读展示（置灰），带锚点的提供「回溯到这一步」。
        // 历史实例不播入场动画——活动组的动画由 composer 实例承担
        if (seg.active) return const SizedBox.shrink();
        return GameChoicesView(
          choices: seg,
          onRollback: seg.rollbackUiIndex == null
              ? null
              : () => _confirmRollback(context, seg),
        );
    }
  }

  /// 新游戏扉页（GameIntroView）：开场情境/世界观可滚动，开始按钮固定底部
  Widget _buildEmptyGame(
    BuildContext context,
    TextGamePlayState state,
    TextGamePlayController controller,
  ) {
    final game = state.game;
    return GameIntroView(
      title: game?.title ?? '',
      opening: game?.settings.opening ?? '',
      worldview: game?.settings.worldview ?? '',
      onStart: controller.startGame,
    );
  }

  /// 回合级错误横幅（error 由控制器从 chatState 同步，新回合开始自动清除）
  Widget _buildErrorBanner(BuildContext context, TextGamePlayState state) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 16, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.error ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunningStrip(
      BuildContext context, TextGamePlayController controller) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('剧情推进中',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          const _EllipsisDots(),
          TextButton(
            onPressed: controller.cancelTurn,
            child: const Text('停止'),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(
    BuildContext context,
    TextGamePlayState state,
    TextGamePlayController controller,
  ) {
    final theme = Theme.of(context);
    final manualImage = state.game?.settings.rules.imagePolicy ==
        GameImagePolicy.manual;

    // 活动选项（最后一条且 active）放在输入区上方；首次出现播错峰入场
    // （按 toolCallId 记账，播完标记；历史/页面重入不重播）
    final activeChoices = state.transcript
        .whereType<GameChoices>()
        .where((c) => c.active)
        .toList();
    final choicesWidget = activeChoices.isEmpty
        ? const SizedBox.shrink()
        : Builder(builder: (context) {
            final seg = activeChoices.last;
            final id = seg.toolCallId;
            return GameChoicesView(
              choices: seg,
              onSelected: (c) {
                _focusNode.unfocus();
                controller.sendChoice(c);
              },
              animate: id != null && !_settledChoiceIds.contains(id),
              onAnimated: () {
                if (id != null) _settledChoiceIds.add(id);
              },
            );
          });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        choicesWidget,
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
            ),
          ),
          child: Row(
            children: [
              if (manualImage)
                IconButton(
                  tooltip: '生成当前场景插图',
                  onPressed: state.agentRunning
                      ? null
                      : () => controller
                          .sendInput('生成当前场景的插图（只生成插图，不要推进剧情）'),
                  icon: const Icon(Icons.palette_outlined),
                ),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (text) {
                    if (text.trim().isEmpty) return;
                    _inputController.clear();
                    controller.sendInput(text);
                  },
                  decoration: const InputDecoration(
                    hintText: '描述你的行动或台词…',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: '发送',
                onPressed: () {
                  final text = _inputController.text;
                  if (text.trim().isEmpty) return;
                  _inputController.clear();
                  controller.sendInput(text);
                },
                icon: Icon(
                  Icons.send_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSettingsSheet(BuildContext context, TextGame game) {
    showGameSettingsSheet(context, ref, game);
  }

  /// 回溯确认：删除该选择点之后的剧情，回到此处重新决定。
  /// 设定演化（角色近况/玩家状态）不随剧情回退。
  Future<void> _confirmRollback(BuildContext context, GameChoices seg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回溯到这一步'),
        content: const Text(
          '将删除这一步之后的所有剧情，回到该选择点重新决定（选项或自由输入均可）。\n\n'
          '此操作不可恢复；角色近况等设定演化不会回退。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('回溯'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await ref
        .read(textGamePlayControllerProvider(widget.gameId).notifier)
        .rollbackToChoices(seg);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回溯失败，请重试')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, TextGame game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除游戏'),
        content: Text('删除「${game.title}」？\n剧情记录将一并删除，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // 若被删游戏正在推进剧情，先中断该回合（避免向已删除会话继续写消息）
    await _cancelIfPlaying(game);
    if (!context.mounted) return;
    await ref.read(textGameRepositoryProvider).delete(game.id!);
    if (!context.mounted) return;
    ref.invalidate(textGamesProvider);
    Navigator.of(context).pop(); // 返回管理页
  }

  /// 被删游戏的剧情会话若正驻内存且在运行，取消其当前回合
  Future<void> _cancelIfPlaying(TextGame game) async {
    final session = ref
        .read(scenarioSessionsProvider.notifier)
        .getIfExists(ScenarioIds.textGame);
    if (session != null && session.sessionId == game.chatSessionId) {
      await session.cancel();
    }
  }
}

/// 动态省略号（三点依次明灭，配合"剧情推进中"的推进感）
class _EllipsisDots extends StatefulWidget {
  const _EllipsisDots();

  @override
  State<_EllipsisDots> createState() => _EllipsisDotsState();
}

class _EllipsisDotsState extends State<_EllipsisDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          FadeTransition(
            opacity: Tween<double>(begin: 0.25, end: 1).animate(
              CurvedAnimation(
                parent: _ctrl,
                curve: Interval(i * 0.28, (i * 0.28 + 0.45).clamp(0.0, 1.0)),
              ),
            ),
            child: Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

/// GM 幕后块（"GM 思考"开关开启时渲染）：思维链实时文本 + 当前幕后动作。
/// 仅实时过程展示——思维链不落库，回合结束/动作开始即清空，历史不可回看。
class _GmBehindTheScenesView extends StatelessWidget {
  final String thinking;
  final String? action;

  const _GmBehindTheScenesView({
    required this.thinking,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology,
                  size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Text('GM 幕后',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
          if (thinking.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                // reverse 滚动让最新思考保持可见
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    thinking,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          if (action != null && action!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                action!,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

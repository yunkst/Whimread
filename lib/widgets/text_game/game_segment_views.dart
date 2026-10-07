/// 文字游戏游玩页 — 游戏段渲染组件
///
/// 全新独立组件（不 import widgets/agent_chat/）：旁白（阅读器风格段落）、
/// 台词（角色名 + 对白排版）、场景插图（MediaView/占位/错误）、选项按钮、
/// 玩家输入。视觉走 Theme.colorScheme，跟随应用主题。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../screens/media_preview_screen.dart';
import '../../screens/text_game/game_transcript_projector.dart';
import '../character/avatar_media.dart';
import '../media/media_view.dart';

/// 旁白段（阅读器风格：适中行高、无头像无标签）
class GameNarrationView extends StatelessWidget {
  final String text;

  const GameNarrationView({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      height: 1.7,
      color: theme.colorScheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text.rich(
        TextSpan(
          text: text,
          style: style,
        ),
      ),
    );
  }
}

/// 台词段（对话气泡：彩色角色名 + 角色头像 + 底色气泡）
///
/// 与旁白纯文本刻意拉开区分度（用户反馈 #10：人物行动/对话/旁白分不清）：
/// 台词永远带名字签和气泡底色，旁白始终是无装饰的阅读段落——玩家扫一眼
/// 就知道"谁在说话"。协议侧同步约束：speak 只放直接引语，动作神态走 narrate。
class GameDialogueView extends StatelessWidget {
  final String character;
  final String text;

  /// 角色头像 mediaId（null = 无头像，只渲染彩色名标签）
  final String? avatarMediaId;

  const GameDialogueView({
    super.key,
    required this.character,
    required this.text,
    this.avatarMediaId,
  });

  Color _nameColor(BuildContext context) {
    // 角色名按 hash 稳定取色（从预置调色板），同一角色恒同色
    const palette = [
      Color(0xFF7E57C2),
      Color(0xFF29B6F6),
      Color(0xFF26A69A),
      Color(0xFFEF6C00),
      Color(0xFFEC407A),
      Color(0xFF8D6E63),
      Color(0xFF5C6BC0),
      Color(0xFF66BB6A),
    ];
    return palette[character.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameColor = _nameColor(context);
    final hasAvatar = avatarMediaId != null && avatarMediaId!.isNotEmpty;
    // 头像 24 + 间距 6：无头像时气泡与名字签左对齐，有头像时与名字文本对齐
    final bubbleIndent = hasAvatar ? 30.0 : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAvatar)
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 6),
                  child: AvatarMedia(
                    mediaId: avatarMediaId,
                    name: character,
                    genderColor: nameColor,
                    fontSize: 12,
                    borderRadius: 12,
                  ),
                ),
              Text(
                character,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: nameColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Padding(
            padding: EdgeInsets.only(left: bubbleIndent),
            child: Container(
              // 不设 width：气泡按文本收缩（上限 0.82 屏宽），短台词不撑满
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Text.rich(
                TextSpan(
                  text: text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.6,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 玩家输入段（右对齐气泡；animate=true 时上滑淡入）
class GamePlayerInputView extends StatefulWidget {
  final String text;

  /// 入场动画（仅本次会话新增的输入，页面重入的历史不播）
  final bool animate;

  const GamePlayerInputView({
    super.key,
    required this.text,
    this.animate = false,
  });

  @override
  State<GamePlayerInputView> createState() => _GamePlayerInputViewState();
}

class _GamePlayerInputViewState extends State<GamePlayerInputView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1; // 静态直出（历史内容/动画已播）
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(curve),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                widget.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 场景插图段
///
/// 渲染直接读消息链里的 tool result（生图同步完成，结果即最终态）；
/// 未完成 → shimmer 流光占位；出图 → 淡入+缩放登场（AnimatedSwitcher，
/// 按 mediaIds 记账，同图重建不重播）；失败 → 错误文案。
class GameSceneImageView extends StatefulWidget {
  final GameSceneImage segment;

  const GameSceneImageView({super.key, required this.segment});

  @override
  State<GameSceneImageView> createState() => _GameSceneImageViewState();
}

class _GameSceneImageViewState extends State<GameSceneImageView>
    with SingleTickerProviderStateMixin {
  /// 占位 shimmer 循环（仅在等待出图期间运转）
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _syncShimmer();
  }

  @override
  void didUpdateWidget(covariant GameSceneImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncShimmer();
  }

  /// 占位中才转循环；出图/失败即停（不空转耗电）
  void _syncShimmer() {
    final need = !widget.segment.toolCompleted;
    if (need && !_shimmer.isAnimating) {
      _shimmer.repeat();
    } else if (!need && _shimmer.isAnimating) {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!widget.segment.toolCompleted) {
      child = _shimmerBox(context);
    } else {
      final mediaIds = parseSceneImageMediaIds(widget.segment.toolResultJson);
      if (mediaIds.isNotEmpty) {
        child = _mediaList(context, mediaIds);
      } else {
        final error = parseSceneImageError(widget.segment.toolResultJson);
        child = _statusBox(
          context,
          Icons.history_toggle_off,
          error ?? '本次运行未完成生成，图片不可用',
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }

  Widget _mediaList(BuildContext context, List<String> mediaIds) {
    if (mediaIds.isEmpty) {
      return _statusBox(context, Icons.image_not_supported_outlined, '图片不可用');
    }
    // MediaView 非全屏分支内部 Stack(fit: expand)，必须 bounded 约束；
    // AnimatedSwitcher 按 mediaId 记账：占位 → 出图播一次登场，重建不重播
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: MediaView(
            key: ValueKey('scene_img_${mediaIds.first}'),
            mediaId: mediaIds.first,
            onTap: () =>
                MediaPreviewScreen.open(context, mediaIds.first),
          ),
        ),
      ),
    );
  }

  /// 生成中占位：shimmer 流光扫过 + 转圈 + 文案
  Widget _shimmerBox(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final t = _shimmer.value;
        return Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t - 0.6, 0),
              end: Alignment(-1 + 2 * t + 0.6, 0),
              colors: [
                theme.colorScheme.surfaceContainerHighest,
                theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                theme.colorScheme.surfaceContainerHighest,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '插图生成中…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusBox(
    BuildContext context,
    IconData? icon,
    String message, {
    bool spinner = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (spinner)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 选项段（按钮组；历史选项置灰，已选标记 ✓）
///
/// [animate] 时按钮按顺序错峰上滑淡入（回合结束时"选项抵达"的反馈）。
/// 只播一次：游玩页按 toolCallId 记账，播完经 [onAnimated] 标记，
/// 之后滚动重建/历史回放直接静态（animate=false）。
class GameChoicesView extends StatefulWidget {
  final GameChoices choices;

  /// 点选回调（null = 不可点，纯展示）
  final void Function(GameChoice choice)? onSelected;

  /// 回溯回调（仅带锚点的历史选项组由游玩页提供：回到此节点重新选择）
  final VoidCallback? onRollback;

  /// 入场动画（首展一次）
  final bool animate;

  /// 动画播完回调（页面据此标记已播，防重播）
  final VoidCallback? onAnimated;

  const GameChoicesView({
    super.key,
    required this.choices,
    this.onSelected,
    this.onRollback,
    this.animate = false,
    this.onAnimated,
  });

  @override
  State<GameChoicesView> createState() => _GameChoicesViewState();
}

class _GameChoicesViewState extends State<GameChoicesView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  )..addStatusListener(_onStatus);

  /// 是否真的播过动画（静态模式手动置 value=1 也会发出 completed 状态，
  /// 不能据此回调 onAnimated）
  late final bool _played = widget.animate;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1; // 静态直出
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _played) {
      widget.onAnimated?.call();
    }
  }

  /// 第 i 项的错峰区间（每项 0.16 递进、单项占 0.66，总时长内收敛）
  Animation<double> _itemCurve(int i) {
    final start = i * 0.16;
    return CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, (start + 0.66).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = widget.choices;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in choices.choices)
            FadeTransition(
              opacity: _itemCurve(choices.choices.indexOf(c)),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.22),
                  end: Offset.zero,
                ).animate(_itemCurve(choices.choices.indexOf(c))),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: widget.onSelected == null || !choices.active
                        ? null
                        : () => widget.onSelected!(c),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (choices.chosenLabel == c.label) ...[
                              Icon(Icons.check_circle,
                                  size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                c.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (c.hint != null && c.hint!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              c.hint!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (widget.onRollback != null)
            TextButton.icon(
              onPressed: widget.onRollback,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.colorScheme.outline,
              ),
              icon: const Icon(Icons.history, size: 16),
              label: Text(
                '回溯到这一步',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

/// 概率判定段（命运骰子卡）
///
/// 视觉三态：
/// - **判定中**（toolCompleted=false 且 live）：循环动画——骰子旋转、
///   分支高亮轮转、边框呼吸辉光；
/// - **揭晓**（完成且 animate=true）：一次性扫动——高亮沿分支快速轮转
///   减速（easeOutCubic）落定选中项：弹簧放大 + 主色辉光淡入；
/// - **静态**（animate=false / 中断 / 失败）：直接展示落定态或错误。
///
/// animate 由游玩页控制：首次揭晓播一次，onAnimated 回调后页面记住该
/// toolCallId，之后滚动重建/历史回放直接静态，动画不重播。
class GameDiceRollView extends StatefulWidget {
  final GameDiceRoll segment;

  /// 是否播揭晓动画（首展播一次）
  final bool animate;

  /// 揭晓动画播完回调（页面据此标记已播，防重播）
  final VoidCallback? onAnimated;

  const GameDiceRollView({
    super.key,
    required this.segment,
    this.animate = false,
    this.onAnimated,
  });

  @override
  State<GameDiceRollView> createState() => _GameDiceRollViewState();
}

class _GameDiceRollViewState extends State<GameDiceRollView>
    with TickerProviderStateMixin {
  /// 判定中循环（骰子旋转/分支轮转/边框呼吸）
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// 揭晓扫动（一次性；0→1 播完回调 onAnimated）
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..addStatusListener(_onSweepStatus);

  /// 扫动进度（减速曲线）
  late final CurvedAnimation _sweepEase =
      CurvedAnimation(parent: _sweep, curve: Curves.easeOutCubic);

  /// 选中项弹簧放大（扫动后段：过冲回落到 1.03）
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.16)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 0.45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.16, end: 1.03)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 0.55,
    ),
  ]).animate(
    CurvedAnimation(parent: _sweep, curve: const Interval(0.68, 1.0)),
  );

  /// 选中项辉光淡入（扫动后段）
  late final Animation<double> _glow = CurvedAnimation(
    parent: _sweep,
    curve: const Interval(0.6, 0.92, curve: Curves.easeOut),
  );

  bool get _isRolling => !widget.segment.toolCompleted && widget.segment.live;

  @override
  void initState() {
    super.initState();
    if (_isRolling) {
      _loop.repeat();
    } else {
      _startSweepIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant GameDiceRollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // pending 段结果到达（判定中 → 已完成）：停轮转，起揭晓扫动
    if (!oldWidget.segment.toolCompleted && widget.segment.toolCompleted) {
      _loop.stop();
      if (widget.segment.live) {
        _startSweepIfNeeded();
      }
    }
    if (!_isRolling && _loop.isAnimating) _loop.stop();
  }

  /// 结果已出且允许动画（animate）、有可选分支 → 播一次揭晓扫动
  void _startSweepIfNeeded() {
    final seg = widget.segment;
    if (!widget.animate ||
        seg.error != null ||
        seg.selectedLabel == null ||
        seg.branches.isEmpty) {
      return;
    }
    _sweep.forward(from: 0);
  }

  void _onSweepStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onAnimated?.call();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seg = widget.segment;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AnimatedBuilder(
        animation: Listenable.merge([_loop, _sweep]),
        builder: (context, _) {
          final winnerIdx = _winnerIndex;
          final highlighted = _highlightIndex;
          final glow = seg.error == null && winnerIdx != null
              ? (widget.animate ? _glow.value : 1.0)
              : 0.0;

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _borderColor(theme, glow),
                width: 1.2,
              ),
              boxShadow: [
                if (glow > 0)
                  BoxShadow(
                    color: theme.colorScheme.primary
                        .withValues(alpha: 0.25 * glow),
                    blurRadius: 18 + 6 * glow,
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(theme, glow),
                if (seg.branches.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (var i = 0; i < seg.branches.length; i++)
                    _branchRow(
                      theme,
                      seg.branches[i],
                      highlighted: highlighted == i,
                      isWinner: winnerIdx == i,
                      winnerScale: winnerIdx == i && widget.animate
                          ? _pop.value
                          : (winnerIdx == i ? 1.03 : 1.0),
                    ),
                ],
                if (seg.error != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 15, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          seg.error!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ===== 状态推导 =====

  /// 选中分支索引（未定/失败为 null）
  int? get _winnerIndex {
    final label = widget.segment.selectedLabel;
    if (label == null) return null;
    final idx = widget.segment.branches.indexWhere((b) => b.label == label);
    return idx >= 0 ? idx : null;
  }

  /// 当前被高亮的分支索引（轮转/扫动中；静态时=选中项）
  int? get _highlightIndex {
    final seg = widget.segment;
    final n = seg.branches.length;
    if (n == 0) return null;
    if (seg.error != null) return null;

    if (_isRolling) {
      return ((n * 2) * _loop.value).floor() % n;
    }
    if (_sweep.isAnimating) {
      final winner = _winnerIndex ?? 0;
      final steps = n * 3 + winner; // 落点步 ≡ winner (mod n)
      final t = Curves.easeOutCubic.transform(_sweep.value);
      return (steps * t).floor().clamp(0, steps) % n;
    }
    return _winnerIndex;
  }

  // ===== 视觉部件 =====

  Color _borderColor(ThemeData theme, double glow) {
    if (glow > 0) {
      return Color.lerp(
          theme.colorScheme.outlineVariant, theme.colorScheme.primary, glow)!;
    }
    if (_isRolling) {
      // 呼吸辉光边框
      final t = 0.5 - 0.5 * math.cos(2 * math.pi * _loop.value);
      return Color.lerp(theme.colorScheme.outlineVariant,
          theme.colorScheme.primary.withValues(alpha: 0.8), t)!;
    }
    return theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
  }

  /// 头部：旋转骰子 + 标题/缘由 + 状态词
  Widget _header(ThemeData theme, double glow) {
    final seg = widget.segment;
    final angle = _diceAngle;
    final statusText = seg.error != null
        ? '判定失败'
        : _isRolling
            ? '概率判定中'
            : !seg.toolCompleted
                ? '判定未完成'
                : (widget.animate && _sweep.isAnimating ? '命运落定中…' : '命运落定');

    return Row(
      children: [
        Transform.rotate(
          angle: angle,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.85),
                  theme.colorScheme.tertiary.withValues(alpha: 0.85),
                ],
              ),
              boxShadow: [
                if (glow > 0)
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4 * glow),
                    blurRadius: 10,
                  ),
              ],
            ),
            child: const Icon(Icons.casino_rounded,
                size: 19, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('概率判定', style: theme.textTheme.titleSmall),
              if (seg.reason.isNotEmpty)
                Text(
                  seg.reason,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
        ),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
            color: glow > 0.5
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            fontWeight: FontWeight.w600,
          ),
          child: Text(statusText),
        ),
      ],
    );
  }

  /// 骰子角度：判定中匀速自旋；揭晓中减速回正；静态归位
  double get _diceAngle {
    if (_isRolling) return _loop.value * 4 * math.pi;
    if (_sweep.isAnimating) return -4 * math.pi * (1 - _sweepEase.value);
    return 0;
  }

  /// 分支行：标签 + 百分比；扫动高亮 / 选中辉光
  Widget _branchRow(
    ThemeData theme,
    GameRollBranch branch, {
    required bool highlighted,
    required bool isWinner,
    required double winnerScale,
  }) {
    final baseColor = theme.colorScheme.onSurfaceVariant;
    final active = highlighted || isWinner;
    final Color bg;
    final Color fg;
    if (isWinner) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.16 + 0.1 * _glow.value);
      fg = theme.colorScheme.primary;
    } else if (highlighted) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.10);
      fg = theme.colorScheme.primary;
    } else {
      bg = Colors.transparent;
      fg = baseColor;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Transform.scale(
        scale: winnerScale,
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  branch.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: isWinner || highlighted
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                branch.percent,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: isWinner ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import '../core/theme/app_typography.dart';

class ParagraphWidget extends StatefulWidget {
  final String paragraph;
  final int index;
  final double fontSize;
  final double textBrightness;
  final bool isEditMode;
  final ValueChanged<String>? onContentChanged;

  /// 该段落是否已有标注（显示标记）
  final bool hasAnnotation;

  /// 阅读模式下长按段落回调（添加/编辑标注）
  final VoidCallback? onLongPress;

  /// 阅读模式下：若非空，表示 agent 重写后此段落有新文本待揭示。
  ///
  /// 行为契约：
  /// - 首次构建（滚动进入视口）即启动：旧文本（[paragraph]）淡出 180ms → 切换到
  ///   [revealNewText] 并以打字机（每 ~16ms 增 1 字符，总时长 ≤ 1000ms）逐字呈现。
  /// - 动画启动时调用一次 [onRevealStart]（父层据此标记 revealed，后续跳过）。
  /// - 父组件应在视口外已显示新文本时不要传 revealNewText（即 revealed 后置 null）。
  final String? revealNewText;

  /// 启动揭示动画时回调（无 setState，仅父层记录 revealed 索引）。
  final ValueChanged<int>? onRevealStart;

  const ParagraphWidget({
    super.key,
    required this.paragraph,
    required this.index,
    required this.fontSize,
    this.textBrightness = 1.0,
    required this.isEditMode,
    this.onContentChanged,
    this.hasAnnotation = false,
    this.onLongPress,
    this.revealNewText,
    this.onRevealStart,
  });

  @override
  State<ParagraphWidget> createState() => _ParagraphWidgetState();
}

class _ParagraphWidgetState extends State<ParagraphWidget>
    with SingleTickerProviderStateMixin {
  late TextEditingController _controller;
  AnimationController? _fadeController;
  Timer? _typingTimer;
  String _displayedNew = '';
  bool _hasStartedReveal = false;

  /// 动画启动时缓存的旧文本——父组件中途重建（被后续 agent 更新触发）
  /// 时避免 fade 阶段读到错误的"旧文本"（应为 newText）。
  String? _fadingOutOldText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.paragraph);
    _maybeStartReveal();
  }

  @override
  void didUpdateWidget(ParagraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 编辑器路径：程序更新不应覆盖用户输入（保留原有逻辑）
    if (widget.isEditMode) {
      if (oldWidget.paragraph != widget.paragraph &&
          _controller.text != widget.paragraph) {
        _controller.value = TextEditingValue(
          text: widget.paragraph,
          selection: TextSelection.collapsed(offset: widget.paragraph.length),
        );
      }
      return;
    }
    // 阅读路径：revealNewText 新出现且尚未启动过动画 → 启动
    final newReveal = widget.revealNewText;
    final oldReveal = oldWidget.revealNewText;
    if (newReveal != null && newReveal != widget.paragraph) {
      if (oldReveal != newReveal || !_hasStartedReveal) {
        _maybeStartReveal();
      }
    }
  }

  void _maybeStartReveal() {
    final reveal = widget.revealNewText;
    if (reveal == null || reveal.isEmpty || reveal == widget.paragraph) return;
    if (_hasStartedReveal) return;
    _hasStartedReveal = true;
    _fadingOutOldText = widget.paragraph;
    widget.onRevealStart?.call(widget.index);

    _displayedNew = '';
    _fadeController?.dispose();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fadeController!.addStatusListener(_onFadeStatus);
    _fadeController!.forward();
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final reveal = widget.revealNewText!;
    if (reveal.isEmpty) {
      setState(() => _displayedNew = '');
      return;
    }
    // 启动打字机：总时长 ≤ 1000ms，按字符数算每 tick 多少字符
    // 立刻把 _displayedNew 推进一格，避免 fade 完成后到首帧之间的空白闪。
    const totalBudgetMs = 1000;
    const tickMs = 16;
    final totalTicks = totalBudgetMs ~/ tickMs; // ~62 ticks
    final charsPerTick = (reveal.length / totalTicks).ceil().clamp(1, 32);
    var typed = charsPerTick.clamp(1, reveal.length);
    setState(() => _displayedNew = reveal.substring(0, typed));

    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (typed >= reveal.length) {
        t.cancel();
        if (mounted) setState(() => _displayedNew = reveal);
        return;
      }
      typed = (typed + charsPerTick).clamp(0, reveal.length);
      if (mounted) setState(() => _displayedNew = reveal.substring(0, typed));
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _fadeController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildTextWidget();
  }

  Widget _buildTextWidget() {
    if (widget.isEditMode) {
      return _buildEditableText();
    }
    return _buildReadableText();
  }

  Widget _buildEditableText() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onContentChanged,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: AppTypography.bodyProse.copyWith(
          fontSize: widget.fontSize,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        maxLines: null,
      ),
    );
  }

  Widget _buildReadableText() {
    final theme = Theme.of(context);
    final baseColor =
        theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
    final effectiveColor = baseColor.withValues(alpha: widget.textBrightness);
    final hasAnnotation = widget.hasAnnotation;

    final reveal = widget.revealNewText;
    final isRevealing = reveal != null && _hasStartedReveal;

    // 揭示动画期间：fadeOut<1 显示旧文本（淡出）；fadeOut≥1 显示新文本（打字机增长）。
    // 非揭示期间：直接显示 paragraph。
    Widget textChild;
    double textOpacity = 1.0;
    if (isRevealing && _fadeController != null) {
      textChild = AnimatedBuilder(
        animation: _fadeController!,
        builder: (context, _) {
          final fadeOut = _fadeController!.value;
          if (fadeOut < 1.0) {
            return Text(
              _fadingOutOldText ?? widget.paragraph.trim(),
              style: AppTypography.bodyProse.copyWith(
                fontSize: widget.fontSize,
                color: effectiveColor,
              ),
            );
          }
          return Text(
            _displayedNew,
            style: AppTypography.bodyProse.copyWith(
              fontSize: widget.fontSize,
              color: effectiveColor,
            ),
          );
        },
      );
      textOpacity = (1.0 - (_fadeController!.value)).clamp(0.0, 1.0);
    } else if (isRevealing) {
      // 极少发生的瞬态：fadeController 已 dispose 但仍在揭示态 → 直接显示打字机当前字符
      textChild = Text(
        _displayedNew,
        style: AppTypography.bodyProse.copyWith(
          fontSize: widget.fontSize,
          color: effectiveColor,
        ),
      );
    } else {
      textChild = Text(
        widget.paragraph.trim(),
        style: AppTypography.bodyProse.copyWith(
          fontSize: widget.fontSize,
          color: effectiveColor,
        ),
      );
    }

    final paragraphWidget = Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: textChild,
          ),
          if (hasAnnotation)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Icon(
                  Icons.edit_note,
                  size: widget.fontSize,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: widget.onLongPress,
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: hasAnnotation
                  ? theme.colorScheme.primary.withValues(alpha: 0.06)
                  : null,
            ),
            child: Opacity(
              opacity: textOpacity,
              child: paragraphWidget,
            ),
          ),
        ),
      ],
    );
  }
}
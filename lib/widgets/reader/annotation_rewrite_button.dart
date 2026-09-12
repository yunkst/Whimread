import 'package:flutter/material.dart';

import '../../services/novel_agent/scenarios/annotation_rewrite_agent.dart';

/// 「按标注重写」悬浮按钮（纯展示 + 点击回调）
///
/// 状态由父组件（reader_screen）持有并通过 [status]/[isRunning]/[progressText]
/// 传入；本组件只根据状态渲染外观，不管理任何定时器或状态机。
///
/// 父组件状态机约定：
/// - `isRunning=true` → 显示旋转图标 + 进度文案，不可点击
/// - `status=done`    → 短暂显示绿色对勾（父组件负责定时回 idle）
/// - `status=error`   → 红色警示图标 + 「重写失败」
/// - 其余             → idle，显示「按标注重写(N)」
class AnnotationRewriteButton extends StatelessWidget {
  final int annotationCount;
  final bool isRunning;
  final RewriteStatus status;

  /// running 态的进度文案（如「第 2 步改写…」）；空则显示默认文案
  final String progressText;

  /// 父组件在 idle 态才响应点击
  final VoidCallback? onTap;

  const AnnotationRewriteButton({
    super.key,
    required this.annotationCount,
    required this.isRunning,
    required this.status,
    this.progressText = '',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, color) = _resolveAppearance(theme);
    final enabled = !isRunning && status == RewriteStatus.idle && onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Widget, Color) _resolveAppearance(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    if (isRunning) {
      return (
        progressText.isEmpty ? '按标注重写中…' : progressText,
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.onPrimary),
          ),
        ),
        primary,
      );
    }
    if (status == RewriteStatus.done) {
      return (
        '已按标注重写',
        Icon(Icons.check_circle, size: 18, color: theme.colorScheme.onPrimary),
        Colors.green.shade600,
      );
    }
    if (status == RewriteStatus.error) {
      return (
        '重写失败',
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.onPrimary),
        theme.colorScheme.error,
      );
    }
    return (
      '按标注重写($annotationCount)',
      Icon(Icons.auto_fix_high, size: 18, color: theme.colorScheme.onPrimary),
      primary,
    );
  }
}
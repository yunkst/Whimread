import 'package:flutter/material.dart';

/// 通用空状态视图
///
/// 统一空状态视觉规范：80 号图标（alpha 0.25）+ headlineSmall 标题 +
/// bodyMedium 描述（可选）+ 可选 CTA 按钮。
///
/// 范本参考：[EmptyBookshelfView]。
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
    this.iconWidget,
    this.titleStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 32),
  });

  /// 空状态图标，size 80，颜色 onSurface alpha 0.25。
  final IconData icon;

  /// 自定义图标 widget（如印章式 SVG 风格）。传则覆盖 [icon]；不传走原 [Icon(icon)]。
  final Widget? iconWidget;

  /// 标题，headlineSmall bold + onSurface alpha 0.7。
  final String title;

  /// 自定义标题样式（如 serif）。传则覆盖默认 headlineSmall；不传走原逻辑。
  final TextStyle? titleStyle;

  /// 描述文字，bodyMedium + onSurface alpha 0.5，居中。
  final String? subtitle;

  /// CTA 按钮文本（与 [onAction] 同时提供时才显示）。
  final String? actionText;

  /// CTA 按钮回调（与 [actionText] 同时提供时才显示）。
  final VoidCallback? onAction;

  /// 外层 Padding，默认横向 32。
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurface = colorScheme.onSurface;

    final children = <Widget>[
      iconWidget ??
          Icon(
            icon,
            size: 80,
            color: onSurface.withValues(alpha: 0.25),
          ),
      const SizedBox(height: 24),
      Text(
        title,
        style: titleStyle ??
            theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: onSurface.withValues(alpha: 0.7),
            ),
      ),
    ];

    if (subtitle != null) {
      children.add(const SizedBox(height: 12));
      children.add(
        Text(
          subtitle!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: onSurface.withValues(alpha: 0.5),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (actionText != null && onAction != null) {
      children.add(const SizedBox(height: 24));
      children.add(
        FilledButton.tonal(
          onPressed: onAction,
          child: Text(actionText!),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

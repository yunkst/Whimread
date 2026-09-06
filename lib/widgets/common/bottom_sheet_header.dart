import 'package:flutter/material.dart';

/// BottomSheet 顶部标准头部
///
/// 内置 36×4 圆角拖拽把手 + 图标+标题 Row + 可选 trailing。
/// 统一各 BottomSheet 的顶部样板，消除重复代码。
///
/// 用法：
/// ```dart
/// BottomSheetHeader(
///   icon: Icons.bookmark,
///   title: '收藏夹',
///   trailing: IconButton(...),
/// )
/// ```
class BottomSheetHeader extends StatelessWidget {
  const BottomSheetHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.titleStyle,
  });

  /// 标题前的小图标（size 20，primary 颜色）。
  final IconData icon;

  /// 标题文字。
  final String title;

  /// 标题右侧的 widget（操作按钮/徽章等）。空间不足时会被 Expanded 压缩。
  final Widget? trailing;

  /// 标题文字样式。默认取 theme 的 titleMedium bold + onSurface。
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveTitleStyle = titleStyle ??
        theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface);

    final trailing = this.trailing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 拖拽把手
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // 标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: effectiveTitleStyle),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
      ],
    );
  }
}

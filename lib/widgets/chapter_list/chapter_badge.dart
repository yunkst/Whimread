import 'package:flutter/material.dart';

/// 用户章节徽章组件
///
/// 标识用户插入的章节
class ChapterBadge extends StatelessWidget {
  final String label;

  const ChapterBadge({
    this.label = '用户',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          color: colorScheme.primary.withValues(alpha: 0.7),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

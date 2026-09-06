import 'package:flutter/material.dart';

/// 章节标题组件
///
/// 统一显示章节标题的样式逻辑
class ChapterTitle extends StatelessWidget {
  final String title;
  final bool isLastRead;
  final bool isUserChapter;
  final bool isRead;

  const ChapterTitle({
    required this.title,
    required this.isLastRead,
    required this.isUserChapter,
    this.isRead = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: isLastRead ? FontWeight.bold : FontWeight.normal,
        color: _getTextColor(context),
        fontStyle: isUserChapter ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }

  /// 获取标题颜色
  /// 优先级：最后阅读 > 已读 > 默认
  Color? _getTextColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (isLastRead) {
      return colorScheme.error;
    }
    if (isRead) {
      return colorScheme.onSurface.withValues(alpha: 0.6);
    }
    return null;
  }
}

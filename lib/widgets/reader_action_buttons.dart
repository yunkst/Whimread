import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class ReaderActionButtons extends StatelessWidget {
  final bool isAutoScrolling;
  final bool isAutoScrollPaused;
  final VoidCallback onToggleAutoScroll;

  const ReaderActionButtons({
    super.key,
    required this.isAutoScrolling,
    this.isAutoScrollPaused = false,
    required this.onToggleAutoScroll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 120.0), // 避免与底部章节切换按钮重叠
      child: FloatingActionButton(
        onPressed: onToggleAutoScroll,
        tooltip: isAutoScrolling
            ? (isAutoScrollPaused ? '恢复自动滚动' : '暂停自动滚动')
            : '开始自动滚动',
        heroTag: 'auto_scroll',
        backgroundColor: context.appColors.agentAccent,
        foregroundColor: context.appColors.agentOnBrand,
        elevation: 4,
        shape: const CircleBorder(),
        child: Icon(isAutoScrolling
            ? (isAutoScrollPaused ? Icons.play_arrow : Icons.pause)
            : Icons.play_arrow),
      ),
    );
  }
}

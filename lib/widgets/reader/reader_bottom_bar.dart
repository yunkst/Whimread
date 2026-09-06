import 'package:flutter/material.dart';

/// ReaderBottomBar - 阅读器底部导航栏
///
/// 职责：
/// - 显示章节切换按钮
/// - 显示当前章节进度
/// - 固定在屏幕底部
///
/// 交互：
/// - 支持上一章/下一章切换
/// - 禁用状态自动处理
class ReaderBottomBar extends StatelessWidget {
  final int currentIndex;
  final int totalChapters;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;

  const ReaderBottomBar({
    super.key,
    required this.currentIndex,
    required this.totalChapters,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPreviousChapter,
    required this.onNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: hasPrevious ? onPreviousChapter : null,
                icon: const Icon(Icons.arrow_back),
                label: const Text('上一章'),
              ),
              Text(
                '${currentIndex + 1}/$totalChapters',
                style: const TextStyle(fontSize: 14),
              ),
              ElevatedButton.icon(
                onPressed: hasNext ? onNextChapter : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('下一章'),
                style: ElevatedButton.styleFrom(
                  iconAlignment: IconAlignment.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

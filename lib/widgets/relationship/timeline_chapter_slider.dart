import 'package:flutter/material.dart';

/// 章节时间轴滑块。
///
/// 在关系图页面顶部展示当前阅读进度,拖动可覆盖默认进度,
/// 按章节过滤"已登场人物 + 当前生效关系"。
///
/// 章节为 0-based index,UI 显示时 +1(第 N 章)。
class TimelineChapterSlider extends StatelessWidget {
  /// 最大章节 index(章节数 - 1)。为 0 时滑块禁用。
  final int maxChapter;

  /// 当前章节 index。
  final int chapter;

  /// 拖动回调(已 debounce 由父层处理)。
  final ValueChanged<int> onChanged;

  const TimelineChapterSlider({
    super.key,
    required this.maxChapter,
    required this.chapter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = maxChapter <= 0;
    final displayChapter = chapter + 1;
    final maxDisplay = maxChapter + 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('章节时间轴', style: theme.textTheme.titleSmall),
              Text(
                disabled ? '第 1 章 / 共 1 章' : '第 $displayChapter 章 / 共 $maxDisplay 章',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: disabled ? 0 : chapter.toDouble().clamp(0, maxChapter.toDouble()),
            min: 0,
            max: disabled ? 1 : maxChapter.toDouble(),
            divisions: disabled ? 1 : maxChapter,
            label: '$displayChapter',
            onChanged: disabled
                ? null
                : (v) => onChanged(v.round().clamp(0, maxChapter)),
          ),
        ],
      ),
    );
  }
}

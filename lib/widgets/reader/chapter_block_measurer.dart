import 'package:flutter/material.dart';

import 'paragraph_metrics.dart';

/// 章节块高度测量：TextPainter 纯计算，不进 widget 树。
///
/// 取代旧的 Offstage 测量层——为测一个章节块的高度挂载整章上百个段落
/// 组件，是单帧数百毫秒卡顿的大头。TextPainter 直接排版文本取高，
/// 开销低一个量级，且无 widget 生命周期、可同步拿到结果。
///
/// 条目构成与 ReaderContentView 的列表一致：章节分隔线 + 段落序列
/// （末章尾部的 160px 占位是列表级条目，不属于任何单个章节块）。
/// 样式与结构来自 [ParagraphMetrics] 与 ReaderChapterDivider——
/// 渲染侧改动若不同步此处，补偿量即漂移。
class ChapterBlockMeasurer {
  ChapterBlockMeasurer._();

  /// 计算一个章节块上屏后的总高度（分隔线 + Σ段落）。
  ///
  /// [contentWidth] 为 ListView 内容宽；textScaler 取自 MediaQuery——
  /// 真实渲染遵循系统字体缩放，测高必须同源。
  static double blockHeight({
    required BuildContext context,
    required String dividerTitle,
    required List<String> paragraphs,
    required double fontSize,
    required double contentWidth,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    var height = _dividerHeight(
      context,
      title: dividerTitle,
      contentWidth: contentWidth,
      scaler: scaler,
    );
    final maxWidth = ParagraphMetrics.textWidth(contentWidth);
    final style = ParagraphMetrics.bodyStyle(fontSize);
    for (final paragraph in paragraphs) {
      height += _textHeight(
            paragraph.trim(),
            style: style,
            maxWidth: maxWidth,
            scaler: scaler,
          ) +
          ParagraphMetrics.containerPaddingV * 2;
    }
    return height;
  }

  /// 章节分隔线高度（结构与 ReaderChapterDivider 严格一致：
  /// padding 24/12 + 1px 分隔线 + 14 间距 + 章名 ≤2 行）
  static double _dividerHeight(
    BuildContext context, {
    required String title,
    required double contentWidth,
    required TextScaler scaler,
  }) {
    const topPadding = 24.0;
    const bottomPadding = 12.0;
    const ruleHeight = 1.0;
    const titleGap = 14.0;
    final titleStyle =
        (Theme.of(context).textTheme.titleSmall ?? const TextStyle())
            .copyWith(fontWeight: FontWeight.w600);
    final titleHeight = _textHeight(
      title,
      style: titleStyle,
      maxWidth: contentWidth,
      scaler: scaler,
      maxLines: 2,
    );
    return topPadding + ruleHeight + titleGap + titleHeight + bottomPadding;
  }

  static double _textHeight(
    String text, {
    required TextStyle style,
    required double maxWidth,
    required TextScaler scaler,
    int? maxLines,
  }) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

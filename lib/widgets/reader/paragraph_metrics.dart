import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// 段落排版度量的单一真理源。
///
/// [ParagraphWidget] 的实际渲染与拼接测高（[ChapterBlockMeasurer]，
/// TextPainter 纯计算）都从这里取样式与内边距——测高结果直接决定
/// 顶部拼接的滚动补偿量，两处任何一处漂移都会造成补偿误差、视野跳动。
/// 修改任何一项，必须同时过渲染与测高两条路径。
class ParagraphMetrics {
  ParagraphMetrics._();

  /// 段落容器水平内边距
  static const double containerPaddingH = 8.0;

  /// 段落容器垂直内边距（同时充当段落间距）
  static const double containerPaddingV = 6.0;

  /// 阅读视图 ListView 的内容宽（padding 16 左右各一）
  static double listContentWidth(double screenWidth) => screenWidth - 32;

  /// 段落正文可用文本宽度（内容宽 - 段落容器左右 padding）
  static double textWidth(double contentWidth) =>
      contentWidth - containerPaddingH * 2;

  /// 正文字体样式（AppTypography.bodyProse + 运行时字号）。
  ///
  /// 颜色/透明度只影响显示不影响排版，测高路径无需传色。
  static TextStyle bodyStyle(double fontSize) =>
      AppTypography.bodyProse.copyWith(fontSize: fontSize);
}

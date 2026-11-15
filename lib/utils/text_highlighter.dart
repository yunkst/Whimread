import 'package:flutter/material.dart';

/// 文本高亮工具类
/// 用于在文本中查找并高亮显示匹配的关键词
class TextHighlighter {
  /// 默认高亮样式配置
  static const HighlightStyle _defaultStyle = HighlightStyle(
    backgroundColor: Colors.yellow,
    textColor: Colors.black,
  );

  /// 在文本中高亮显示所有匹配的关键词
  ///
  /// [text] 原始文本
  /// [keywords] 要高亮的关键词列表
  /// [style] 高亮样式，如果为null则使用默认样式
  /// [caseSensitive] 是否区分大小写，默认为false
  ///
  /// 返回带高亮标记的文本，使用特殊标记包围匹配文本
  static String highlightText({
    required String text,
    required List<String> keywords,
    HighlightStyle? style,
    bool caseSensitive = false,
  }) {
    if (text.isEmpty || keywords.isEmpty) {
      return text;
    }

    final highlightStyle = style ?? _defaultStyle;
    final startMarker = highlightStyle.startMarker;
    final endMarker = highlightStyle.endMarker;

    String result = text;

    // 对每个关键词进行高亮处理
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;

      result = _highlightSingleKeyword(
        text: result,
        keyword: keyword,
        startMarker: startMarker,
        endMarker: endMarker,
        caseSensitive: caseSensitive,
      );
    }

    return result;
  }

  /// 在文本中高亮单个关键词
  static String _highlightSingleKeyword({
    required String text,
    required String keyword,
    required String startMarker,
    required String endMarker,
    required bool caseSensitive,
  }) {
    if (keyword.isEmpty) return text;

    final RegExp pattern;
    if (caseSensitive) {
      pattern = RegExp(RegExp.escape(keyword));
    } else {
      pattern = RegExp(RegExp.escape(keyword), caseSensitive: false);
    }

    return text.replaceAllMapped(
      pattern,
      (match) => '$startMarker${match.group(0)}$endMarker',
    );
  }

  /// 解析高亮文本为TextSpan列表
  ///
  /// [highlightedText] 带高亮标记的文本
  /// [baseStyle] 基础文本样式
  /// [highlightStyle] 高亮样式
  ///
  /// 返回可以用于RichText的TextSpan列表
  static List<TextSpan> parseHighlightedText({
    required String highlightedText,
    TextStyle? baseStyle,
    TextStyle? highlightStyle,
  }) {
    final List<TextSpan> spans = [];
    final marker = HighlightStyle.defaultStartMarker;
    final endMarker = HighlightStyle.defaultEndMarker;

    int currentIndex = 0;
    int markerIndex = highlightedText.indexOf(marker);

    while (markerIndex != -1) {
      // 添加普通文本
      if (markerIndex > currentIndex) {
        final normalText = highlightedText.substring(currentIndex, markerIndex);
        spans.add(TextSpan(
          text: normalText,
          style: baseStyle,
        ));
      }

      // 查找结束标记
      final endIndex = highlightedText.indexOf(endMarker, markerIndex);
      if (endIndex == -1) break;

      // 添加高亮文本（兜底样式复用 [_defaultStyle]，避免重复定义）
      final highlightText = highlightedText.substring(
        markerIndex + marker.length,
        endIndex,
      );
      spans.add(TextSpan(
        text: highlightText,
        style: highlightStyle ??
            TextStyle(
              backgroundColor: _defaultStyle.backgroundColor,
              color: _defaultStyle.textColor,
            ),
      ));

      currentIndex = endIndex + endMarker.length;
      markerIndex = highlightedText.indexOf(marker, currentIndex);
    }

    // 添加剩余的普通文本
    if (currentIndex < highlightedText.length) {
      final remainingText = highlightedText.substring(currentIndex);
      spans.add(TextSpan(
        text: remainingText,
        style: baseStyle,
      ));
    }

    return spans;
  }
}

/// 高亮样式配置
class HighlightStyle {
  final String startMarker;
  final String endMarker;
  final Color backgroundColor;
  final Color textColor;
  final FontWeight? fontWeight;
  final TextDecoration? decoration;

  static const String defaultStartMarker = '§§HIGHLIGHT_START§§';
  static const String defaultEndMarker = '§§HIGHLIGHT_END§§';

  const HighlightStyle({
    this.startMarker = defaultStartMarker,
    this.endMarker = defaultEndMarker,
    this.backgroundColor = Colors.yellow,
    this.textColor = Colors.black,
    this.fontWeight,
    this.decoration,
  });

  /// 获取高亮文本样式
  TextStyle getTextStyle(TextStyle? baseStyle) {
    return (baseStyle ?? const TextStyle()).copyWith(
      backgroundColor: backgroundColor,
      color: textColor,
      fontWeight: fontWeight,
      decoration: decoration,
    );
  }
}


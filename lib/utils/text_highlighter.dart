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

  /// 提取带高亮的上下文片段
  ///
  /// [text] 原始文本
  /// [keywords] 搜索关键词
  /// [contextLength] 上下文长度（字符数），默认为100
  /// [maxLength] 最大显示长度，默认为300
  /// [style] 高亮样式
  /// [caseSensitive] 是否区分大小写
  ///
  /// 返回包含高亮匹配的上下文片段
  static HighlightedContext extractContextWithHighlight({
    required String text,
    required List<String> keywords,
    int contextLength = 100,
    int maxLength = 300,
    HighlightStyle? style,
    bool caseSensitive = false,
  }) {
    if (text.isEmpty || keywords.isEmpty) {
      return HighlightedContext(
        text: text.length > maxLength
            ? '${text.substring(0, maxLength)}...'
            : text,
        hasMatches: false,
        matchPositions: [],
      );
    }

    final highlightStyle = style ?? _defaultStyle;

    // 查找所有匹配的位置
    final matchPositions = _findMatchPositions(
      text: text,
      keywords: keywords,
      caseSensitive: caseSensitive,
    );

    if (matchPositions.isEmpty) {
      return HighlightedContext(
        text: text.length > maxLength
            ? '${text.substring(0, maxLength)}...'
            : text,
        hasMatches: false,
        matchPositions: [],
      );
    }

    // 找到最佳匹配位置（第一个匹配）
    final bestMatch = matchPositions.first;
    final start = (bestMatch.start - contextLength).clamp(0, text.length);
    final end = (bestMatch.end + contextLength).clamp(0, text.length);

    String contextText = text.substring(start, end);

    // 添加省略号标记
    if (start > 0) {
      contextText = '...$contextText';
    }
    if (end < text.length) {
      contextText = '$contextText...';
    }

    // 在上下文中添加高亮标记（需要调整位置偏移）
    final highlightedText = _highlightContextWithOffset(
      contextText: contextText,
      originalText: text,
      matchPositions: matchPositions,
      offset: start > 0 ? start - 3 : 0, // 考虑"..."的长度
      style: highlightStyle,
      caseSensitive: caseSensitive,
    );

    return HighlightedContext(
      text: highlightedText,
      hasMatches: true,
      matchPositions: matchPositions,
    );
  }

  /// 查找文本中所有匹配的位置
  static List<MatchPosition> _findMatchPositions({
    required String text,
    required List<String> keywords,
    required bool caseSensitive,
  }) {
    final List<MatchPosition> allMatches = [];

    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;

      final RegExp pattern;
      if (caseSensitive) {
        pattern = RegExp(RegExp.escape(keyword));
      } else {
        pattern = RegExp(RegExp.escape(keyword), caseSensitive: false);
      }

      for (final match in pattern.allMatches(text)) {
        allMatches.add(MatchPosition(
          start: match.start,
          end: match.end,
          keyword: match.group(0) ?? '',
        ));
      }
    }

    // 按位置排序并去重
    allMatches.sort((a, b) => a.start.compareTo(b.start));
    return _removeOverlappingMatches(allMatches);
  }

  /// 移除重叠的匹配位置
  static List<MatchPosition> _removeOverlappingMatches(
      List<MatchPosition> matches) {
    final List<MatchPosition> result = [];

    for (final match in matches) {
      if (result.isEmpty || result.last.end <= match.start) {
        result.add(match);
      }
      // 如果有重叠，保留较长的匹配
      else if (match.end > result.last.end) {
        result.last = match;
      }
    }

    return result;
  }

  /// 在上下文文本中添加高亮标记（考虑偏移量）
  static String _highlightContextWithOffset({
    required String contextText,
    required String originalText,
    required List<MatchPosition> matchPositions,
    required int offset,
    required HighlightStyle style,
    required bool caseSensitive,
  }) {
    String result = contextText;

    // 调整匹配位置以适应上下文偏移
    final adjustedMatches = matchPositions
        .where((match) {
          final adjustedStart = match.start - offset;
          final adjustedEnd = match.end - offset;
          return adjustedStart >= 0 && adjustedEnd <= result.length;
        })
        .map((match) => MatchPosition(
              start: match.start - offset,
              end: match.end - offset,
              keyword: match.keyword,
            ))
        .toList();

    // 按位置倒序排列，从后往前替换，避免位置偏移
    adjustedMatches.sort((a, b) => b.start.compareTo(a.start));

    for (final match in adjustedMatches) {
      final start = match.start.clamp(0, result.length);
      final end = match.end.clamp(0, result.length);

      if (start < end) {
        final before = result.substring(0, start);
        final matchText = result.substring(start, end);
        final after = result.substring(end);

        result =
            '$before${style.startMarker}$matchText${style.endMarker}$after';
      }
    }

    return result;
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

/// 匹配位置信息
class MatchPosition {
  final int start;
  final int end;
  final String keyword;

  const MatchPosition({
    required this.start,
    required this.end,
    required this.keyword,
  });

  @override
  String toString() {
    return 'MatchPosition(start: $start, end: $end, keyword: $keyword)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MatchPosition &&
        other.start == start &&
        other.end == end &&
        other.keyword == keyword;
  }

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ keyword.hashCode;
}

/// 带高亮的上下文信息
class HighlightedContext {
  final String text;
  final bool hasMatches;
  final List<MatchPosition> matchPositions;

  const HighlightedContext({
    required this.text,
    required this.hasMatches,
    required this.matchPositions,
  });
}

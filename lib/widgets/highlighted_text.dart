import 'package:flutter/material.dart';
import '../utils/text_highlighter.dart';

/// 高亮文本显示组件
/// 用于显示带高亮标记的文本
class HighlightedText extends StatelessWidget {
  final String highlightedText;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool selectable;

  const HighlightedText({
    super.key,
    required this.highlightedText,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final effectiveStyle = defaultStyle.merge(style);

    // 获取高亮样式
    final defaultHighlightStyle =
        const HighlightStyle().getTextStyle(effectiveStyle);
    final effectiveHighlightStyle = highlightStyle ?? defaultHighlightStyle;

    // 解析高亮文本
    final textSpans = TextHighlighter.parseHighlightedText(
      highlightedText: highlightedText,
      baseStyle: effectiveStyle,
      highlightStyle: effectiveHighlightStyle,
    );

    if (selectable) {
      // 可选择的高亮文本
      return SelectableText.rich(
        TextSpan(
          children: textSpans,
          style: effectiveStyle,
        ),
        textAlign: textAlign ?? TextAlign.left,
        maxLines: maxLines,
      );
    } else {
      // 普通高亮文本
      return RichText(
        text: TextSpan(
          children: textSpans,
          style: effectiveStyle,
        ),
        textAlign: textAlign ?? TextAlign.left,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.ellipsis,
      );
    }
  }
}

/// 标题高亮组件
/// 用于显示章节标题等较短文本的高亮
class TitleHighlight extends StatelessWidget {
  final String title;
  final List<String> keywords;
  final TextStyle? style;
  final TextStyle? highlightStyle;

  const TitleHighlight({
    super.key,
    required this.title,
    required this.keywords,
    this.style,
    this.highlightStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (keywords.isEmpty) {
      return Text(
        title,
        style: style,
      );
    }

    // 高亮整个标题
    final highlightedTitle = TextHighlighter.highlightText(
      text: title,
      keywords: keywords,
      style: HighlightStyle(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        textColor: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
    );

    return HighlightedText(
      highlightedText: highlightedTitle,
      style: style,
      highlightStyle: highlightStyle,
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/app_typography.dart';

class ParagraphWidget extends StatefulWidget {
  final String paragraph;
  final int index;
  final double fontSize;
  final double textBrightness;
  final bool isEditMode;
  final ValueChanged<String>? onContentChanged;

  /// 该段落是否已有标注（显示标记）
  final bool hasAnnotation;

  /// 阅读模式下长按段落回调（添加/编辑标注）
  final VoidCallback? onLongPress;

  const ParagraphWidget({
    super.key,
    required this.paragraph,
    required this.index,
    required this.fontSize,
    this.textBrightness = 1.0,
    required this.isEditMode,
    this.onContentChanged,
    this.hasAnnotation = false,
    this.onLongPress,
  });

  @override
  State<ParagraphWidget> createState() => _ParagraphWidgetState();
}

class _ParagraphWidgetState extends State<ParagraphWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.paragraph);
  }

  @override
  void didUpdateWidget(ParagraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有在外部内容真正改变时才更新
    if (oldWidget.paragraph != widget.paragraph) {
      // 检查是否是用户编辑导致的更新（避免覆盖用户输入）
      if (_controller.text != widget.paragraph) {
        _controller.value = TextEditingValue(
          text: widget.paragraph,
          selection: TextSelection.collapsed(offset: widget.paragraph.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildTextWidget();
  }

  Widget _buildTextWidget() {
    if (widget.isEditMode) {
      return _buildEditableText();
    }
    return _buildReadableText();
  }

  Widget _buildEditableText() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onContentChanged,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: AppTypography.bodyProse.copyWith(
          fontSize: widget.fontSize,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        maxLines: null,
      ),
    );
  }

  Widget _buildReadableText() {
    final baseColor = Theme.of(context).textTheme.bodyLarge?.color ??
        Theme.of(context).colorScheme.onSurface;
    final effectiveColor = baseColor.withValues(alpha: widget.textBrightness);
    final hasAnnotation = widget.hasAnnotation;

    final paragraphWidget = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: widget.paragraph.trim(),
            style: AppTypography.bodyProse.copyWith(
              fontSize: widget.fontSize,
              color: effectiveColor,
            ),
          ),
          // 段落末尾的标注标记（类似脚注角标）
          if (hasAnnotation)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Icon(
                  Icons.edit_note,
                  size: widget.fontSize,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: widget.onLongPress,
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              // 已标注段落加淡淡的底色提示
              color: hasAnnotation
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.06)
                  : null,
            ),
            child: paragraphWidget,
          ),
        ),
      ],
    );
  }
}
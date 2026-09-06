import 'dart:async';
import 'package:flutter/material.dart';
import '../paragraph_widget.dart';

/// ReaderContentView - 阅读器内容视图
///
/// 职责：
/// - 显示章节内容列表
/// - 支持触摸事件处理自动滚动
/// - 处理滚动通知
/// - 支持全文连续编辑模式
///
/// 依赖：
/// - ParagraphWidget (段落组件)
/// - AutoScrollMixin (自动滚动功能)
class ReaderContentView extends StatefulWidget {
  final List<String> paragraphs;
  final double fontSize;
  final double textBrightness;
  final bool isEditMode;
  final bool isAutoScrolling;

  /// 内容变化回调
  /// - [index] 段落索引（-1 表示全文编辑，>=0 表示段落编辑）
  /// - [newContent] 新的内容
  final Function(int index, String newContent) onContentChanged;
  final ScrollController scrollController;
  final Function() onPointerDown;
  final Function() onPointerUp;
  final bool Function(ScrollNotification) onScrollNotification;

  const ReaderContentView({
    super.key,
    required this.paragraphs,
    required this.fontSize,
    this.textBrightness = 1.0,
    required this.isEditMode,
    required this.isAutoScrolling,
    required this.onContentChanged,
    required this.scrollController,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onScrollNotification,
  });

  @override
  State<ReaderContentView> createState() => _ReaderContentViewState();
}

class _ReaderContentViewState extends State<ReaderContentView> {
  late TextEditingController _fullTextController;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fullTextController = TextEditingController(
      text: widget.paragraphs.join('\n\n'),
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(ReaderContentView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isEditMode && !widget.isEditMode) {
      widget.onContentChanged(-1, _fullTextController.text);
    }

    if (!widget.isEditMode &&
        (oldWidget.paragraphs.length != widget.paragraphs.length ||
            !_listEquals(oldWidget.paragraphs, widget.paragraphs))) {
      _fullTextController.text = widget.paragraphs.join('\n\n');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fullTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditMode) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => widget.onPointerDown(),
        onPointerUp: (_) => widget.onPointerUp(),
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16.0),
          child: _buildFullTextEditor(),
        ),
      );
    }

    return _buildReadingMode(context);
  }

  Widget _buildFullTextEditor() {
    return TextField(
      controller: _fullTextController,
      maxLines: null,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        filled: true,
        fillColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        hintText: '开始编辑章节内容...',
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        contentPadding: const EdgeInsets.all(16.0),
      ),
      style: TextStyle(
        fontSize: widget.fontSize,
        height: 1.8,
        letterSpacing: 0.5,
      ),
      onChanged: (value) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          widget.onContentChanged(-1, value);
        });
      },
    );
  }

  Widget _buildReadingMode(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onPointerDown(),
      onPointerUp: (_) => widget.onPointerUp(),
      child: NotificationListener<ScrollNotification>(
        onNotification: widget.onScrollNotification,
        child: ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16.0),
          itemCount: widget.paragraphs.length + 1,
          itemBuilder: (context, index) {
            if (index == widget.paragraphs.length) {
              return SizedBox(
                height: 160,
                child: Container(),
              );
            }

            final paragraph = widget.paragraphs[index];

            return ParagraphWidget(
              paragraph: paragraph,
              index: index,
              fontSize: widget.fontSize,
              textBrightness: widget.textBrightness,
              isEditMode: widget.isEditMode,
              onContentChanged: (newContent) =>
                  widget.onContentChanged(index, newContent),
            );
          },
        ),
      ),
    );
  }
}
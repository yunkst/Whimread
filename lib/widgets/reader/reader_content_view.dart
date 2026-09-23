import 'dart:async';
import 'package:flutter/material.dart';
import '../paragraph_widget.dart';
import 'reader_chapter_segment.dart';

/// ReaderContentView - 阅读器内容视图
///
/// 职责：
/// - 按序显示已拼接章节分段（无限滚动：上/下章内容由上层追加进 [segments]）
/// - 支持触摸事件处理自动滚动
/// - 处理滚动通知
/// - 支持全文连续编辑模式（仅展示当前章）
///
/// 依赖：
/// - ParagraphWidget (段落组件)
/// - ReaderChapterSegment / ReaderFlatLayout (分段与扁平布局换算)
class ReaderContentView extends StatefulWidget {
  /// 已拼接章节分段（按显示顺序；编辑模式仅应传入当前章一段）
  final List<ReaderChapterSegment> segments;

  /// 章节起点标记的 GlobalKey（key = 章节 URL），由阅读页持有，
  /// 用于当前章检测与定位；视图按段把标记渲染为 0 高度条目
  final Map<String, GlobalKey> blockStartKeys;

  final double fontSize;
  final double textBrightness;
  final bool isEditMode;
  final bool isAutoScrolling;

  /// 长按段落回调（chapterUrl = 段落所属章节，index = 章内段落序号）
  final void Function(String chapterUrl, int index, String paragraph)?
      onParagraphLongPress;

  /// 揭示动画播完回调（父层据此撤销该段的旧文本占位与登记）
  final void Function(String chapterUrl, int index, String revealedText)?
      onParagraphRevealComplete;

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
    required this.segments,
    required this.blockStartKeys,
    required this.fontSize,
    this.textBrightness = 1.0,
    required this.isEditMode,
    required this.isAutoScrolling,
    this.onParagraphLongPress,
    this.onParagraphRevealComplete,
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

  /// 编辑模式全文（当前章段落按空行连接）
  List<String> _editParagraphs(ReaderContentView widget) =>
      widget.segments.expand((s) => s.paragraphs).toList();

  @override
  void initState() {
    super.initState();
    _fullTextController = TextEditingController(
      text: _editParagraphs(widget).join('\n\n'),
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

    final oldParagraphs = _editParagraphs(oldWidget);
    final newParagraphs = _editParagraphs(widget);
    if (!widget.isEditMode &&
        (oldParagraphs.length != newParagraphs.length ||
            !_listEquals(oldParagraphs, newParagraphs))) {
      _fullTextController.text = newParagraphs.join('\n\n');
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
    final layout = ReaderFlatLayout(widget.segments);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onPointerDown(),
      onPointerUp: (_) => widget.onPointerUp(),
      child: NotificationListener<ScrollNotification>(
        onNotification: widget.onScrollNotification,
        child: ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16.0),
          itemCount: layout.itemCount,
          itemBuilder: (context, index) {
            // 尾部占位（末章底部留白）
            if (index == layout.itemCount - 1) {
              return SizedBox(
                height: 160,
                child: Container(),
              );
            }

            // 章节分隔线（每章起点，携带章节级 GlobalKey 供上层采样/检测/定位）
            final markerUrl = layout.markerChapterUrlAt(index);
            if (markerUrl != null) {
              final markerKey = widget.blockStartKeys[markerUrl];
              final markerSegment = widget.segments.firstWhere(
                (s) => s.chapterUrl == markerUrl,
              );
              return ReaderChapterDivider(
                key: markerKey,
                title: markerSegment.chapterTitle,
              );
            }

            final paragraphInfo = layout.paragraphAt(index);
            if (paragraphInfo == null) {
              return const SizedBox.shrink();
            }
            final (chapterUrl, paragraphIndex, paragraph) = paragraphInfo;
            final segment = widget.segments.firstWhere(
              (s) => s.chapterUrl == chapterUrl,
            );
            final reveal = segment.pendingReveals[paragraphIndex];

            return ParagraphWidget(
              // 稳定 key：顶部拼接插入条目时元素可跨索引匹配，
              // 避免段落 State（揭示动画等）错挂到别的段落
              key: ValueKey('p_${chapterUrl}_$paragraphIndex'),
              paragraph: paragraph,
              index: paragraphIndex,
              fontSize: widget.fontSize,
              textBrightness: widget.textBrightness,
              isEditMode: false,
              hasAnnotation: segment.annotatedIndexes.contains(paragraphIndex),
              revealNewText: reveal,
              onRevealComplete:
                  widget.onParagraphRevealComplete == null
                      ? null
                      : (i, text) =>
                          widget.onParagraphRevealComplete!(chapterUrl, i, text),
              onLongPress: widget.onParagraphLongPress == null
                  ? null
                  : () =>
                      widget.onParagraphLongPress!(chapterUrl, paragraphIndex, paragraph),
            );
          },
        ),
      ),
    );
  }
}

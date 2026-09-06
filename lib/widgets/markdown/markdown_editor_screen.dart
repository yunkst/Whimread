import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/logger_service.dart';
import '../../utils/error_helper.dart';
import '../../utils/toast_utils.dart';
import '../common/common_widgets.dart';
import 'prose_markdown_style.dart';

/// Markdown 编辑文档的值对象
///
/// [title] 为 `null` 表示单字段模式（如背景设定，只有正文）；
/// 非 `null` 表示双字段模式（如大纲，含标题与正文）。
@immutable
class MarkdownEditorDoc {
  final String? title;
  final String content;

  const MarkdownEditorDoc({this.title, required this.content});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownEditorDoc &&
          other.title == title &&
          other.content == content;

  @override
  int get hashCode => Object.hash(title, content);
}

/// 通用 Markdown 编辑 / 预览页
///
/// 内聚以下统一行为，消除 [OutlineScreen] / [BackgroundSettingScreen] 的重复：
/// - 编辑 / 预览双 Tab（[DefaultTabController]）
/// - 2 秒防抖自动保存；编辑切预览时强制 auto-save
/// - [PopScope] 拦截未保存修改，弹 [ConfirmDialog] 二次确认
/// - 加载 / 保存异常统一走 [ErrorHelper] / [LoggerService]
///
/// 调用方仅需提供 [load] / [save] 两个回调与少量文案参数，
/// 数据源差异（大纲 upsert / 背景设定 update）完全封装在闭包内。
class MarkdownEditorScreen extends ConsumerStatefulWidget {
  /// AppBar 主标题（如「大纲」「背景设定」）。
  final String appBarTitle;

  /// AppBar 副标题（书名）。
  final String appBarSubtitle;

  /// 加载初始文档。抛错由组件内部捕获并降级为空内容 + 错误提示。
  final Future<MarkdownEditorDoc> Function() load;

  /// 保存文档。正常返回视为成功，抛错由组件内部统一处理。
  /// `auto=true` 表示防抖触发的自动保存；`false` 表示手动保存。
  final Future<void> Function(MarkdownEditorDoc doc, {required bool auto}) save;

  /// 日志 tag（如 `'outline'` / `'background'`），用于 `[tag, 'save'|'auto-save', 'failed']`。
  final String logTag;

  /// 非空时渲染标题输入框（双字段模式）；`null` 表示单字段模式。
  final String? titleHint;

  /// 标题留空时保存用的占位值（如大纲以书名为默认标题）。
  final String? titleFallback;

  /// 正文输入框 hint。
  final String? contentHint;

  /// 预览空态文案。
  final String? emptyText;

  /// 手动保存成功 toast（如「大纲已保存」）。
  final String? savedToast;

  /// 自动保存成功 toast。
  final String autoSavedToast;

  const MarkdownEditorScreen({
    required this.appBarTitle,
    required this.appBarSubtitle,
    required this.load,
    required this.save,
    required this.logTag,
    this.titleHint,
    this.titleFallback,
    this.contentHint,
    this.emptyText,
    this.savedToast,
    this.autoSavedToast = '已自动保存',
    super.key,
  });

  @override
  ConsumerState<MarkdownEditorScreen> createState() =>
      _MarkdownEditorScreenState();
}

class _MarkdownEditorScreenState extends ConsumerState<MarkdownEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  MarkdownEditorDoc _original = const MarkdownEditorDoc(content: '');
  bool _isSaving = false;
  bool _isModified = false;
  bool _isLoading = true;
  Timer? _autoSaveTimer;
  int _currentTabIndex = 0; // 0=编辑, 1=预览

  bool get _hasTitle => widget.titleHint != null;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTextChanged);
    _contentController.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTextChanged);
    _contentController.removeListener(_onTextChanged);
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ─── 数据加载 ───────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final doc = await widget.load();
      if (!mounted) return;
      setState(() {
        _titleController.text = doc.title ?? '';
        _contentController.text = doc.content;
        _original = MarkdownEditorDoc(
          title: doc.title,
          content: doc.content,
        );
        _isModified = false;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      // 加载失败：调用方负责在 load 闭包内返回兜底值；
      // 若仍抛到此处，统一报错并降级为空内容，不崩溃。
      LoggerService.instance.e(
        '加载${widget.appBarTitle}失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: [widget.logTag, 'load', 'failed'],
      );
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ─── 文本变化 & 自动保存 ────────────────────────────────────

  void _onTextChanged() {
    final wasModified = _isModified;
    _isModified = _titleController.text != (_original.title ?? '') ||
        _contentController.text != _original.content;
    if (wasModified != _isModified) {
      setState(() {});
    }
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (_isModified && mounted) {
        _save(auto: true);
      }
    });
  }

  Future<void> _save({bool auto = false}) async {
    if (_isSaving) return;
    _autoSaveTimer?.cancel();
    setState(() => _isSaving = true);

    try {
      final title = _hasTitle
          ? (_titleController.text.trim().isEmpty
              ? (widget.titleFallback ?? '')
              : _titleController.text.trim())
          : null;
      final doc = MarkdownEditorDoc(
        title: title,
        content: _contentController.text,
      );
      await widget.save(doc, auto: auto);

      if (!mounted) return;
      setState(() {
        _original = doc;
        _isModified = false;
      });
      if (auto) {
        ToastUtils.showInfo(widget.autoSavedToast);
      } else {
        if (widget.savedToast != null) {
          ToastUtils.showSuccess(widget.savedToast!);
        }
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      if (auto) {
        LoggerService.instance.w(
          '${widget.appBarTitle}自动保存失败',
          stackTrace: stackTrace.toString(),
          category: LogCategory.database,
          tags: [widget.logTag, 'auto-save', 'failed'],
        );
      } else {
        ErrorHelper.showErrorWithLog(
          context,
          '保存失败',
          error: e,
          stackTrace: stackTrace,
          category: LogCategory.database,
          tags: [widget.logTag, 'save', 'failed'],
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_isModified) return true;
    final result = await ConfirmDialog.show(
      context,
      title: '放弃修改？',
      message: '您有未保存的修改，确定要放弃吗？',
      confirmText: '放弃修改',
      cancelText: '继续编辑',
      confirmColor: context.appColors.error,
    );
    return result ?? false;
  }

  Future<void> _onTabChanged(int index) async {
    // 从编辑切到预览时，若有改动先自动保存
    if (_currentTabIndex == 0 && index == 1 && _isModified) {
      await _save(auto: true);
    }
    setState(() => _currentTabIndex = index);
  }

  // ─── 构建 ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: _currentTabIndex,
      child: PopScope(
        canPop: !_isModified,
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) return;
          final shouldPop = await _confirmDiscardChanges();
          if (shouldPop && context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.appBarTitle,
                  style: AppTypography.chapterTitle.copyWith(fontSize: 18),
                ),
                Text(
                  widget.appBarSubtitle,
                  style: AppTypography.metaItalic.copyWith(
                    fontSize: 12,
                    color: context.appColors.inkSoft,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      )
                    : const Icon(Icons.save),
                onPressed: (_isSaving || !_isModified) ? null : () => _save(),
                tooltip: '保存',
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TabBar(
                        tabs: const [
                          Tab(text: '编辑', icon: Icon(Icons.edit)),
                          Tab(text: '预览', icon: Icon(Icons.preview)),
                        ],
                        labelColor: Theme.of(context).colorScheme.primary,
                        onTap: _onTabChanged,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildEditMode(),
                            _buildPreviewMode(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildEditMode() {
    return Column(
      children: [
        if (_hasTitle) ...[
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: '${widget.appBarTitle}标题',
              hintText: widget.titleHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: TextField(
            controller: _contentController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.contentHint ?? '在此输入内容（支持 Markdown 格式）...',
              contentPadding: const EdgeInsets.all(16),
              counterText: '${_contentController.text.length} 字符',
            ),
            style: AppTypography.bodyProse.copyWith(
              fontSize: 16,
              height: 1.5,
              color: context.appColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: context.appColors.inkSoft,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _isModified
                    ? '内容已修改，2 秒后自动保存或点击右上角保存'
                    : '点击右上角保存按钮保存修改',
                style: AppTypography.metaItalic.copyWith(
                  color: _isModified
                      ? context.appColors.warning
                      : context.appColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewMode() {
    final content = _contentController.text.trim();
    final hasTitle = _hasTitle && _titleController.text.trim().isNotEmpty;
    if (content.isEmpty) {
      return Center(
        child: Text(
          widget.emptyText ??
              (hasTitle ? '暂无内容' : '暂无${widget.appBarTitle}，可在「编辑」页创建'),
          style: AppTypography.bodyProse.copyWith(
            fontSize: 16,
            color: context.appColors.inkSoft,
          ),
        ),
      );
    }

    return Markdown(
      data: content,
      selectable: true,
      padding: const EdgeInsets.all(16),
      styleSheet: buildProseMarkdownStyle(context),
    );
  }
}

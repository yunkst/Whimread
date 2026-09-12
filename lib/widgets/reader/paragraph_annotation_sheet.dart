import 'package:flutter/material.dart';
import '../../models/paragraph_annotation.dart';
import '../../core/theme/app_typography.dart';

/// 段落标注编辑弹层
///
/// 阅读页长按段落后弹出：输入/编辑该段落的个人标注，支持删除。
/// 保存/删除的实际写库由调用方通过回调完成，回调返回 true 才关闭弹层。
class ParagraphAnnotationSheet extends StatefulWidget {
  /// 长按段落的预览文本（回显上下文）
  final String paragraphPreview;

  /// 已有标注（编辑模式），null 表示新增
  final ParagraphAnnotation? existing;

  /// 保存回调，返回是否成功
  final Future<bool> Function(String content) onSave;

  /// 删除回调，仅在编辑模式下可用，返回是否成功
  final Future<bool> Function() onDelete;

  const ParagraphAnnotationSheet({
    super.key,
    required this.paragraphPreview,
    required this.existing,
    required this.onSave,
    required this.onDelete,
  });

  /// 弹出标注编辑弹层
  static Future<void> show(
    BuildContext context, {
    required String paragraphPreview,
    ParagraphAnnotation? existing,
    required Future<bool> Function(String content) onSave,
    required Future<bool> Function() onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParagraphAnnotationSheet(
        paragraphPreview: paragraphPreview,
        existing: existing,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<ParagraphAnnotationSheet> createState() =>
      _ParagraphAnnotationSheetState();
}

class _ParagraphAnnotationSheetState extends State<ParagraphAnnotationSheet> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existing?.content ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving) return;

    setState(() => _saving = true);
    final ok = await widget.onSave(content);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete() async {
    if (_saving) return;

    // 删除前确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除标注', style: AppTypography.chapterTitle.copyWith(fontSize: 18)),
        content: Text(
          '确定要删除这条段落标注吗？删除后不可恢复。',
          style: AppTypography.bodyProse.copyWith(
            fontSize: 15,
            height: 1.6,
            color: Theme.of(dialogContext).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final ok = await widget.onDelete();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.existing != null;

    return Padding(
      // 键盘弹出时抬升弹层
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽把手
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标题
              Text(
                isEditing ? '编辑标注' : '添加标注',
                style: AppTypography.chapterTitle.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 8),
              // 段落上下文回显
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.paragraphPreview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metaItalic.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 标注输入框
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText: '写下你对这段文字的想法...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: AppTypography.bodyProse.copyWith(fontSize: 15),
                onSubmitted: (_) => _handleSave(),
              ),
              const SizedBox(height: 12),
              // 操作按钮
              Row(
                children: [
                  if (isEditing)
                    TextButton(
                      onPressed: _saving ? null : _handleDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      child: const Text('删除标注'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final canSave =
                          value.text.trim().isNotEmpty && !_saving;
                      return ElevatedButton(
                        onPressed: canSave ? _handleSave : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                        child: Text(_saving ? '保存中...' : '保存'),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

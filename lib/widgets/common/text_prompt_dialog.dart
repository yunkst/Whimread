import 'package:flutter/material.dart';
import 'base_stateful_dialog.dart';

/// 通用文本输入对话框
///
/// 用 StatefulWidget 内部管理 [TextEditingController] 生命周期（dispose 释放，
/// 避免泄漏），返回 trim 后的输入文本，null 表示用户取消。
///
/// 继承 [BaseStatefulDialog],内容拆到 [buildContent]、按钮拆到 [buildActions];
/// State 通过 [BaseStatefulDialogState] 复用共享的 helper 与默认样式。
///
/// 用法：
/// ```dart
/// final name = await TextPromptDialog.show(
///   context,
///   title: '重命名分组',
///   initialValue: currentName,
///   label: '分组名',
/// );
/// if (name != null && name.isNotEmpty) { ... }
/// ```
class TextPromptDialog extends BaseStatefulDialog {
  final String? initialValue;
  final String? label;
  final String confirmText;
  final String cancelText;

  const TextPromptDialog({
    super.key,
    required super.title,
    this.initialValue,
    this.label,
    this.confirmText = '保存',
    this.cancelText = '取消',
  });

  /// 弹出文本输入对话框。
  ///
  /// - 返回 trim 后的输入字符串（可能为空字符串）
  /// - 用户点击取消或关闭弹窗 → 返回 null
  /// [barrierDismissible] 透传给 [showDialog]，默认 true（与改造前行为一致）。
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? initialValue,
    String? label,
    String confirmText = '保存',
    String cancelText = '取消',
    bool barrierDismissible = true,
  }) {
    return BaseStatefulDialog.show<String>(
      context: context,
      barrierDismissible: barrierDismissible,
      dialog: TextPromptDialog(
        title: title,
        initialValue: initialValue,
        label: label,
        confirmText: confirmText,
        cancelText: cancelText,
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    // 实际的 TextField 由 State 持有（控制器要 dispose），
    // 此处仅作契约占位。buildDialog 里直接使用 State 提供的 TextField。
    return const SizedBox.shrink();
  }

  @override
  TextPromptDialogState createState() => TextPromptDialogState();
}

/// [TextPromptDialog] 的 State
///
/// 单独声明为 public,便于需要访问内部状态或扩展行为的子类继承。
class TextPromptDialogState extends BaseStatefulDialogState<TextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _controller.text.trim();
    if (t.isNotEmpty) {
      Navigator.of(context).pop(t);
    }
  }

  /// 重写 buildDialog 以保持与改造前字节级一致的 [AlertDialog]:
  /// 不传 contentPadding / elevation / shape 等参数(原文件即如此),
  /// 直接使用 widget 的 [TextEditingController] 与按钮配置。
  @override
  Widget buildDialog(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title!),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelText),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

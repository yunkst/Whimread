import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../utils/toast_utils.dart';

/// 小说书名编辑对话框
///
/// 用于修改本地数据库中的小说书名
class NovelEditDialog extends StatefulWidget {
  /// 原始书名
  final String originalTitle;

  /// 取消回调
  final VoidCallback onCancel;

  /// 确认回调，传入新书名
  final Function(String newTitle) onConfirm;

  const NovelEditDialog({
    super.key,
    required this.originalTitle,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<NovelEditDialog> createState() => _NovelEditDialogState();

  /// 显示编辑对话框
  ///
  /// 返回用户是否确认修改
  static Future<bool?> show({
    required BuildContext context,
    required String originalTitle,
    required Function(String newTitle) onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => NovelEditDialog(
        originalTitle: originalTitle,
        onCancel: () => Navigator.pop(dialogContext, false),
        onConfirm: (newTitle) {
          if (newTitle.trim().isEmpty) {
            ToastUtils.showError('书名不能为空', context: dialogContext);
            return;
          }
          Navigator.pop(dialogContext, true);
          onConfirm(newTitle.trim());
        },
      ),
    );
  }
}

class _NovelEditDialogState extends State<NovelEditDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.originalTitle);
    // 自动选中全部文本，方便用户直接输入
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: 0),
    ).copyWith(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit, color: context.appColors.info),
          const SizedBox(width: 8),
          Text('编辑书名'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '书名',
            hintText: '请输入小说书名',
            border: OutlineInputBorder(),
          ),
          maxLength: 100,
          buildCounter: (context,
              {required currentLength, required isFocused, maxLength}) {
            return Text(
              '$currentLength/$maxLength',
              style: const TextStyle(fontSize: 12),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => widget.onConfirm(_controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

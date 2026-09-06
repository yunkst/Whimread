/// 提示词分类编辑对话框
///
/// 从 `prompt_tag_management_screen.dart` 拆出。负责分类的新增/编辑：
/// 维护一个 name TextField，保存后返回 [PromptTagCategory]。
library;

import 'package:flutter/material.dart';

import '../../../models/prompt_tag_category.dart';

class CategoryEditDialog extends StatefulWidget {
  final PromptTagCategory? category;

  const CategoryEditDialog({super.key, this.category});

  @override
  State<CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<CategoryEditDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.category != null;
    return AlertDialog(
      title: Text(isEditing ? '编辑分类' : '添加分类'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '分类名称',
          hintText: '如：风格、场景、人物',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入分类名称')),
      );
      return;
    }
    final now = DateTime.now();
    final category = PromptTagCategory(
      id: widget.category?.id,
      name: name,
      sortOrder: widget.category?.sortOrder ?? 0,
      createdAt: widget.category?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.pop(context, category);
  }
}

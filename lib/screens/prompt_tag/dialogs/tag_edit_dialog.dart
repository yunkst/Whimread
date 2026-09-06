/// 提示词标签编辑对话框
///
/// 从 `prompt_tag_management_screen.dart` 拆出。负责标签的新增/编辑/移动分类，
/// 以及"添加同名标签"场景（[presetName] 不为空时 name 只读）。
/// 保存后返回 [PromptTag]。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/prompt_tag.dart';
import '../../../models/prompt_tag_category.dart';

class TagEditDialog extends StatefulWidget {
  final PromptTag? tag;
  final int categoryId;
  final String categoryName;
  final List<PromptTagCategory> categories;
  final String? presetName;

  /// 仅编辑模式（[tag] != null）下生效：点击 actions 区「删除」按钮时回调。
  /// 由外层 Screen 负责二次确认 + 实际删除。
  final VoidCallback? onDeleteRequested;

  const TagEditDialog({
    super.key,
    this.tag,
    required this.categoryId,
    required this.categoryName,
    required this.categories,
    this.presetName,
    this.onDeleteRequested,
  });

  @override
  State<TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<TagEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _reasonController;
  late final TextEditingController _promptTextController;
  late int _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.presetName ?? widget.tag?.name ?? '',
    );
    _reasonController = TextEditingController(
      text: widget.tag?.reason ?? '',
    );
    _promptTextController = TextEditingController(
      text: widget.tag?.promptText ?? '',
    );
    _selectedCategoryId = widget.tag?.categoryId ?? widget.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    _promptTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.tag != null;
    final hasPresetName = widget.presetName != null;

    return AlertDialog(
      title: Text(isEditing ? '编辑标签' : '添加标签'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 分类选择
            DropdownButtonFormField<int>(
              initialValue: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: '所属分类',
                border: OutlineInputBorder(),
              ),
              items: widget.categories
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      ))
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  setState(() => _selectedCategoryId = id);
                }
              },
            ),
            const SizedBox(height: 12),
            // 标签名称
            TextField(
              controller: _nameController,
              readOnly: hasPresetName,
              decoration: InputDecoration(
                labelText: '标签名称',
                hintText: '如：赛博朋克、暗黑',
                border: const OutlineInputBorder(),
                filled: hasPresetName,
                fillColor: hasPresetName
                    ? context.appColors.divider.withValues(alpha: 0.3)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            // 使用场景
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: '使用场景',
                hintText: '简述何时该用这个标签（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Prompt 文本
            TextField(
              controller: _promptTextController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Prompt 文本',
                hintText: '输入该标签对应的 prompt 内容',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        // 编辑模式下显示「删除」按钮（左侧，红色）→ 触发外层回调
        if (isEditing && widget.onDeleteRequested != null)
          TextButton(
            onPressed: widget.onDeleteRequested,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
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
    final reason = _reasonController.text.trim();
    final promptText = _promptTextController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标签名称')),
      );
      return;
    }
    if (promptText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 Prompt 文本')),
      );
      return;
    }

    final now = DateTime.now();
    final tag = PromptTag(
      id: widget.tag?.id,
      categoryId: _selectedCategoryId,
      name: name,
      reason: reason,
      promptText: promptText,
      sortOrder: widget.tag?.sortOrder ?? 0,
      createdAt: widget.tag?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.pop(context, tag);
  }
}

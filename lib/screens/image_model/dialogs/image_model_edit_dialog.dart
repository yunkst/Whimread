/// 生图模型编辑对话框
///
/// 新增/编辑 image_models 条目。导入流程（管理页）会预填文件路径/大小/默认名。
/// 保存后通过 Navigator.pop 返回 [ImageModel]，由外层 Screen 落库。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/image_model.dart';
import '../../../utils/format_utils.dart';

class ImageModelEditDialog extends StatefulWidget {
  /// 编辑已有模型时传入；新增为 null
  final ImageModel? model;

  /// 导入流程预填的模型文件路径（local_sd）
  final String? presetFilePath;

  /// 导入流程预填的文件大小（字节）
  final int? presetFileSize;

  /// 导入流程预填的默认名（来自原始文件名，去掉 .gguf 后缀）
  final String? presetName;

  /// 当前已占用的模型名（用于同步唯一性校验；不含正在编辑的自身）
  final Set<String> existingNames;

  const ImageModelEditDialog({
    super.key,
    this.model,
    this.presetFilePath,
    this.presetFileSize,
    this.presetName,
    this.existingNames = const {},
  });

  @override
  State<ImageModelEditDialog> createState() => _ImageModelEditDialogState();
}

class _ImageModelEditDialogState extends State<ImageModelEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _stepsController;
  late final TextEditingController _cfgController;

  late List<String> _tags;
  late String _filePath;
  late int _fileSize;
  late bool _isEnabled;
  late bool _isDefault;

  /// 高级参数区默认折叠（多数用户不需要动）
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    final m = widget.model;
    _nameController = TextEditingController(
      text: widget.presetName ?? m?.name ?? '',
    );
    _descriptionController = TextEditingController(text: m?.description ?? '');
    _tagController = TextEditingController();
    _widthController = TextEditingController(text: '${m?.defaultWidth ?? 512}');
    _heightController =
        TextEditingController(text: '${m?.defaultHeight ?? 512}');
    _stepsController = TextEditingController(text: '${m?.defaultSteps ?? 20}');
    _cfgController =
        TextEditingController(text: (m?.defaultCfg ?? 7.0).toString());
    _tags = m != null ? List.of(m.tags) : [];
    _filePath = m?.filePath ?? widget.presetFilePath ?? '';
    _fileSize = m?.fileSize ?? widget.presetFileSize ?? 0;
    _isEnabled = m?.isEnabled ?? true;
    _isDefault = m?.isDefault ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _stepsController.dispose();
    _cfgController.dispose();
    super.dispose();
  }

  void _addTag() {
    final text = _tagController.text.trim();
    if (text.isEmpty) return;
    if (_tags.contains(text)) {
      _tagController.clear();
      return;
    }
    if (_tags.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多 10 个标签')),
      );
      return;
    }
    setState(() {
      _tags = [..._tags, text];
      _tagController.clear();
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入模型名称')),
      );
      return;
    }
    // 唯一性校验（唯一索引兜底在 repository 层）
    if (widget.existingNames.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型名称 "$name" 已存在，请换一个')),
      );
      return;
    }
    if (_filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地引擎模型需要先导入 .gguf 模型文件')),
      );
      return;
    }

    final width = int.tryParse(_widthController.text.trim()) ?? 512;
    final height = int.tryParse(_heightController.text.trim()) ?? 512;
    final steps = int.tryParse(_stepsController.text.trim()) ?? 20;
    final cfg = double.tryParse(_cfgController.text.trim()) ?? 7.0;

    final now = DateTime.now();
    final model = ImageModel(
      id: widget.model?.id,
      name: name,
      description: _descriptionController.text.trim(),
      tags: _tags,
      filePath: _filePath,
      fileSize: _fileSize,
      previewMediaId: widget.model?.previewMediaId,
      defaultWidth: width.clamp(64, 2048),
      defaultHeight: height.clamp(64, 2048),
      defaultSteps: steps.clamp(1, 100),
      defaultCfg: cfg.clamp(1.0, 30.0),
      isEnabled: _isEnabled,
      isDefault: _isDefault,
      sortOrder: widget.model?.sortOrder ?? 0,
      createdAt: widget.model?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.pop(context, model);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.model != null;
    final hasPresetFile = widget.presetFilePath != null;

    return AlertDialog(
      title: Text(isEditing ? '编辑生图模型' : '添加生图模型'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 模型名称（agent 用作 key，导入时预填文件名）
            TextField(
              controller: _nameController,
              readOnly: hasPresetFile,
              decoration: InputDecoration(
                labelText: '模型名称（唯一）',
                hintText: '如：古风水墨、写实人物',
                helperText: 'Agent 根据描述和标签挑选时以此名字为 key',
                border: const OutlineInputBorder(),
                filled: hasPresetFile,
                fillColor: hasPresetFile
                    ? Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            // 模型特点描述（agent 推理依据，越具体越好）
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: '模型特点（Agent 选型依据）',
                hintText: '描述这个模型擅长什么，如：擅长中国古风水墨插画，'
                    '适合山水、建筑、古装人物；不太适合写实人脸',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            // 标签输入
            _TagsField(
              tags: _tags,
              controller: _tagController,
              onAdd: _addTag,
              onRemove: (tag) => setState(() {
                _tags = _tags.where((e) => e != tag).toList();
              }),
            ),
            const SizedBox(height: 12),
            // 模型文件信息
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filePath.isEmpty
                          ? '尚未导入模型文件（保存前需先导入）'
                          : '${_filePath.split(Platform.pathSeparator).last}\n'
                              '${FormatUtils.formatFileSize(_fileSize)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 启用 / 默认
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用'),
                    subtitle: const Text('停用后 Agent 不可见'),
                    value: _isEnabled,
                    onChanged: (v) => setState(() => _isEnabled = v),
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('默认'),
                    subtitle: const Text('不指定模型时使用'),
                    value: _isDefault,
                    onChanged: (v) => setState(() => _isDefault = v),
                  ),
                ),
              ],
            ),
            // 高级参数（折叠）
            TextButton.icon(
              onPressed: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              icon: Icon(_advancedExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down),
              label: const Text('默认出图参数（可选）'),
            ),
            if (_advancedExpanded)
              Row(
                children: [
                  _numField(_widthController, '宽', 3),
                  _numField(_heightController, '高', 3),
                  _numField(_stepsController, '步数', 3),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _cfgController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'CFG',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
          ],
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

  Widget _numField(
    TextEditingController controller,
    String label,
    int flex,
  ) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}

/// 标签输入区（Wrap chips + 输入框回车追加）
class _TagsField extends StatelessWidget {
  final List<String> tags;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _TagsField({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('标签（如：古风、写实、风景）'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ...tags.map(
              (t) => InputChip(
                label: Text(t),
                onDeleted: () => onRemove(t),
              ),
            ),
            SizedBox(
              width: 140,
              height: 40,
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '输入后回车',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 生图模型编辑对话框
///
/// 编辑 image_models 条目的展示信息（名称/特点/标签/负向提示词）与
/// 默认出图参数。保存后通过 Navigator.pop 返回 [ImageModel]，
/// 由外层 Screen 落库。模型包文件本身由下载器/导入流程管理，此处不改。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/image_model.dart';
import '../../../services/local_dream_embedded/model_pack.dart';
import '../../../utils/toast_utils.dart';

class ImageModelEditDialog extends StatefulWidget {
  final ImageModel model;

  /// 当前已占用的模型名（用于同步唯一性校验；不含正在编辑的自身）
  final Set<String> existingNames;

  const ImageModelEditDialog({
    super.key,
    required this.model,
    this.existingNames = const {},
  });

  @override
  State<ImageModelEditDialog> createState() => _ImageModelEditDialogState();
}

class _ImageModelEditDialogState extends State<ImageModelEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _negativePromptController;
  late final TextEditingController _tagController;
  late final TextEditingController _stepsController;
  late final TextEditingController _cfgController;

  /// 默认出图比例（仅 SDXL 包展示/生效；空 = 1:1）
  late String _aspectRatio;

  late List<String> _tags;
  late bool _isEnabled;
  late bool _isDefault;

  /// 高级参数区默认折叠（多数用户不需要动）
  bool _advancedExpanded = false;

  /// SDXL 包才有比例概念（SD1.5 固定 1:1，SDXL 固定 1024 画布合成裁切）
  bool get _isSdxl =>
      LocalDreamPackType.parse(widget.model.remoteModelId) ==
      LocalDreamPackType.sdxl;

  static const _aspectPresets = ['1:1', '3:4', '4:3', '16:9', '9:16'];

  @override
  void initState() {
    super.initState();
    final m = widget.model;
    _nameController = TextEditingController(text: m.name);
    _descriptionController = TextEditingController(text: m.description);
    _negativePromptController =
        TextEditingController(text: m.negativePrompt);
    _tagController = TextEditingController();
    _stepsController = TextEditingController(text: '${m.defaultSteps}');
    _cfgController = TextEditingController(text: m.defaultCfg.toString());
    _aspectRatio = m.defaultAspectRatio.isEmpty ||
            !_aspectPresets.contains(m.defaultAspectRatio)
        ? '1:1'
        : m.defaultAspectRatio;
    _tags = List.of(m.tags);
    _isEnabled = m.isEnabled;
    _isDefault = m.isDefault;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _negativePromptController.dispose();
    _tagController.dispose();
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
      ToastUtils.showError('最多 10 个标签', context: context);
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
      ToastUtils.showError('请输入模型名称', context: context);
      return;
    }
    // 唯一性校验（唯一索引兜底在 repository 层）
    if (widget.existingNames.contains(name)) {
      ToastUtils.showError('模型名称 "$name" 已存在，请换一个', context: context);
      return;
    }

    final steps = int.tryParse(_stepsController.text.trim()) ?? 20;
    final cfg = double.tryParse(_cfgController.text.trim()) ?? 7.0;

    final model = widget.model.copyWith(
      name: name,
      description: _descriptionController.text.trim(),
      tags: _tags,
      negativePrompt: _negativePromptController.text.trim(),
      defaultAspectRatio: _isSdxl ? _aspectRatio : '',
      defaultSteps: steps.clamp(1, 100),
      defaultCfg: cfg.clamp(1.0, 30.0),
      isEnabled: _isEnabled,
      isDefault: _isDefault,
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, model);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑生图模型'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 模型名称（agent 用作 key）
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '模型名称（唯一）',
                helperText: 'Agent 根据描述和标签挑选时以此名字为 key',
                border: OutlineInputBorder(),
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
            // 负向提示词预设（agent 不传 negativePrompt，由模型统一提供）
            TextField(
              controller: _negativePromptController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '负向提示词（预设）',
                hintText: '如：worst quality, extra fingers, blurry, watermark',
                helperText: '每次用该模型生图时自动附加，Agent 无需再传',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
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
            // 默认出图比例（仅 SDXL：引擎固定 1024 画布按比例合成裁切）
            if (_isSdxl) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _aspectRatio,
                decoration: const InputDecoration(
                  labelText: '出图比例（SDXL）',
                  helperText: '画布固定 1024，按比例合成后裁切；Agent 未指定时使用',
                  border: OutlineInputBorder(),
                ),
                items: _aspectPresets
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _aspectRatio = v);
                },
              ),
            ],
            // 高级参数（折叠）
            TextButton.icon(
              onPressed: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              icon: Icon(_advancedExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down),
              label: const Text('默认步数 / CFG（可选）'),
            ),
            if (_advancedExpanded)
              Row(
                children: [
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

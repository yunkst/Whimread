/// Local Dream 设备模型添加/编辑对话框
///
/// 与 [ImageModelEditDialog]（本地文件模型）并列：填设备地址 →
/// "获取设备模型"拉取 /models 目录并下拉选择 → 自动填充默认参数。
/// 保存后通过 Navigator.pop 返回 backendType=localDream 的 [ImageModel]，
/// 由外层 Screen 落库。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/image_model.dart';
import '../../../services/image_generation/local_dream_client.dart';

class LocalDreamModelDialog extends StatefulWidget {
  /// 编辑已有模型时传入；新增为 null
  final ImageModel? model;

  /// 当前已占用的模型名（用于同步唯一性校验；不含正在编辑的自身）
  final Set<String> existingNames;

  const LocalDreamModelDialog({
    super.key,
    this.model,
    this.existingNames = const {},
  });

  @override
  State<LocalDreamModelDialog> createState() => _LocalDreamModelDialogState();
}

class _LocalDreamModelDialogState extends State<LocalDreamModelDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _negativePromptController;
  late final TextEditingController _tagController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _stepsController;
  late final TextEditingController _cfgController;

  late List<String> _tags;
  late bool _isEnabled;
  late bool _isDefault;
  bool _advancedExpanded = false;

  /// 设备模型目录（"获取设备模型"成功后填充）
  List<LocalDreamCatalogModel> _catalogModels = const [];
  String? _selectedModelId;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    final m = widget.model;
    _nameController = TextEditingController(text: m?.name ?? '');
    _hostController = TextEditingController(text: m?.remoteHost ?? '');
    _descriptionController = TextEditingController(text: m?.description ?? '');
    _negativePromptController =
        TextEditingController(text: m?.negativePrompt ?? '');
    _tagController = TextEditingController();
    _widthController =
        TextEditingController(text: '${m?.defaultWidth ?? 512}');
    _heightController =
        TextEditingController(text: '${m?.defaultHeight ?? 512}');
    _stepsController = TextEditingController(text: '${m?.defaultSteps ?? 20}');
    _cfgController =
        TextEditingController(text: (m?.defaultCfg ?? 7.0).toString());
    _tags = m != null ? List.of(m.tags) : [];
    _isEnabled = m?.isEnabled ?? true;
    _isDefault = m?.isDefault ?? false;
    _selectedModelId = (m?.remoteModelId.isNotEmpty ?? false)
        ? m!.remoteModelId
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _descriptionController.dispose();
    _negativePromptController.dispose();
    _tagController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _stepsController.dispose();
    _cfgController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 拉取设备模型目录（兼做连通性测试）
  Future<void> _fetchModels() async {
    final host = LocalDreamClient.normalizeHost(_hostController.text);
    if (host.isEmpty) {
      _showSnack('请先输入设备地址（手机 IP）');
      return;
    }
    setState(() => _fetching = true);
    final client = LocalDreamClient(host: host);
    try {
      final list = await client.models();
      if (!mounted) return;
      setState(() {
        _catalogModels = list;
        if (!list.any((m) => m.id == _selectedModelId)) {
          _selectedModelId = null;
        }
      });
      if (list.isEmpty) {
        _showSnack('已连上设备，但还没有已安装的模型，请先在 Local Dream 中下载');
      } else {
        _showSnack('已获取 ${list.length} 个设备模型，请选择一个');
      }
    } on LocalDreamException catch (e) {
      _showSnack(e.message);
    } finally {
      client.close();
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// 选中设备模型后自动填充默认参数与元数据（仅填空缺项，不覆盖已填内容）
  void _onCatalogModelSelected(String? id) {
    if (id == null) {
      setState(() => _selectedModelId = null);
      return;
    }
    LocalDreamCatalogModel? deviceModel;
    for (final m in _catalogModels) {
      if (m.id == id) {
        deviceModel = m;
        break;
      }
    }
    setState(() => _selectedModelId = id);
    if (deviceModel == null) return;

    if (_nameController.text.trim().isEmpty) {
      _nameController.text = deviceModel.name;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _descriptionController.text = deviceModel.description.isEmpty
          ? 'Local Dream 设备上的模型（${deviceModel.id}）'
          : deviceModel.description;
    }
    if (_negativePromptController.text.trim().isEmpty &&
        deviceModel.defaultNegativePrompt.isNotEmpty) {
      _negativePromptController.text = deviceModel.defaultNegativePrompt;
    }
    if (_tags.isEmpty) {
      _tags = ['远程设备', deviceModel.isSdxl ? 'SDXL' : 'SD1.5'];
    }
    _widthController.text = '${deviceModel.generationSize}';
    _heightController.text = '${deviceModel.generationSize}';
    _stepsController.text = '${deviceModel.defaultSteps}';
    _cfgController.text = deviceModel.defaultCfg.toString();
  }

  void _addTag() {
    final text = _tagController.text.trim();
    if (text.isEmpty) return;
    if (_tags.contains(text)) {
      _tagController.clear();
      return;
    }
    if (_tags.length >= 10) {
      _showSnack('最多 10 个标签');
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
      _showSnack('请输入模型名称');
      return;
    }
    if (widget.existingNames.contains(name)) {
      _showSnack('模型名称 "$name" 已存在，请换一个');
      return;
    }
    final host = LocalDreamClient.normalizeHost(_hostController.text);
    if (host.isEmpty) {
      _showSnack('请输入设备地址（手机 IP，如 192.168.31.76）');
      return;
    }
    if (_selectedModelId == null || _selectedModelId!.isEmpty) {
      _showSnack('请先获取设备模型并选择一个');
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
      backendType: ImageModelBackendType.localDream,
      remoteHost: host,
      remoteModelId: _selectedModelId!,
      negativePrompt: _negativePromptController.text.trim(),
      previewMediaId: widget.model?.previewMediaId,
      defaultWidth: width.clamp(64, 4096),
      defaultHeight: height.clamp(64, 4096),
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
    return AlertDialog(
      title: Text(isEditing ? '编辑 Local Dream 设备模型' : '添加 Local Dream 设备模型'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 设备地址 + 获取按钮
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _hostController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '设备地址（手机 IP）',
                      hintText: '如 192.168.31.76',
                      helperText: '手机与该设备需在同一网络，宿主模式已开启且屏幕未锁定',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _fetching
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: '获取设备模型',
                          icon: const Icon(Icons.cloud_download_outlined),
                          onPressed: _fetchModels,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 设备模型下拉（获取后可用）
            DropdownButtonFormField<String>(
              initialValue: _selectedModelId,
              decoration: InputDecoration(
                labelText: '设备模型',
                helperText: _catalogModels.isEmpty
                    ? '先点右上角按钮获取设备上的模型列表'
                    : '选中后自动填充默认参数',
                border: const OutlineInputBorder(),
              ),
              items: _catalogModels
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          m.name.isEmpty ? m.id : '${m.name}（${m.id}）',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _catalogModels.isEmpty
                  ? null
                  : _onCatalogModelSelected,
            ),
            const SizedBox(height: 12),
            // 模型名称
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '模型名称（唯一）',
                hintText: '选中设备模型后可自动填充',
                helperText: 'Agent 根据描述和标签挑选时以此名字为 key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 模型特点描述
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: '模型特点（Agent 选型依据）',
                hintText: '描述这个模型擅长什么，选中设备模型后会自动填充',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            // 标签
            _TagsField(
              tags: _tags,
              controller: _tagController,
              onAdd: _addTag,
              onRemove: (tag) => setState(() {
                _tags = _tags.where((e) => e != tag).toList();
              }),
            ),
            const SizedBox(height: 12),
            // 负向提示词预设
            TextField(
              controller: _negativePromptController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '负向提示词（预设）',
                hintText: '选中设备模型后会自动填充其预设',
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
            // 高级参数（折叠）
            TextButton.icon(
              onPressed: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              icon: Icon(_advancedExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down),
              label: const Text('默认出图参数（选中设备模型后自动填充）'),
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

/// 标签输入区（与 ImageModelEditDialog 同款）
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

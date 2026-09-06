import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/database_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../models/character.dart';
import '../models/novel.dart';
import '../services/logger_service.dart';
import '../utils/error_helper.dart';
import '../utils/toast_utils.dart';

/// 人物卡编辑页（新增 / 编辑共用）
///
/// - [existing] 为 null 表示新建，非空表示编辑现有角色。
/// - 保存成功后 `Navigator.pop(true)`，调用方可据此刷新列表/详情。
/// - 编辑时通过 [Character.copyWith] 保留 id / novelUrl / createdAt / cachedImageUrl，
///   因为 [CharacterRepository.updateCharacter] 要求整对象且含 id。
class CharacterEditScreen extends ConsumerStatefulWidget {
  final Novel novel;
  final Character? existing;

  const CharacterEditScreen({
    required this.novel,
    this.existing,
    super.key,
  });

  @override
  ConsumerState<CharacterEditScreen> createState() =>
      _CharacterEditScreenState();
}

class _CharacterEditScreenState extends ConsumerState<CharacterEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _occupationController;
  late final TextEditingController _personalityController;
  late final TextEditingController _appearanceController;
  late final TextEditingController _bodyTypeController;
  late final TextEditingController _clothingController;
  late final TextEditingController _backgroundController;
  late final TextEditingController _facePromptsController;
  late final TextEditingController _bodyPromptsController;

  String? _gender;
  List<String> _aliases = const [];
  bool _isSaving = false;
  bool _aiPromptsExpanded = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nameController = TextEditingController(text: c?.name ?? '');
    _ageController =
        TextEditingController(text: c?.age?.toString() ?? '');
    _occupationController =
        TextEditingController(text: c?.occupation ?? '');
    _personalityController =
        TextEditingController(text: c?.personality ?? '');
    _appearanceController =
        TextEditingController(text: c?.appearanceFeatures ?? '');
    _bodyTypeController = TextEditingController(text: c?.bodyType ?? '');
    _clothingController =
        TextEditingController(text: c?.clothingStyle ?? '');
    _backgroundController =
        TextEditingController(text: c?.backgroundStory ?? '');
    _facePromptsController =
        TextEditingController(text: c?.facePrompts ?? '');
    _bodyPromptsController =
        TextEditingController(text: c?.bodyPrompts ?? '');
    _gender = c?.gender;
    _aliases = List<String>.from(c?.aliases ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _occupationController.dispose();
    _personalityController.dispose();
    _appearanceController.dispose();
    _bodyTypeController.dispose();
    _clothingController.dispose();
    _backgroundController.dispose();
    _facePromptsController.dispose();
    _bodyPromptsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? '编辑人物卡' : '新建人物卡',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _onSave,
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionTitle('基本信息'),
            _buildNameField(),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _buildGenderField()),
                const SizedBox(width: 12),
                Expanded(flex: 1, child: _buildAgeField()),
              ],
            ),
            const SizedBox(height: 12),
            _buildOccupationField(),
            const SizedBox(height: 12),
            _buildAliasesField(),
            const SizedBox(height: 24),

            _buildSectionTitle('性格'),
            _buildMultilineField(
              controller: _personalityController,
              label: '性格特点',
              hint: '冷静沉稳、重情重义……',
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('外貌'),
            _buildMultilineField(
              controller: _appearanceController,
              label: '外貌特征',
              hint: '眉目清秀，左颊有疤……',
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _buildMultilineField(
              controller: _bodyTypeController,
              label: '身材体型',
              hint: '高挑清瘦……',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _buildMultilineField(
              controller: _clothingController,
              label: '穿衣风格',
              hint: '素色长衫，腰佩玉佩……',
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('背景'),
            _buildMultilineField(
              controller: _backgroundController,
              label: '背景经历',
              hint: '出身江南，幼年……',
              maxLines: 5,
            ),
            const SizedBox(height: 24),

            _buildAiPromptsSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── 字段构建 ───────────────────────────────────────────────

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTypography.novelTitle.copyWith(
          fontSize: 15,
          color: context.appColors.agentAccent,
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      autofocus: !_isEditing,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: '姓名 *',
        hintText: '请输入角色姓名',
        border: OutlineInputBorder(),
      ),
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? '姓名不能为空' : null,
    );
  }

  Widget _buildGenderField() {
    return DropdownButtonFormField<String>(
      initialValue: _gender,
      decoration: const InputDecoration(
        labelText: '性别',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: '男', child: Text('男')),
        DropdownMenuItem(value: '女', child: Text('女')),
        DropdownMenuItem(value: '其他', child: Text('其他')),
      ],
      onChanged: (v) => setState(() => _gender = v),
    );
  }

  Widget _buildAgeField() {
    return TextFormField(
      controller: _ageController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '年龄',
        hintText: '可选',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final n = int.tryParse(value.trim());
        if (n == null || n < 0) return '请输入有效年龄';
        return null;
      },
    );
  }

  Widget _buildOccupationField() {
    return TextFormField(
      controller: _occupationController,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: '职业 / 身份',
        hintText: '可选',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildAliasesField() {
    return InputChipList(
      values: _aliases,
      onChanged: (next) => setState(() => _aliases = next),
      label: '别名 / 称号',
      hint: '添加后回车',
      maxLength: 10,
    );
  }

  Widget _buildMultilineField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 3,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildAiPromptsSection() {
    return ExpansionTile(
      initiallyExpanded: _aiPromptsExpanded,
      onExpansionChanged: (v) => _aiPromptsExpanded = v,
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: context.appColors.info),
          const SizedBox(width: 6),
          Text(
            'AI 生图提示词',
            style: AppTypography.novelTitle.copyWith(
              fontSize: 15,
              color: context.appColors.ink,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '普通用户可忽略，供生图功能使用',
        style: AppTypography.metaItalic.copyWith(
          color: context.appColors.inkSoft,
        ),
      ),
      children: [
        const SizedBox(height: 8),
        _buildMultilineField(
          controller: _facePromptsController,
          label: '面部提示词',
          hint: 'face prompts……',
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _buildMultilineField(
          controller: _bodyPromptsController,
          label: '身材提示词',
          hint: 'body prompts……',
          maxLines: 3,
        ),
      ],
    );
  }

  // ─── 保存 ───────────────────────────────────────────────────

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final ageText = _ageController.text.trim();
    final age = ageText.isEmpty ? null : int.tryParse(ageText);
    final aliases = _aliases.isEmpty ? null : _aliases;

    Character target;
    if (_isEditing) {
      target = widget.existing!.copyWith(
        name: _nameController.text.trim(),
        gender: _gender,
        age: age,
        occupation: _occupationController.text.trim().isEmpty
            ? null
            : _occupationController.text.trim(),
        personality: _personalityController.text.trim().isEmpty
            ? null
            : _personalityController.text.trim(),
        appearanceFeatures: _appearanceController.text.trim().isEmpty
            ? null
            : _appearanceController.text.trim(),
        bodyType: _bodyTypeController.text.trim().isEmpty
            ? null
            : _bodyTypeController.text.trim(),
        clothingStyle: _clothingController.text.trim().isEmpty
            ? null
            : _clothingController.text.trim(),
        backgroundStory: _backgroundController.text.trim().isEmpty
            ? null
            : _backgroundController.text.trim(),
        facePrompts: _facePromptsController.text.trim().isEmpty
            ? null
            : _facePromptsController.text.trim(),
        bodyPrompts: _bodyPromptsController.text.trim().isEmpty
            ? null
            : _bodyPromptsController.text.trim(),
        aliases: aliases,
      );
    } else {
      target = Character(
        novelUrl: widget.novel.url,
        name: _nameController.text.trim(),
        gender: _gender,
        age: age,
        occupation: _occupationController.text.trim().isEmpty
            ? null
            : _occupationController.text.trim(),
        personality: _personalityController.text.trim().isEmpty
            ? null
            : _personalityController.text.trim(),
        appearanceFeatures: _appearanceController.text.trim().isEmpty
            ? null
            : _appearanceController.text.trim(),
        bodyType: _bodyTypeController.text.trim().isEmpty
            ? null
            : _bodyTypeController.text.trim(),
        clothingStyle: _clothingController.text.trim().isEmpty
            ? null
            : _clothingController.text.trim(),
        backgroundStory: _backgroundController.text.trim().isEmpty
            ? null
            : _backgroundController.text.trim(),
        facePrompts: _facePromptsController.text.trim().isEmpty
            ? null
            : _facePromptsController.text.trim(),
        bodyPrompts: _bodyPromptsController.text.trim().isEmpty
            ? null
            : _bodyPromptsController.text.trim(),
        aliases: aliases,
      );
    }

    try {
      final repo = ref.read(characterRepositoryProvider);
      if (_isEditing) {
        await repo.updateCharacter(target);
      } else {
        await repo.createCharacter(target);
      }
      if (!mounted) return;
      ToastUtils.showSuccess(
        _isEditing ? '人物卡已更新' : '人物卡已创建',
        context: context,
      );
      Navigator.pop(context, true);
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ErrorHelper.showErrorWithLog(
        context,
        '保存人物卡失败',
        error: e,
        stackTrace: stackTrace,
        category: LogCategory.character,
        tags: ['character', _isEditing ? 'update' : 'create', 'failed'],
      );
    }
  }
}

/// 简易别名/标签编辑器：输入文本回车追加 chip，chip 右侧 ✕ 删除。
class InputChipList extends StatefulWidget {
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final String hint;
  final int maxLength;

  const InputChipList({
    required this.values,
    required this.onChanged,
    required this.label,
    required this.hint,
    this.maxLength = 10,
    super.key,
  });

  @override
  State<InputChipList> createState() => _InputChipListState();
}

class _InputChipListState extends State<InputChipList> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (widget.values.length >= widget.maxLength) {
      ToastUtils.showWarning('最多 ${widget.maxLength} 个', context: context);
      return;
    }
    if (widget.values.contains(text)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.values, text]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTypography.metaItalic.copyWith(
            color: context.appColors.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ...widget.values.map((v) => InputChip(
                  label: Text(v),
                  onDeleted: () =>
                      widget.onChanged(widget.values.where((e) => e != v).toList()),
                )),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

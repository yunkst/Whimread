/// Agent 记忆管理页面
///
/// 让用户查看和管理各场景（写作 / 网页提取）的经验记忆。
/// Agent 在对话中通过 `patch_memory` 工具写入的记忆会持久化到
/// `agent_memory` 表，下次新会话注入 system prompt。
/// 此页面提供手动查看 / 新增 / 编辑 / 删除能力，弥补 Agent 侧的不足。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/database_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/novel_agent/agent_scenario.dart';
import '../services/novel_agent/agent_scenario_factory.dart';
import '../utils/toast_utils.dart';

class AgentMemoryManagementScreen extends ConsumerStatefulWidget {
  const AgentMemoryManagementScreen({super.key});

  @override
  ConsumerState<AgentMemoryManagementScreen> createState() =>
      _AgentMemoryManagementScreenState();
}

class _AgentMemoryManagementScreenState
    extends ConsumerState<AgentMemoryManagementScreen> {
  /// 当前选中场景的记忆列表（含 id 等完整字段）
  List<Map<String, dynamic>> _memories = const [];

  /// 当前选中场景 ID
  String _selectedScenarioId = ScenarioIds.writing;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  /// 加载当前场景的记忆列表
  Future<void> _loadMemories() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(agentMemoryRepositoryProvider);
      final memories = await repo.getAllWithId(_selectedScenarioId);
      if (mounted) {
        setState(() {
          _memories = memories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastUtils.showError('加载记忆失败: $e', context: context);
      }
    }
  }

  /// 切换场景
  void _selectScenario(String scenarioId) {
    if (scenarioId == _selectedScenarioId) return;
    setState(() {
      _selectedScenarioId = scenarioId;
      _memories = const [];
    });
    _loadMemories();
  }

  /// 新增记忆
  Future<void> _addMemory() async {
    final displayName = _currentScenarioDisplayName();
    final content = await showDialog<String>(
      context: context,
      builder: (context) => _MemoryEditDialog(
        scenarioDisplayName: displayName,
      ),
    );
    if (content == null) return;

    try {
      final repo = ref.read(agentMemoryRepositoryProvider);
      await repo.addMemory(_selectedScenarioId, content);
      if (mounted) {
        ToastUtils.showSuccess('记忆已添加', context: context);
      }
      await _loadMemories();
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('添加记忆失败: $e', context: context);
      }
    }
  }

  /// 编辑记忆
  Future<void> _editMemory(Map<String, dynamic> memory) async {
    final id = memory['id'] as int;
    final oldContent = memory['content'] as String;
    final displayName = _currentScenarioDisplayName();

    final newContent = await showDialog<String>(
      context: context,
      builder: (context) => _MemoryEditDialog(
        scenarioDisplayName: displayName,
        existingContent: oldContent,
      ),
    );
    if (newContent == null || newContent == oldContent) return;

    try {
      final repo = ref.read(agentMemoryRepositoryProvider);
      await repo.updateMemory(id, newContent);
      if (mounted) {
        ToastUtils.showSuccess('记忆已更新', context: context);
      }
      await _loadMemories();
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('更新记忆失败: $e', context: context);
      }
    }
  }

  /// 删除记忆（二次确认）
  Future<void> _deleteMemory(Map<String, dynamic> memory) async {
    final id = memory['id'] as int;
    final content = memory['content'] as String;
    final preview = content.length > 40 ? '${content.substring(0, 40)}...' : content;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记忆'),
        content: Text('确定要删除以下记忆吗？\n\n"$preview"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final repo = ref.read(agentMemoryRepositoryProvider);
      await repo.deleteMemory(id);
      if (mounted) {
        ToastUtils.showSuccess('记忆已删除', context: context);
      }
      await _loadMemories();
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('删除记忆失败: $e', context: context);
      }
    }
  }

  /// 获取当前选中场景的显示名
  String _currentScenarioDisplayName() {
    return AgentScenarioFactory.availableScenarios
            .where((s) => s.id == _selectedScenarioId)
            .map((s) => s.displayName)
            .firstOrNull ??
        _selectedScenarioId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agent 记忆管理',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加记忆',
            onPressed: _addMemory,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildScenarioTabs(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 场景切换 ChoiceChip 栏
  Widget _buildScenarioTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: AgentScenarioFactory.availableScenarios.map((info) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${info.icon} ${info.displayName}'),
              selected: info.id == _selectedScenarioId,
              onSelected: (_) => _selectScenario(info.id),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 主体：加载 / 空列表 / 数据列表 三态
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_memories.isEmpty) {
      return _buildEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _loadMemories,
      child: ListView.builder(
        itemCount: _memories.length,
        itemBuilder: (context, index) =>
            _buildMemoryCard(_memories[index]),
      ),
    );
  }

  /// 空状态占位
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined,
              size: 64, color: context.appColors.inkSoft.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            '该场景暂无记忆',
            style: AppTypography.chapterTitle.copyWith(
              fontSize: 16,
              color: context.appColors.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Agent 在对话中通过 patch_memory 工具记录经验，\n'
            '也可点击右上角 + 手动添加。',
            textAlign: TextAlign.center,
            style: AppTypography.metaItalic.copyWith(
              color: context.appColors.inkSoft.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  /// 单条记忆卡片
  Widget _buildMemoryCard(Map<String, dynamic> memory) {
    final content = memory['content'] as String;
    final updatedAt = memory['updated_at'] as int;
    final updatedTime = DateTime.fromMillisecondsSinceEpoch(updatedAt);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        title: Text(
          content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyProse.copyWith(
            fontSize: 14,
            height: 1.6,
            color: context.appColors.ink,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '更新于 ${_formatTime(updatedTime)}',
            style: AppTypography.metaItalic.copyWith(
              color: context.appColors.inkSoft,
            ),
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _editMemory(memory);
                break;
              case 'delete':
                _deleteMemory(memory);
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => _editMemory(memory),
      ),
    );
  }

  /// 时间格式化为 yyyy-MM-dd HH:mm
  String _formatTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// 记忆新增 / 编辑弹窗
///
/// 仅一个多行 TextField，[existingContent] 为 null 表示新增。
class _MemoryEditDialog extends StatefulWidget {
  final String scenarioDisplayName;
  final String? existingContent;

  const _MemoryEditDialog({
    required this.scenarioDisplayName,
    this.existingContent,
  });

  @override
  State<_MemoryEditDialog> createState() => _MemoryEditDialogState();
}

class _MemoryEditDialogState extends State<_MemoryEditDialog> {
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.existingContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ToastUtils.showError('请输入记忆内容', context: context);
      return;
    }
    Navigator.of(context).pop(content);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingContent != null;
    return AlertDialog(
      title: Text(isEditing ? '编辑记忆' : '添加记忆'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '场景：${widget.scenarioDisplayName}',
              style: AppTypography.metaItalic.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 6,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '记忆内容',
                hintText: '输入 Agent 的经验记忆文本',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }
}

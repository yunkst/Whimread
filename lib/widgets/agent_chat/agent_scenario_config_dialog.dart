/// Agent 场景配置对话框
///
/// 用户可选择一个已有的 LLM 配置作为当前场景的 LLM 后端，
/// 也可清空选择以使用全局默认配置。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/services/ai_service_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/llm_config.dart';
import '../../services/novel_agent/agent_scenario_factory.dart';
import 'agent_icons.dart';

class AgentScenarioConfigDialog extends ConsumerStatefulWidget {
  final String scenarioId;

  const AgentScenarioConfigDialog({
    super.key,
    required this.scenarioId,
  });

  @override
  ConsumerState<AgentScenarioConfigDialog> createState() =>
      _AgentScenarioConfigDialogState();
}

class _AgentScenarioConfigDialogState
    extends ConsumerState<AgentScenarioConfigDialog> {
  List<LlmConfig> _configs = [];
  int? _selectedConfigId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final service = ref.read(llmConfigServiceProvider);
    await service.ensureMigratedFromLegacy();
    final configs = await service.getAllConfigs();

    // 获取当前场景激活的配置
    final activeConfig =
        await service.getActiveConfig(scenarioId: widget.scenarioId);
    final activeId = activeConfig?.id;

    if (mounted) {
      setState(() {
        _configs = configs;
        _selectedConfigId = activeId;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取场景信息
    final scenarioInfo = AgentScenarioFactory.availableScenarios
        .where((s) => s.id == widget.scenarioId)
        .firstOrNull;

    return AlertDialog(
      title: Row(
        children: [
          Icon(AgentIcons.quill,
              size: 22, color: context.appColors.chatButtonPrimary),
          const SizedBox(width: 8),
          Text('${scenarioInfo?.displayName ?? widget.scenarioId} 配置'),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()))
          : _configs.isEmpty
              ? const SizedBox(
                  height: 80,
                  child: Center(
                    child: Text('暂无 LLM 配置\n请先在设置中添加配置'),
                  ),
                )
              : SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '选择此场景使用的 LLM 后端：',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _configs.length,
                          itemBuilder: (context, index) {
                            final config = _configs[index];
                            return RadioListTile<int>(
                              dense: true,
                              title: Row(
                                children: [
                                  Expanded(child: Text(config.name)),
                                  if (config.isDefault)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('默认',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          )),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                '${config.apiUrl}${config.model.isNotEmpty ? ' · ${config.model}' : ''}',
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: config.id!,
                              // ignore: deprecated_member_use
                              groupValue: _selectedConfigId,
                              // ignore: deprecated_member_use
                              onChanged: (id) {
                                setState(() => _selectedConfigId = id);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
      actions: [
        if (_selectedConfigId != null)
          TextButton(
            onPressed: () {
              setState(() => _selectedConfigId = null);
            },
            child: const Text('清空覆盖'),
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

  Future<void> _save() async {
    final service = ref.read(llmConfigServiceProvider);
    await service.setActiveConfigForScenario(
        widget.scenarioId, _selectedConfigId);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }
}

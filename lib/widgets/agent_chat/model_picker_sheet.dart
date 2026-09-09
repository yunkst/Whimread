/// Agent Chat 内嵌的 AI 模型选择底部抽屉
///
/// 与设置页 [ManagedModelPickerScreen] 共享同一份目录(provider);
/// 此处仅做「当前对话内快速切换」的轻量入口(底部抽屉,免新建会话)。
///
/// 数据源 [managedModelProvider],与设置页 / buildManagedProvider 同一份;
///  选择写入 [ManagedModelService.setSelectedModelId] → 下次 chat/completions
/// 生效(当前在跑的请求仍用旧模型,符合「作用于后续所有 AI 调用」契约)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/build_config.dart';
import '../../core/providers/managed_model_provider.dart';
import '../../services/managed_models/managed_model_service.dart';
import '../../utils/toast_utils.dart';
import '../common/bottom_sheet_header.dart';
import '../empty_states/empty_state_view.dart';

/// 弹出底部抽屉;非托管包调用此函数会被静默忽略。
Future<void> showAgentModelPickerSheet(BuildContext context) async {
  if (!kHasBundledBackend) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _AgentModelPickerSheet(),
  );
}

class _AgentModelPickerSheet extends ConsumerStatefulWidget {
  const _AgentModelPickerSheet();

  @override
  ConsumerState<_AgentModelPickerSheet> createState() =>
      _AgentModelPickerSheetState();
}

class _AgentModelPickerSheetState
    extends ConsumerState<_AgentModelPickerSheet> {
  @override
  void initState() {
    super.initState();
    // 抽屉打开时强制拉一次目录,避免聊天中目录过时
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(managedModelProvider.notifier).refresh();
    });
  }

  Future<void> _onSelect(ManagedModel model) async {
    final state = ref.read(managedModelProvider);
    if (state.selectedModelId == model.id) {
      Navigator.of(context).pop();
      return;
    }
    await ref.read(managedModelProvider.notifier).select(model.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    ToastUtils.showSuccess('已切换到 ${model.displayName}', context: context);
  }

  Future<void> _onRefresh() async {
    await ref.read(managedModelProvider.notifier).refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(managedModelProvider);
    final accent = theme.colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              BottomSheetHeader(
                icon: Icons.tune,
                title: '切换 AI 模型',
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新目录',
                  onPressed: state.loading ? null : _onRefresh,
                ),
              ),
              Expanded(child: _buildBody(state, accent, scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    ManagedModelState state,
    Color accent,
    ScrollController scrollController,
  ) {
    final theme = Theme.of(context);
    final catalog = state.catalog;

    if (catalog == null) {
      if (state.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return EmptyStateView(
        icon: Icons.cloud_off_outlined,
        title: '暂无可用模型',
        subtitle: '后端目录暂时不可达,请稍后重试',
        actionText: '重试',
        onAction: _onRefresh,
      );
    }

    final selectedId = state.selectedModelId ?? catalog.defaultModel?.id;

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: catalog.models.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
      itemBuilder: (_, i) {
        final m = catalog.models[i];
        final isSelected = m.id == selectedId;
        return _ModelRow(
          model: m,
          rateLabel: catalog.rateLabel(m),
          isSelected: isSelected,
          accent: accent,
          onTap: () => _onSelect(m),
        );
      },
    );
  }
}

class _ModelRow extends StatelessWidget {
  final ManagedModel model;
  final String rateLabel;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  const _ModelRow({
    required this.model,
    required this.rateLabel,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.displayName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? accent
                                : theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (model.isBaseline) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '基准',
                            style: TextStyle(
                              fontSize: 10,
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rateLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_off,
              color: isSelected ? accent : theme.colorScheme.outline,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
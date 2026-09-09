/// Agent Chat 顶栏的「当前模型」紧凑 chip
///
/// 显示规则:
///   - 有目录 + 有选中 → 显示模型 displayName(短)+ 「基准」徽章(若是 baseline)
///   - 有目录 + 无选中 → 显示默认模型(baseline)
///   - 目录未知 + 有选中(selectedId 已持久化) → 显示原始 selectedId + 「未知」徽章,
///     让用户看到实际计费的模型而不只是「模型」占位;resolveForRequest 已确认该选择
///     在请求路径上仍在生效(buildManagedProvider 会信任本地选择)。
///   - 目录未知 + 无选中 → 显示「模型」灰底占位
///   - 非托管包 → 不渲染(返回 SizedBox.shrink())
///
/// 点击 → [showAgentModelPickerSheet] 打开底部抽屉快速切换。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/build_config.dart';
import '../../core/providers/managed_model_provider.dart';
import '../../core/theme/app_colors.dart';
import 'model_picker_sheet.dart';

class ActiveModelChip extends ConsumerWidget {
  const ActiveModelChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 非托管包:客户端 LLM 走用户自配,模型概念不复存在,隐藏
    if (!kHasBundledBackend) return const SizedBox.shrink();

    final state = ref.watch(managedModelProvider);
    final colors = context.appColors;
    final catalog = state.catalog;
    final selectedId = state.selectedModelId;
    final selected = (selectedId != null && catalog != null)
        ? catalog.byId(selectedId)
        : (catalog?.defaultModel);
    // 目录拉取失败但用户已有持久化选择 → 显示原始 id 让 UI 与实际请求模型对齐,
    // 而不是退化为「模型」占位(占位会让人误以为 baseline 1× 计费)。
    final showUnknownBadge = catalog == null && selectedId != null;

    final label = selected?.shortLabel ?? selectedId ?? '模型';
    final isBaseline = selected?.isBaseline ?? false;
    final badgeColor =
        isBaseline ? colors.chatButtonPrimary : colors.inkSoft;

    return InkWell(
      onTap: () => showAgentModelPickerSheet(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 12, color: colors.chatButtonPrimary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colors.chatButtonPrimary,
                fontWeight: isBaseline ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (isBaseline || showUnknownBadge) ...[
              const SizedBox(width: 4),
              _Badge(label: isBaseline ? '基准' : '未知', color: badgeColor),
            ],
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 12, color: colors.chatButtonPrimary),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}
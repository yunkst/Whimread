/// Agent Chat 顶栏的「当前模型」紧凑 chip
///
/// 显示规则:
///   - 有目录 + 有选中 → 显示模型 displayName(短)+ 「基准」徽章(若是 baseline)
///   - 目录未知 / 正在拉取 → 显示「模型 …」灰底占位,点击同样可打开抽屉强制刷新
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

    final label = selected?.shortLabel ?? '模型';
    final isBaseline = selected?.isBaseline ?? false;

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
            if (isBaseline) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                decoration: BoxDecoration(
                  color: colors.chatButtonPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '基准',
                  style: TextStyle(
                    fontSize: 9,
                    color: colors.chatButtonPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 12, color: colors.chatButtonPrimary),
          ],
        ),
      ),
    );
  }
}
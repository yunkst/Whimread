/// 窄屏用：可横滑的分类 Tab 栏
///
/// 从 `prompt_tag_management_screen.dart` 拆分。接收分类列表与选中状态，
/// 通过 [onSelect] 回调通知上层切换分类；通过 [onAddCategory] 回调通知上层新增。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/prompt_tag_category.dart';

class CategoryTabs extends StatelessWidget {
  final List<PromptTagCategory> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelect;
  final VoidCallback onAddCategory;

  const CategoryTabs({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelect,
    required this.onAddCategory,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              '暂无分类',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft,
              ),
            ),
            const SizedBox(width: 12),
            IconButton.outlined(
              onPressed: onAddCategory,
              icon: const Icon(Icons.add, size: 18),
              tooltip: '添加分类',
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ...categories.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat.name),
                  selected: cat.id == selectedCategoryId,
                  onSelected: (_) => onSelect(cat.id),
                ),
              )),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onAddCategory,
            icon: const Icon(Icons.add, size: 20),
            tooltip: '添加分类',
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

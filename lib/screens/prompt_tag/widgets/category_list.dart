/// 宽屏用：左侧分类列表
///
/// 从 `prompt_tag_management_screen.dart` 拆出 [CategoryList] 与
/// [CategoryPopupMenu]。行为完全一致：点击行切换分类、PopupMenu 编辑/删除。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/prompt_tag_category.dart';

class CategoryList extends StatelessWidget {
  final List<PromptTagCategory> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelect;
  final VoidCallback onAddCategory;
  final void Function(PromptTagCategory category, String action) onMenuAction;

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelect,
    required this.onAddCategory,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 标题 + 添加按钮
        ListTile(
          dense: true,
          title: Text('分类',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft,
              )),
          trailing: IconButton(
            onPressed: onAddCategory,
            icon: const Icon(Icons.add, size: 18),
            tooltip: '添加分类',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: categories.isEmpty
              ? Center(
                  child: Text(
                    '暂无分类',
                    style: AppTypography.metaItalic.copyWith(
                      color: context.appColors.inkSoft,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = cat.id == selectedCategoryId;
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      leading: Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(cat.name),
                      trailing: CategoryPopupMenu(
                        category: cat,
                        onAction: (action) => onMenuAction(cat, action),
                      ),
                      onTap: () => onSelect(cat.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 分类行 PopupMenu（编辑 / 删除）
class CategoryPopupMenu extends StatelessWidget {
  final PromptTagCategory category;
  final ValueChanged<String> onAction;

  const CategoryPopupMenu({
    super.key,
    required this.category,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: onAction,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('编辑')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
  }
}

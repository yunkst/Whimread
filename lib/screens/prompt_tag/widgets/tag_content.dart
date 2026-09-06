/// Tag 内容区
///
/// 从 `prompt_tag_management_screen.dart` 拆出。负责三种状态展示：
/// - 未选中分类：提示「请选择左侧分类」
/// - 加载中：菊花
/// - 列表为空：提示「该分类下暂无标签」
/// - 正常：TagGroup 列表（每个 group 走 [TagGroupItem]）
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/prompt_tag.dart';
import '../../../models/tag_group.dart';
import 'tag_group_item.dart';

class TagContent extends StatelessWidget {
  final int? selectedCategoryId;
  final bool isLoadingTags;
  final List<TagGroup> tagGroups;
  final Set<String> expandedGroupNames;
  final Map<String, List<PromptTag>> expandedTags;
  final void Function(TagGroup group) onToggleExpand;
  final void Function(TagGroup group) onAddSameName;
  final void Function(TagGroup group) onDeleteAll;
  final Future<void> Function(TagGroup group) onEditSingleTag;
  final void Function(PromptTag tag) onEditTag;
  final void Function(PromptTag tag) onDeleteTag;

  const TagContent({
    super.key,
    required this.selectedCategoryId,
    required this.isLoadingTags,
    required this.tagGroups,
    required this.expandedGroupNames,
    required this.expandedTags,
    required this.onToggleExpand,
    required this.onAddSameName,
    required this.onDeleteAll,
    required this.onEditSingleTag,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCategoryId == null) {
      return _CenterHint(
        icon: Icons.label_outline,
        text: '请选择左侧分类',
      );
    }

    if (isLoadingTags) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tagGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.label_off_outlined,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              '该分类下暂无标签',
              style: AppTypography.bodyProse.copyWith(
                fontSize: 15,
                color: context.appColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角 + 添加标签',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: tagGroups.length,
      itemBuilder: (context, index) {
        final group = tagGroups[index];
        return TagGroupItem(
          group: group,
          isExpanded: expandedGroupNames.contains(group.name),
          expandedTags: expandedTags[group.name] ?? const [],
          onToggleExpand: () => onToggleExpand(group),
          onAddSameName: () => onAddSameName(group),
          onDeleteAll: () => onDeleteAll(group),
          onEditSingleTag: () => onEditSingleTag(group),
          onEditTag: onEditTag,
          onDeleteTag: onDeleteTag,
        );
      },
    );
  }
}

class _CenterHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CenterHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            text,
            style: AppTypography.bodyProse.copyWith(
              fontSize: 15,
              color: context.appColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

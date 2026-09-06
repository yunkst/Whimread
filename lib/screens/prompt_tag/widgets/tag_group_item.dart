/// TagGroup 列表项（含展开后的子 tag）
///
/// 从 `prompt_tag_management_screen.dart` 拆出 [TagGroupItem] 与
/// [ExpandedTagItem]。行为完全一致：点 group 头切换展开、PopupMenu 添加同名/
/// 删除全部、只有 1 条 tag 的 group 点击直接编辑单条 tag。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/prompt_tag.dart';
import '../../../models/tag_group.dart';

class TagGroupItem extends StatelessWidget {
  final TagGroup group;
  final VoidCallback onToggleExpand;
  final VoidCallback onAddSameName;
  final VoidCallback onDeleteAll;
  final Future<void> Function() onEditSingleTag;
  final void Function(PromptTag tag) onEditTag;
  final void Function(PromptTag tag) onDeleteTag;

  /// 展开状态下该 group 加载到的同名 tags
  final List<PromptTag> expandedTags;

  /// 该 group 当前是否展开
  final bool isExpanded;

  const TagGroupItem({
    super.key,
    required this.group,
    required this.isExpanded,
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
    return Column(
      children: [
        // Group 头部（可点击展开/收起）
        ListTile(
          leading: Icon(
            isExpanded ? Icons.label : Icons.label_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(group.name),
          subtitle: group.count > 1
              ? Text('${group.count} 条 prompt')
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (group.count > 1)
                IconButton(
                  icon: Icon(isExpanded
                      ? Icons.expand_less
                      : Icons.expand_more),
                  onPressed: onToggleExpand,
                  tooltip: isExpanded ? '收起' : '展开',
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (value) {
                  switch (value) {
                    case 'add_same_name':
                      onAddSameName();
                      break;
                    case 'delete_all':
                      onDeleteAll();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'add_same_name',
                      child: Text('添加同名标签')),
                  if (group.count > 1)
                    const PopupMenuItem(
                        value: 'delete_all',
                        child: Text('删除全部同名标签')),
                ],
              ),
            ],
          ),
          onTap: group.count > 1
              ? onToggleExpand
              : () => onEditSingleTag(),
        ),
        // 展开的 tag 列表
        if (isExpanded && expandedTags.isNotEmpty)
          ...expandedTags.map(
            (tag) => ExpandedTagItem(
              tag: tag,
              onEdit: () => onEditTag(tag),
              onDelete: () => onDeleteTag(tag),
            ),
          ),
      ],
    );
  }
}

/// 展开的单条 tag（缩进展示）
class ExpandedTagItem extends StatelessWidget {
  final PromptTag tag;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ExpandedTagItem({
    super.key,
    required this.tag,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.short_text, size: 16),
        title: Text(
          tag.promptText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyProse.copyWith(
            fontSize: 13,
            height: 1.5,
            color: context.appColors.ink,
          ),
        ),
        subtitle: tag.reason.isNotEmpty
            ? Text(
                tag.reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.metaItalic.copyWith(
                  fontSize: 11,
                  color: context.appColors.inkSoft,
                ),
              )
            : null,
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 16),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

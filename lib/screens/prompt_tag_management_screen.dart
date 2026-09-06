/// 提示词标签管理页
///
/// 职责：
/// - 分类（PromptTagCategory）的增删改
/// - 标签（PromptTag）的增删改、移动分类
/// - 同名标签按 TagGroup 聚合展示，点击展开查看各 prompt
/// - 宽屏双栏 / 窄屏上下自适应布局
///
/// 架构（2026-07-09 重构）：
/// - 业务状态与数据 CRUD：[PromptTagManagementNotifier]
/// - 分类列表 / Tab / Tag 内容区 / Tag 分组项：`widgets/`
/// - 分类 / 标签编辑对话框：`dialogs/`
/// - 本 Screen 仅作为编排层：watch 状态 → 渲染子组件；触发交互 → 回传 Notifier
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/prompt_tag_management_notifier.dart';
import '../../core/theme/app_typography.dart';
import '../../models/prompt_tag.dart';
import '../../models/prompt_tag_category.dart';
import '../../models/tag_group.dart';
import '../../utils/toast_utils.dart';
import '../../widgets/common/common_widgets.dart';
import 'prompt_tag/dialogs/category_edit_dialog.dart';
import 'prompt_tag/dialogs/tag_edit_dialog.dart';
import 'prompt_tag/widgets/category_list.dart';
import 'prompt_tag/widgets/category_tabs.dart';
import 'prompt_tag/widgets/tag_content.dart';

class PromptTagManagementScreen extends ConsumerWidget {
  const PromptTagManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(promptTagManagementNotifierProvider);
    final notifier = ref.read(promptTagManagementNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '提示词标签管理',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: () => _addTag(context, state, notifier),
            icon: const Icon(Icons.add),
            tooltip: '添加标签',
          ),
        ],
      ),
      body: state.isLoadingCategories
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                // 宽屏 ≥ 600 走双栏，窄屏走上下布局
                if (constraints.maxWidth >= 600) {
                  return _buildWideLayout(context, state, notifier);
                }
                return _buildNarrowLayout(context, state, notifier);
              },
            ),
    );
  }

  // ==================== 布局 ====================

  /// 窄屏布局：顶部 Tab 切分类 + 下方 tag 列表
  Widget _buildNarrowLayout(
    BuildContext context,
    PromptTagManagementState state,
    PromptTagManagementNotifier notifier,
  ) {
    return Column(
      children: [
        CategoryTabs(
          categories: state.categories,
          selectedCategoryId: state.selectedCategoryId,
          onSelect: notifier.selectCategory,
          onAddCategory: () => _addCategory(context, notifier),
        ),
        const Divider(height: 1),
        Expanded(
          child: _buildTagContent(context, state, notifier),
        ),
      ],
    );
  }

  /// 宽屏布局：左侧分类列表 + 右侧 tag 列表
  Widget _buildWideLayout(
    BuildContext context,
    PromptTagManagementState state,
    PromptTagManagementNotifier notifier,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧分类列表（固定宽度）
        SizedBox(
          width: 200,
          child: CategoryList(
            categories: state.categories,
            selectedCategoryId: state.selectedCategoryId,
            onSelect: notifier.selectCategory,
            onAddCategory: () => _addCategory(context, notifier),
            onMenuAction: (category, action) => _onCategoryMenuAction(
              context,
              notifier,
              category,
              action,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildTagContent(context, state, notifier)),
      ],
    );
  }

  Widget _buildTagContent(
    BuildContext context,
    PromptTagManagementState state,
    PromptTagManagementNotifier notifier,
  ) {
    return TagContent(
      selectedCategoryId: state.selectedCategoryId,
      isLoadingTags: state.isLoadingTags,
      tagGroups: state.tagGroups,
      expandedGroupNames: state.expandedGroupNames,
      expandedTags: state.expandedTags,
      onToggleExpand: notifier.toggleGroupExpand,
      onAddSameName: (group) =>
          _addTagWithName(context, state, notifier, group.categoryId, group.name),
      onDeleteAll: (group) => _deleteAllInGroup(context, notifier, group),
      onEditSingleTag: (group) => _editSingleTag(context, state, notifier, group),
      onEditTag: (tag) => _editTag(context, state, notifier, tag),
      onDeleteTag: (tag) => _deleteTag(context, notifier, tag),
    );
  }

  // ==================== 分类 CRUD ====================

  void _onCategoryMenuAction(
    BuildContext context,
    PromptTagManagementNotifier notifier,
    PromptTagCategory category,
    String action,
  ) {
    switch (action) {
      case 'edit':
        _editCategory(context, notifier, category);
        break;
      case 'delete':
        _deleteCategory(context, notifier, category);
        break;
    }
  }

  Future<void> _addCategory(
    BuildContext context,
    PromptTagManagementNotifier notifier,
  ) async {
    final result = await showDialog<PromptTagCategory>(
      context: context,
      builder: (context) => const CategoryEditDialog(),
    );
    if (result == null) return;
    await notifier.saveCategory(result);
    if (context.mounted) {
      ToastUtils.showSuccess('分类已添加');
    }
  }

  Future<void> _editCategory(
    BuildContext context,
    PromptTagManagementNotifier notifier,
    PromptTagCategory category,
  ) async {
    final result = await showDialog<PromptTagCategory>(
      context: context,
      builder: (context) => CategoryEditDialog(category: category),
    );
    if (result == null) return;
    await notifier.saveCategory(result);
    if (context.mounted) {
      ToastUtils.showSuccess('分类已更新');
    }
  }

  Future<void> _deleteCategory(
    BuildContext context,
    PromptTagManagementNotifier notifier,
    PromptTagCategory category,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '确认删除',
      message: '删除分类「${category.name}」将同时删除该分类下所有标签，确定吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (confirmed != true) return;
    await notifier.deleteCategory(category);
    if (context.mounted) {
      ToastUtils.showSuccess('分类已删除');
    }
  }

  // ==================== Tag CRUD ====================

  Future<void> _addTag(
    BuildContext context,
    PromptTagManagementState state,
    PromptTagManagementNotifier notifier,
  ) async {
    if (state.selectedCategoryId == null) {
      ToastUtils.showInfo('请先选择分类');
      return;
    }
    final category =
        state.categories.firstWhere((c) => c.id == state.selectedCategoryId);
    final result = await showDialog<PromptTag>(
      context: context,
      builder: (context) => TagEditDialog(
        categoryId: state.selectedCategoryId!,
        categoryName: category.name,
        categories: state.categories,
      ),
    );
    if (result == null) return;
    await notifier.saveTag(result, autoExpand: true);
    if (context.mounted) {
      ToastUtils.showSuccess('标签已添加');
    }
  }

  Future<void> _addTagWithName(
    BuildContext context,
    PromptTagManagementState state,
    PromptTagManagementNotifier notifier,
    int categoryId,
    String name,
  ) async {
    final category = state.categories.firstWhere((c) => c.id == categoryId);
    final result = await showDialog<PromptTag>(
      context: context,
      builder: (context) => TagEditDialog(
        categoryId: categoryId,
        categoryName: category.name,
        categories: state.categories,
        presetName: name,
      ),
    );
    if (result == null) return;
    await notifier.saveTag(result, autoExpand: true);
    if (context.mounted) {
      ToastUtils.showSuccess('标签已添加');
    }
  }

  Future<void> _editTag(
    BuildContext context,
    PromptTagManagementState state,
    PromptTagManagementNotifier notifier,
    PromptTag tag,
  ) async {
    final category =
        state.categories.firstWhere((c) => c.id == tag.categoryId);
    final result = await showDialog<PromptTag>(
      context: context,
      builder: (context) => TagEditDialog(
        tag: tag,
        categoryId: tag.categoryId,
        categoryName: category.name,
        categories: state.categories,
        onDeleteRequested: () {
          // 编辑对话框点「删除」→ 直接 pop 出去，外层再走标准删除流程
          // （二次确认 + notifier.deleteTag + Toast）以保证 UX 一致。
          Navigator.of(context).pop();
          _deleteTag(context, notifier, tag);
        },
      ),
    );
    if (result == null) return;
    await notifier.saveTag(result, originalCategoryId: tag.categoryId);
    if (context.mounted) {
      ToastUtils.showSuccess('标签已更新');
    }
  }

  Future<void> _editSingleTag(
    BuildContext context,
    PromptTagManagementState state,
    PromptTagManagementNotifier notifier,
    TagGroup group,
  ) async {
    final tag = await notifier.getSingleTagInGroup(group);
    if (!context.mounted) return;
    _editTag(context, state, notifier, tag);
  }

  Future<void> _deleteTag(
    BuildContext context,
    PromptTagManagementNotifier notifier,
    PromptTag tag,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '确认删除',
      message: '确定要删除标签「${tag.name}」吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (confirmed != true || tag.id == null) return;
    await notifier.deleteTag(tag);
    if (context.mounted) {
      ToastUtils.showSuccess('标签已删除');
    }
  }

  Future<void> _deleteAllInGroup(
    BuildContext context,
    PromptTagManagementNotifier notifier,
    TagGroup group,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '确认删除',
      message: '确定要删除所有名为「${group.name}」的标签（${group.count} 条）吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (confirmed != true) return;
    await notifier.deleteAllInGroup(group);
    if (context.mounted) {
      ToastUtils.showSuccess('已删除全部同名标签');
    }
  }
}

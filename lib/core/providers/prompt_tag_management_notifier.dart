/// 提示词标签管理状态管理
///
/// 将 [PromptTagManagementScreen] 原本散落在 State 中的 7 个状态字段与
/// 13 个业务方法收敛到此 Notifier。UI 层（Screen / Widget）只负责：
/// - watch 状态并渲染
/// - 触发需要 BuildContext 的交互（showDialog / ConfirmDialog / Toast）
///   并把交互结果回传给 Notifier 的纯数据方法
///
/// 数据层依赖：
/// - [promptTagCategoryRepositoryProvider] → 分类 CRUD
/// - [promptTagRepositoryProvider] → 标签 CRUD
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/prompt_tag.dart';
import '../../models/prompt_tag_category.dart';
import '../../models/tag_group.dart';
import 'database_providers.dart';

/// 提示词标签管理聚合状态
class PromptTagManagementState {
  /// 全部分类
  final List<PromptTagCategory> categories;

  /// 当前选中分类 id
  final int? selectedCategoryId;

  /// 当前分类下按名聚合的标签分组
  final List<TagGroup> tagGroups;

  /// 展开的 TagGroup name 集合
  final Set<String> expandedGroupNames;

  /// 展开后加载的 PromptTag 列表（按 groupName 索引）
  final Map<String, List<PromptTag>> expandedTags;

  /// 是否正在加载分类（首次进入）
  final bool isLoadingCategories;

  /// 是否正在加载标签
  final bool isLoadingTags;

  const PromptTagManagementState({
    this.categories = const [],
    this.selectedCategoryId,
    this.tagGroups = const [],
    this.expandedGroupNames = const {},
    this.expandedTags = const {},
    this.isLoadingCategories = true,
    this.isLoadingTags = false,
  });

  PromptTagManagementState copyWith({
    List<PromptTagCategory>? categories,
    int? selectedCategoryId,
    bool clearSelectedCategoryId = false,
    List<TagGroup>? tagGroups,
    Set<String>? expandedGroupNames,
    Map<String, List<PromptTag>>? expandedTags,
    bool? isLoadingCategories,
    bool? isLoadingTags,
  }) {
    return PromptTagManagementState(
      categories: categories ?? this.categories,
      selectedCategoryId: clearSelectedCategoryId
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
      tagGroups: tagGroups ?? this.tagGroups,
      expandedGroupNames: expandedGroupNames ?? this.expandedGroupNames,
      expandedTags: expandedTags ?? this.expandedTags,
      isLoadingCategories: isLoadingCategories ?? this.isLoadingCategories,
      isLoadingTags: isLoadingTags ?? this.isLoadingTags,
    );
  }
}

/// 提示词标签管理状态管理器
///
/// 封装分类/标签的加载、切换、CRUD 等纯数据操作。
/// 不持有 BuildContext，因此所有需要 UI 交互（对话框、确认框、Toast）
/// 的入口由 Screen/Widget 层调用，并将结果回传。
class PromptTagManagementNotifier
    extends StateNotifier<PromptTagManagementState> {
  PromptTagManagementNotifier(this._ref)
      : super(const PromptTagManagementState()) {
    _loadCategories();
  }

  final Ref _ref;

  // ==================== 数据加载 ====================

  /// 加载全部分类（首次进入自动初始化默认分类，并自动选中第一个）
  Future<void> _loadCategories() async {
    final repo = _ref.read(promptTagCategoryRepositoryProvider);
    await repo.initDefaultCategories();
    final categories = await repo.getAll();
    int? selected = state.selectedCategoryId;
    if (selected == null && categories.isNotEmpty) {
      selected = categories.first.id;
    }
    state = state.copyWith(
      categories: categories,
      isLoadingCategories: false,
      selectedCategoryId: selected,
    );
    if (selected != null) {
      await _loadTagGroups(selected);
    }
  }

  /// 重新加载分类（CRUD 后调用）
  Future<void> reloadCategories() => _loadCategories();

  /// 加载指定分类下按名聚合的标签分组
  Future<void> _loadTagGroups(int categoryId) async {
    state = state.copyWith(isLoadingTags: true);
    final repo = _ref.read(promptTagRepositoryProvider);
    final groups = await repo.getGroupedByCategory(categoryId);
    // 清理不存在的展开状态
    final expandedNames = state.expandedGroupNames
        .where((name) => groups.any((g) => g.name == name))
        .toSet();
    final expandedTags = Map<String, List<PromptTag>>.from(state.expandedTags)
      ..removeWhere((key, _) => !groups.any((g) => g.name == key));
    state = state.copyWith(
      tagGroups: groups,
      isLoadingTags: false,
      expandedGroupNames: expandedNames,
      expandedTags: expandedTags,
    );
  }

  /// 切换当前选中分类
  Future<void> selectCategory(int? categoryId) async {
    if (categoryId == state.selectedCategoryId) return;
    state = state.copyWith(
      selectedCategoryId: categoryId,
      expandedGroupNames: const {},
      expandedTags: const {},
    );
    if (categoryId != null) {
      await _loadTagGroups(categoryId);
    }
  }

  /// 切换某 TagGroup 的展开状态（需要时懒加载该 group 下同名标签）
  Future<void> toggleGroupExpand(TagGroup group) async {
    final expandedNames = Set<String>.from(state.expandedGroupNames);
    if (expandedNames.contains(group.name)) {
      expandedNames.remove(group.name);
      state = state.copyWith(expandedGroupNames: expandedNames);
      return;
    }
    expandedNames.add(group.name);
    state = state.copyWith(expandedGroupNames: expandedNames);
    if (!state.expandedTags.containsKey(group.name)) {
      final repo = _ref.read(promptTagRepositoryProvider);
      final tags = await repo.getByCategory(group.categoryId);
      final sameNameTags = tags.where((t) => t.name == group.name).toList();
      final expandedTags = Map<String, List<PromptTag>>.from(state.expandedTags)
        ..[group.name] = sameNameTags;
      state = state.copyWith(expandedTags: expandedTags);
    }
  }

  /// 取单条 tag 所属 group 的首条同名 tag（点击单条 group 直接编辑用）
  Future<PromptTag> getSingleTagInGroup(TagGroup group) async {
    final repo = _ref.read(promptTagRepositoryProvider);
    final tags = await repo.getByCategory(group.categoryId);
    return tags.firstWhere((t) => t.name == group.name);
  }

  // ==================== 分类 CRUD ====================

  /// 保存（新增/编辑）分类，返回后由 UI 调用
  Future<void> saveCategory(PromptTagCategory category) async {
    final repo = _ref.read(promptTagCategoryRepositoryProvider);
    await repo.save(category);
    await _loadCategories();
  }

  /// 删除分类（同时删除其下所有标签）
  Future<void> deleteCategory(PromptTagCategory category) async {
    if (category.id == null) return;
    final tagRepo = _ref.read(promptTagRepositoryProvider);
    final catRepo = _ref.read(promptTagCategoryRepositoryProvider);
    await tagRepo.deleteByCategory(category.id!);
    await catRepo.delete(category.id!);
    if (state.selectedCategoryId == category.id) {
      state = state.copyWith(clearSelectedCategoryId: true);
    }
    await _loadCategories();
  }

  // ==================== Tag CRUD ====================

  /// 保存（新增/编辑）标签
  ///
  /// 若 [tag] 的 categoryId 与原 [originalCategoryId] 不同，则同时移动分类。
  /// 新增场景下 [originalCategoryId] 传 null，且会自动展开该 tag 所在 group。
  Future<void> saveTag(
    PromptTag tag, {
    int? originalCategoryId,
    bool autoExpand = false,
  }) async {
    final repo = _ref.read(promptTagRepositoryProvider);
    if (originalCategoryId != null && tag.categoryId != originalCategoryId) {
      await repo.save(tag);
      await repo.moveToCategory(tag.id!, tag.categoryId);
    } else {
      await repo.save(tag);
    }
    if (autoExpand) {
      final expandedNames = Set<String>.from(state.expandedGroupNames)
        ..add(tag.name);
      state = state.copyWith(expandedGroupNames: expandedNames);
    }
    final target = state.selectedCategoryId;
    if (target != null) {
      await _loadTagGroups(target);
    }
  }

  /// 删除单条标签
  Future<void> deleteTag(PromptTag tag) async {
    if (tag.id == null) return;
    final repo = _ref.read(promptTagRepositoryProvider);
    await repo.delete(tag.id!);
    final target = state.selectedCategoryId;
    if (target != null) {
      await _loadTagGroups(target);
    }
  }

  /// 删除同名 group 下所有 tag
  Future<void> deleteAllInGroup(TagGroup group) async {
    final repo = _ref.read(promptTagRepositoryProvider);
    final tags = await repo.getByCategory(group.categoryId);
    for (final tag in tags.where((t) => t.name == group.name)) {
      if (tag.id != null) {
        await repo.delete(tag.id!);
      }
    }
    final expandedNames = Set<String>.from(state.expandedGroupNames)
      ..remove(group.name);
    final expandedTags = Map<String, List<PromptTag>>.from(state.expandedTags)
      ..remove(group.name);
    state = state.copyWith(
      expandedGroupNames: expandedNames,
      expandedTags: expandedTags,
    );
    final target = state.selectedCategoryId;
    if (target != null) {
      await _loadTagGroups(target);
    }
  }
}

/// 提示词标签管理状态 Provider
final promptTagManagementNotifierProvider =
    StateNotifierProvider<PromptTagManagementNotifier, PromptTagManagementState>(
        (ref) {
  return PromptTagManagementNotifier(ref);
});

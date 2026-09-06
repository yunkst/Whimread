import 'tag_group.dart';

/// 历史提示词关联的标签组快照
///
/// 用于从历史记录恢复标签选择状态。仅保存 categoryId + name，
/// 不保存 tagId — 因为 PromptTagService 每次随机取一条同名 prompt，
/// 恢复时不追求"完全复现当时的那条 prompt"，而是保留当时的标签组选择。
class SavedTagGroup {
  final int categoryId;
  final String name;

  const SavedTagGroup({
    required this.categoryId,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'name': name,
      };

  factory SavedTagGroup.fromJson(Map<String, dynamic> json) => SavedTagGroup(
        categoryId: json['categoryId'] as int,
        name: json['name'] as String,
      );

  /// 转换为 TagGroup（用于 PromptTagSelectorSheet 初始化）
  TagGroup toTagGroup() => TagGroup(
        categoryId: categoryId,
        name: name,
        count: 1,
        representativeId: 0,
      );
}

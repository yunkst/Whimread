/// 标签分组模型（用于选择器 UI 聚合展示同名标签）
class TagGroup {
  /// 标签名称（同分类下可能重复）
  final String name;

  /// 同名标签数量
  final int count;

  /// 代表 id（用于选择器选中状态追踪，取组内第一条的 id）
  final int representativeId;

  /// 所属分类 id
  final int categoryId;

  const TagGroup({
    required this.name,
    required this.count,
    required this.representativeId,
    required this.categoryId,
  });
}

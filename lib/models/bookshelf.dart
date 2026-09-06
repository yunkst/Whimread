/// 书架模型（分类功能）
///
/// 重要：不要与数据库表混淆！
///
/// 正确的理解：
/// - Bookshelf 类（本类）：表示书架分类，如"我的收藏"、"玄幻小说"
/// - bookshelf 表：数据库物理表，存储的是小说数据（历史遗留命名）
/// - novels 视图：bookshelf表的别名视图，提供更清晰的语义
/// - bookshelves 表：数据库表，存储书架分类（复数形式）
///
/// 命名对照：
/// Bookshelf 模型 = 书架分类功能（id, name, icon, color）
/// bookshelf 表 = 存储小说元数据（命名不当）
/// novels 视图 = bookshelf表的别名（语义清晰）
/// bookshelves 表 = 存储书架分类（正确命名）
/// novel_bookshelves 表 = 小说与书架的多对多关系
///
/// 推荐用法：
/// getNovels() - 获取所有小说（语义清晰）
/// getBookshelf() - 获取所有小说（命名有误导性）
///
class Bookshelf {
  /// 书架唯一ID
  final int id;

  /// 书架名称
  final String name;

  /// 创建时间（Unix时间戳）
  final int createdAt;

  /// 排序字段，用于自定义书架显示顺序
  final int sortOrder;

  /// 书架图标（可选）
  final String? icon;

  /// 书架颜色（可选，ARGB格式整数）
  final int? color;

  /// 是否为系统书架
  ///
  /// 系统书架包括：
  /// - ID=1: "全部小说" - 显示所有小说，不可删除
  /// - ID=2: "我的收藏" - 默认收藏书架，不可删除
  ///
  /// 用户创建的书架：isSystem=false，可以编辑和删除
  final bool isSystem;

  const Bookshelf({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortOrder = 0,
    this.icon,
    this.color,
    this.isSystem = false,
  });

  /// 从JSON创建Bookshelf实例
  factory Bookshelf.fromJson(Map<String, dynamic> json) {
    return Bookshelf(
      id: json['id'] as int,
      name: json['name'] as String,
      createdAt: json['created_at'] as int,
      sortOrder: json['sort_order'] as int? ?? 0,
      icon: json['icon'] as String?,
      color: json['color'] as int?,
      isSystem: (json['is_system'] as int? ?? 0) == 1,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt,
      'sort_order': sortOrder,
      'icon': icon,
      'color': color,
      'is_system': isSystem ? 1 : 0,
    };
  }

  /// 创建副本，可选择性地修改某些字段
  Bookshelf copyWith({
    int? id,
    String? name,
    int? createdAt,
    int? sortOrder,
    String? icon,
    int? color,
    bool? isSystem,
  }) {
    return Bookshelf(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isSystem: isSystem ?? this.isSystem,
    );
  }

  @override
  String toString() {
    return 'Bookshelf(id: $id, name: $name, isSystem: $isSystem)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Bookshelf &&
        other.id == id &&
        other.name == name &&
        other.isSystem == isSystem;
  }

  @override
  int get hashCode => id.hashCode;
}

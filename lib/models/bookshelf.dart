/// 书架分类（按"小说来源"派生）
///
/// ## 设计变更
///
/// 旧设计：用户在 UI 中增删改书架（`bookshelves` + `novel_bookshelves` 多对多）。
/// 新设计：书架仅由"小说来源"派生，三档系统固定——
///
/// - [BookshelfKind.all]：全部小说（不过滤 URL）。
/// - [BookshelfKind.original]：原创（`custom://` 前缀，AI Agent/手动创建）。
/// - [BookshelfKind.online]：联网（其它 URL，浏览器/书源抓取加入）。
///
/// 用户不再调整书架分类；不再支持新建/重命名/删除书架，
/// 也不再支持把小说从 A 书架"移动"到 B 书架（分类由 URL 决定，无法手动改）。
///
/// ## 数据表
///
/// 旧的 `bookshelves` / `novel_bookshelves` 数据表保留在 schema 中以避免破坏性
/// migration（其内残留数据无副作用，运行时不再读写）。如未来确认无用户依赖，
/// 可在下个 schema 大版本里 DROP。
class Bookshelf {
  /// 书架唯一 ID（内存枚举值，不对应数据库主键）。
  ///
  /// 用稳定的小整数以兼容旧 `currentBookshelfIdProvider` 的 SharedPreferences
  /// 持久化键 `current_bookshelf_id`——升级时若读到旧值（1/2/任意），
  /// 走 [BookshelfKind.fromLegacyId] 兜底映射到新三档。
  final BookshelfKind kind;

  /// 书架显示名
  final String name;

  const Bookshelf({
    required this.kind,
    required this.name,
  });

  /// 三个系统书架的固定列表（顺序即 Tab 顺序）。
  static const List<Bookshelf> systemShelves = [
    Bookshelf(kind: BookshelfKind.all, name: '全部'),
    Bookshelf(kind: BookshelfKind.original, name: '原创'),
    Bookshelf(kind: BookshelfKind.online, name: '联网'),
  ];

  /// 通过 [BookshelfKind] 查找对应书架，找不到时回退到"全部"。
  static Bookshelf byKind(BookshelfKind kind) {
    for (final b in systemShelves) {
      if (b.kind == kind) return b;
    }
    return systemShelves.first;
  }

  /// 通过旧 [Bookshelf.id]（数据库主键）反查书架。
  ///
  /// 用于兼容 SharedPreferences 中持久化的旧 `current_bookshelf_id`：
  /// - 1 -> 全部（旧"全部小说"虚拟书架）
  /// - 2 -> 我的收藏（旧默认书架）—— 旧数据集中放非原创书，回退到"全部"
  /// - 其它（用户自定义）-> 全部（自定义书架已下线，无法精确还原）
  static Bookshelf fromLegacyId(int legacyId) {
    switch (legacyId) {
      case 1:
        return systemShelves[0]; // 全部
      case 2:
        return systemShelves[0]; // 我的收藏 -> 全部（最安全的兜底）
      default:
        return systemShelves[0];
    }
  }

  Bookshelf copyWith({BookshelfKind? kind, String? name}) {
    return Bookshelf(
      kind: kind ?? this.kind,
      name: name ?? this.name,
    );
  }

  @override
  String toString() => 'Bookshelf(kind: $kind, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Bookshelf && other.kind == kind;
  }

  @override
  int get hashCode => kind.hashCode;
}

/// 书架分类（按来源派生）
enum BookshelfKind {
  /// 全部小说（不过滤 URL）
  all,

  /// 原创（`custom://` 前缀，由 Agent 工具或独立入口创建的小说）
  original,

  /// 联网（其它 URL，浏览器加入或书源抓取）
  online,
}

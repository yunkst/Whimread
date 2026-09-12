/// 书架分类（按"小说来源"派生）
///
/// ## 设计变更
///
/// 旧设计：用户在 UI 中增删改书架（`bookshelves` + `novel_bookshelves` 多对多）。
/// 新设计：书架仅由"小说来源"派生——
///
/// - [BookshelfKind.all]：全部小说（不过滤 URL）。
/// - [BookshelfKind.original]：原创（`custom://` 前缀，AI Agent/手动创建）。
/// - [BookshelfKind.online]：联网，**按来源网站（URL host）再拆分**，
///   每个有藏书的站点一个书架（[Bookshelf.domain] 持有站点 host）。
///
/// UI Tab 列表由 [Bookshelf.tabShelves] 动态生成（全部/原创固定 + 各来源站点），
/// 用户不可手动调整分类，也不能把小说从 A 书架"移动"到 B 书架
/// （分类由 URL 决定，无法手动改）。
///
/// ## 数据表
///
/// 旧的 `bookshelves` / `novel_bookshelves` 数据表保留在 schema 中以避免破坏性
/// migration（其内残留数据无副作用，运行时不再读写）。如未来确认无用户依赖，
/// 可在下个 schema 大版本里 DROP。
class Bookshelf {
  /// 书架分类（内存枚举值，不对应数据库主键）。
  ///
  /// 用稳定的小整数以兼容旧 `currentBookshelfIdProvider` 的 SharedPreferences
  /// 持久化键 `current_bookshelf_id`——升级时若读到旧值（1/2/任意），
  /// 走 [Bookshelf.fromLegacyId] 兜底映射到新分类。
  final BookshelfKind kind;

  /// 书架显示名（站点书架为去掉 `www.` 前缀的 host，见 [siteDisplayName]）
  final String name;

  /// 站点书架的来源网站 host（小写，如 `www.example.com`）。
  ///
  /// 仅 [BookshelfKind.online] 的按站点拆分书架非空；与站点提取脚本
  /// 体系（`site_scripts.domain`）同源：`Uri.tryParse(url)?.host`。
  final String? domain;

  const Bookshelf({
    required this.kind,
    required this.name,
    this.domain,
  });

  /// 三个基础书架的固定列表（历史遗留：旧"联网"为聚合书架）。
  ///
  /// 运行时 UI Tab 走 [tabShelves]（联网按站点拆分）；本列表仅用于
  /// 兼容旧调用（`getBookshelves`）与 `fromLegacyId` 兜底。
  static const List<Bookshelf> systemShelves = [
    Bookshelf(kind: BookshelfKind.all, name: '全部'),
    Bookshelf(kind: BookshelfKind.original, name: '原创'),
    Bookshelf(kind: BookshelfKind.online, name: '联网'),
  ];

  /// UI Tab 书架列表：全部/原创固定 + 按来源站点拆分的联网书架。
  ///
  /// [siteDomains] 为有藏书的站点 host 列表（由仓库按最近活跃排序），
  /// 顺序即 Tab 顺序。
  ///
  /// [displayNames] 为 `domain -> 站点显示名`（来自 `site_scripts.display_name`，
  /// 如 `www.qidian.com -> 起点中文网`）；未命中的站点回退 host
  /// （见 [siteDisplayName]）。
  static List<Bookshelf> tabShelves(
    List<String> siteDomains, {
    Map<String, String> displayNames = const {},
  }) {
    return [
      const Bookshelf(kind: BookshelfKind.all, name: '全部'),
      const Bookshelf(kind: BookshelfKind.original, name: '原创'),
      for (final domain in siteDomains)
        Bookshelf(
          kind: BookshelfKind.online,
          name: displayNames[domain.toLowerCase()] ?? siteDisplayName(domain),
          domain: domain,
        ),
    ];
  }

  /// 站点书架默认显示名：去掉 `www.` 前缀的 host（如 `www.qidian.com` →
  /// `qidian.com`）。站点在 `site_scripts.display_name` 登记过名字时，
  /// 展示方优先用登记名，本方法仅作回退。
  static String siteDisplayName(String host) {
    return host.startsWith('www.') ? host.substring('www.'.length) : host;
  }

  /// 是否为按站点拆分的联网书架
  bool get isSiteShelf => kind == BookshelfKind.online && domain != null;

  /// 通过 [BookshelfKind] 查找基础书架（聚合"联网"），找不到时回退到"全部"。
  ///
  /// 注意：按站点拆分的联网书架 kind 同为 [BookshelfKind.online] 但带
  /// [domain]，不在本方法的查找范围。
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

  /// 序列化为 SharedPreferences 持久化值（新键 `current_bookshelf_kind`）。
  ///
  /// 格式：`all` / `original` / `online:<host>`。
  String toPersistedValue() {
    if (kind == BookshelfKind.online && domain != null) {
      return '${BookshelfKind.online.name}:$domain';
    }
    return kind.name;
  }

  /// 从持久化值反序列化。
  ///
  /// 兼容旧值：裸 `online`（聚合"联网"Tab 已下线）、`online:` 空 host
  /// 与未知值均兜底为"全部"。
  static Bookshelf fromPersistedValue(String value) {
    const all = Bookshelf(kind: BookshelfKind.all, name: '全部');
    if (value.startsWith('${BookshelfKind.online.name}:')) {
      final domain = value.substring(BookshelfKind.online.name.length + 1);
      if (domain.isEmpty) return all; // 空 host 非法
      return Bookshelf(
        kind: BookshelfKind.online,
        name: siteDisplayName(domain),
        domain: domain,
      );
    }
    if (value == BookshelfKind.original.name) {
      return const Bookshelf(kind: BookshelfKind.original, name: '原创');
    }
    // `all`、裸 `online`（旧聚合书架）与未知值 → 全部
    return all;
  }

  Bookshelf copyWith({BookshelfKind? kind, String? name, String? domain}) {
    return Bookshelf(
      kind: kind ?? this.kind,
      name: name ?? this.name,
      domain: domain ?? this.domain,
    );
  }

  @override
  String toString() => 'Bookshelf(kind: $kind, name: $name, domain: $domain)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Bookshelf &&
        other.kind == kind &&
        other.domain == domain;
  }

  @override
  int get hashCode => Object.hash(kind, domain);
}

/// 书架分类（按来源派生）
enum BookshelfKind {
  /// 全部小说（不过滤 URL）
  all,

  /// 原创（`custom://` 前缀，由 Agent 工具或独立入口创建的小说）
  original,

  /// 联网（非 `custom://` 的 URL，浏览器加入或书源抓取）。
  ///
  /// 书架页按来源网站（URL host）拆分展示；host 持有在
  /// [Bookshelf.domain]，裸 kind 仅为聚合语义（旧"联网"Tab、统计查询）。
  online,
}

import 'package:sqflite/sqflite.dart';
import '../models/bookshelf.dart';
import '../models/novel.dart';
import 'base_repository.dart';
import '../core/interfaces/repositories/i_bookshelf_repository.dart';

/// 书架数据仓库（按"小说来源"派生）
///
/// 新设计下书架由小说 URL 派生（全部/原创 + 联网按来源网站拆分），
/// 用户不可增删改。因此本仓库只做"读"操作。
///
/// ## 历史遗留
///
/// - **bookshelf 表**: 物理表，存储小说元数据（历史遗留命名，与 Bookshelf 模型无关）
/// - **bookshelves / novel_bookshelves 表**: 旧"用户自定义书架"的数据表，
///   已停用（schema 保留避免破坏性 migration，运行时不再读写）
///
/// ## 分类规则
///
/// - [BookshelfKind.all]：bookshelf 表全部行
/// - [BookshelfKind.original]：`custom://` 前缀（原创）
/// - [BookshelfKind.online]：非 `custom://` 前缀（联网，按 URL host 再拆分站点）
class BookshelfRepository extends BaseRepository
    implements IBookshelfRepository {
  /// 构造函数 - 接受数据库连接实例
  BookshelfRepository({required super.dbConnection});

  /// 原创小说的 URL 前缀（与 Agent create_novel 工具、NovelCover 印章判定一致）
  static const String _originalPrefix = 'custom://';

  /// 联网行的过滤条件（非 `custom://` 前缀或 URL 为空）
  static const String _onlineWhere = 'url NOT LIKE ? OR url IS NULL';

  // ==================== 书架列表 ====================

  /// 获取基础书架（全部/原创/联网聚合的固定列表）
  ///
  /// UI Tab 的完整列表（联网按站点拆分）由 [getOnlineSourceDomains]
  /// 配合 `Bookshelf.tabShelves` 生成。
  @override
  Future<List<Bookshelf>> getBookshelves() async {
    return Bookshelf.systemShelves;
  }

  // ==================== 书架内容查询 ====================

  /// 行 Map 转 Novel 列表（统一排序由查询 orderBy 保证）
  List<Novel> _mapsToNovels(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return Novel(
        title: maps[i]['title'],
        author: maps[i]['author'],
        url: maps[i]['url'],
        coverUrl: maps[i]['coverUrl'],
        coverMediaId: maps[i]['coverMediaId'],
        description: maps[i]['description'],
        backgroundSetting: maps[i]['backgroundSetting'],
        isInBookshelf: true,
        lastReadChapterIndex: maps[i]['lastReadChapter'] as int?,
      );
    });
  }

  /// 解析联网小说 URL 的站点 host（小写）；无法解析或为空返回 null。
  ///
  /// 与站点提取脚本体系（site_scripts.domain）同口径。
  static String? _sourceDomainOf(String? url) {
    if (url == null || url.isEmpty) return null;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host.isEmpty ? null : host;
  }

  /// 获取指定书架中的小说列表
  ///
  /// [kind] 书架分类（全部/原创/联网聚合）
  ///
  /// 返回小说列表，按最后阅读时间和添加时间降序排列
  ///
  /// Web平台返回空列表
  @override
  Future<List<Novel>> getNovelsByBookshelf(BookshelfKind kind) async {
    if (isWebPlatform) {
      return [];
    }

    final db = await database;

    final List<Map<String, dynamic>> maps;
    switch (kind) {
      case BookshelfKind.all:
        maps = await db.query(
          'bookshelf',
          orderBy: 'lastReadTime DESC, addedAt DESC',
        );
        break;
      case BookshelfKind.original:
        maps = await db.query(
          'bookshelf',
          where: 'url LIKE ?',
          whereArgs: ['$_originalPrefix%'],
          orderBy: 'lastReadTime DESC, addedAt DESC',
        );
        break;
      case BookshelfKind.online:
        maps = await db.query(
          'bookshelf',
          where: _onlineWhere,
          whereArgs: ['$_originalPrefix%'],
          orderBy: 'lastReadTime DESC, addedAt DESC',
        );
        break;
    }

    return _mapsToNovels(maps);
  }

  /// 获取指定来源网站的联网小说列表
  ///
  /// [domain] 站点 host（小写）。SQLite 无 URI 解析能力，host 过滤在
  /// Dart 侧完成（书架为个人数据，行数量级小，先按排序取出联网行再筛）。
  @override
  Future<List<Novel>> getNovelsBySourceDomain(String domain) async {
    if (isWebPlatform) {
      return [];
    }

    final db = await database;
    final maps = await db.query(
      'bookshelf',
      where: _onlineWhere,
      whereArgs: ['$_originalPrefix%'],
      orderBy: 'lastReadTime DESC, addedAt DESC',
    );

    final target = domain.toLowerCase();
    return _mapsToNovels(maps)
        .where((n) => _sourceDomainOf(n.url) == target)
        .toList();
  }

  /// 获取有藏书的联网来源站点 host 列表（去重，按最近活跃降序）
  @override
  Future<List<String>> getOnlineSourceDomains() async {
    if (isWebPlatform) {
      return [];
    }

    final db = await database;
    final maps = await db.query(
      'bookshelf',
      columns: ['url'],
      where: _onlineWhere,
      whereArgs: ['$_originalPrefix%'],
      orderBy: 'lastReadTime DESC, addedAt DESC',
    );

    final domains = <String>[];
    for (final row in maps) {
      final domain = _sourceDomainOf(row['url'] as String?);
      if (domain != null && !domains.contains(domain)) {
        domains.add(domain);
      }
    }
    return domains;
  }

  /// 获取书架中的小说数量
  ///
  /// [kind] 书架分类（全部/原创/联网聚合）
  @override
  Future<int> getNovelCountByBookshelf(BookshelfKind kind) async {
    if (isWebPlatform) {
      return 0;
    }

    final db = await database;

    final String? where;
    final List<Object?>? whereArgs;
    switch (kind) {
      case BookshelfKind.all:
        where = null;
        whereArgs = null;
        break;
      case BookshelfKind.original:
        where = 'url LIKE ?';
        whereArgs = ['$_originalPrefix%'];
        break;
      case BookshelfKind.online:
        where = _onlineWhere;
        whereArgs = ['$_originalPrefix%'];
        break;
    }

    final result = await db.query(
      'bookshelf',
      columns: ['COUNT(*) as count'],
      where: where,
      whereArgs: whereArgs,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

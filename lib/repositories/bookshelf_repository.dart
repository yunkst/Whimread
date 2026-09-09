import 'package:sqflite/sqflite.dart';
import '../models/bookshelf.dart';
import '../models/novel.dart';
import 'base_repository.dart';
import '../core/interfaces/repositories/i_bookshelf_repository.dart';

/// 书架数据仓库（按"小说来源"派生）
///
/// 新设计下书架只有三档系统分类（[BookshelfKind]：全部/原创/联网），
/// 由小说 URL 前缀派生，用户不可增删改。因此本仓库只做"读"操作。
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
/// - [BookshelfKind.online]：非 `custom://` 前缀（联网）
class BookshelfRepository extends BaseRepository
    implements IBookshelfRepository {
  /// 构造函数 - 接受数据库连接实例
  BookshelfRepository({required super.dbConnection});

  /// 原创小说的 URL 前缀（与 Agent create_novel 工具、NovelCover 印章判定一致）
  static const String _originalPrefix = 'custom://';

  // ==================== 书架列表 ====================

  /// 获取所有书架（三档系统分类的固定列表）
  ///
  /// 顺序即 UI Tab 顺序：全部 -> 原创 -> 联网
  @override
  Future<List<Bookshelf>> getBookshelves() async {
    return Bookshelf.systemShelves;
  }

  // ==================== 书架内容查询 ====================

  /// 获取指定书架中的小说列表
  ///
  /// [kind] 书架分类（全部/原创/联网）
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
          where: 'url NOT LIKE ? OR url IS NULL',
          whereArgs: ['$_originalPrefix%'],
          orderBy: 'lastReadTime DESC, addedAt DESC',
        );
        break;
    }

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

  /// 获取书架中的小说数量
  ///
  /// [kind] 书架分类（全部/原创/联网）
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
        where = 'url NOT LIKE ? OR url IS NULL';
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

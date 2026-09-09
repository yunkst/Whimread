import '../../../models/bookshelf.dart';
import '../../../models/novel.dart';

/// 书架数据仓库接口（按"小说来源"派生）
///
/// 新设计下书架只有三档系统分类（全部/原创/联网），由小说 URL 前缀派生，
/// 用户不可增删改。因此本接口只暴露"读"操作。
///
/// 关联表写操作（addNovelToBookshelf / removeNovelFromBookshelf /
/// moveNovelToBookshelf）已随"用户自定义书架"功能一起移除——
/// 旧 `novel_bookshelves` 关联表不再读写。
abstract class IBookshelfRepository {
  /// 获取所有书架（三档系统分类的固定列表）
  ///
  /// 顺序即 UI Tab 顺序：全部 -> 原创 -> 联网
  Future<List<Bookshelf>> getBookshelves();

  /// 获取指定书架中的小说列表
  ///
  /// [kind] 书架分类（全部/原创/联网）
  ///
  /// 返回小说列表，按最后阅读时间和添加时间降序排列
  ///
  /// 分类规则（由小说 URL 派生）：
  /// - [BookshelfKind.all]：返回 bookshelf 表中所有小说
  /// - [BookshelfKind.original]：仅 `custom://` 前缀（原创）
  /// - [BookshelfKind.online]：非 `custom://` 前缀（联网）
  ///
  /// Web平台返回空列表
  Future<List<Novel>> getNovelsByBookshelf(BookshelfKind kind);

  /// 获取书架中的小说数量
  ///
  /// [kind] 书架分类（全部/原创/联网）
  Future<int> getNovelCountByBookshelf(BookshelfKind kind);
}

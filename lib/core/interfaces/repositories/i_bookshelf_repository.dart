import '../../../models/bookshelf.dart';
import '../../../models/novel.dart';

/// 书架数据仓库接口（按"小说来源"派生）
///
/// 新设计下书架由小说来源派生（全部/原创 + 联网按来源网站拆分），
/// 用户不可增删改。因此本接口只暴露"读"操作。
///
/// 关联表写操作（addNovelToBookshelf / removeNovelFromBookshelf /
/// moveNovelToBookshelf）已随"用户自定义书架"功能一起移除——
/// 旧 `novel_bookshelves` 关联表不再读写。
abstract class IBookshelfRepository {
  /// 获取基础书架（全部/原创/联网聚合的固定列表）
  ///
  /// UI Tab 的完整列表（联网按站点拆分）由 [getOnlineSourceDomains]
  /// 配合 `Bookshelf.tabShelves` 生成。
  Future<List<Bookshelf>> getBookshelves();

  /// 获取指定书架中的小说列表
  ///
  /// [kind] 书架分类（全部/原创/联网聚合）
  ///
  /// 返回小说列表，按最后阅读时间和添加时间降序排列
  ///
  /// 分类规则（由小说 URL 派生）：
  /// - [BookshelfKind.all]：返回 bookshelf 表中所有小说
  /// - [BookshelfKind.original]：仅 `custom://` 前缀（原创）
  /// - [BookshelfKind.online]：非 `custom://` 前缀（联网，含所有站点）
  ///
  /// Web平台返回空列表
  Future<List<Novel>> getNovelsByBookshelf(BookshelfKind kind);

  /// 获取指定来源网站的联网小说列表
  ///
  /// [domain] 站点 host（小写，`Uri.tryParse(url)?.host` 口径，与
  /// `site_scripts.domain` 同源）
  ///
  /// 返回该站点的小说列表，排序规则同 [getNovelsByBookshelf]。
  /// URL 无法解析或 host 为空的联网小说不属于任何站点书架（仅出现在
  /// "全部"中）。Web平台返回空列表。
  Future<List<Novel>> getNovelsBySourceDomain(String domain);

  /// 获取有藏书的联网来源站点 host 列表
  ///
  /// 返回去重后的 host（小写），按最近活跃（最后阅读/添加时间）降序排列，
  /// 顺序即 UI Tab 顺序。Web平台返回空列表。
  Future<List<String>> getOnlineSourceDomains();

  /// 获取书架中的小说数量
  ///
  /// [kind] 书架分类（全部/原创/联网聚合）
  Future<int> getNovelCountByBookshelf(BookshelfKind kind);
}

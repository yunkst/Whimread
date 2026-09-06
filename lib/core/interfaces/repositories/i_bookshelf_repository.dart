import '../../../models/bookshelf.dart';
import '../../../models/novel.dart';

/// 书架数据仓库接口
///
/// 负责书架分类的数据库操作，包括：
/// - 书架CRUD操作（创建、读取、更新、删除）
/// - 书架与小说的多对多关系管理
/// - 书架排序和分组
/// - 书架统计信息
///
/// 关联表写操作（addNovelToBookshelf / removeNovelFromBookshelf /
/// moveNovelToBookshelf）已移至内部 `IBookshelfAssociationWriter` 接口，
/// 仅 [BookshelfRepository] 实现，调用方须经 BookshelfMutationNotifier 走统一写入路径。
abstract class IBookshelfRepository {
  // ==================== 书架CRUD操作 ====================

  /// 获取所有书架列表
  ///
  /// 返回所有书架，包括系统书架和用户创建的书架
  /// 按排序字段（sort_order）升序排列
  ///
  /// Web平台返回默认系统书架（全部小说、我的收藏）
  Future<List<Bookshelf>> getBookshelves();

  /// 创建新书架
  ///
  /// [name] 书架名称
  ///
  /// 返回新创建的书架ID
  ///
  /// 自动计算并设置排序顺序（最大sort_order + 1）
  ///
  /// Web平台抛出UnsupportedError异常
  Future<int> createBookshelf(String name);

  /// 删除书架
  ///
  /// [bookshelfId] 书架ID
  ///
  /// 返回是否删除成功
  ///
  /// 限制：
  /// - 系统书架（is_system=1）不能删除
  /// - 书架不存在返回false
  /// - 删除书架会级联删除novel_bookshelves表中的关联记录
  ///
  /// Web平台抛出UnsupportedError异常
  Future<bool> deleteBookshelf(int bookshelfId);

  // ==================== 书架与小说关系管理 ====================

  /// 获取指定书架中的小说列表
  ///
  /// [bookshelfId] 书架ID
  ///
  /// 返回小说列表，按最后阅读时间和添加时间降序排列
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：返回bookshelf表中的所有小说
  /// - 其他书架：通过novel_bookshelves关联表查询
  ///
  /// Web平台返回空列表
  Future<List<Novel>> getNovelsByBookshelf(int bookshelfId);

  // ==================== 书架统计和查询 ====================

  /// 获取小说所属的所有书架
  ///
  /// [novelUrl] 小说URL
  ///
  /// 返回书架ID列表
  ///
  /// 特殊处理：
  /// - 始终包含"全部小说"书架（ID=1）
  /// - 返回去重后的列表
  ///
  /// Web平台返回[1]（全部小说）
  Future<List<int>> getBookshelvesByNovel(String novelUrl);

  /// 获取书架中的小说数量
  ///
  /// [bookshelfId] 书架ID
  ///
  /// 返回小说数量
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：返回bookshelf表中的所有小说数量
  /// - 其他书架：返回novel_bookshelves表中的关联记录数量
  Future<int> getNovelCountByBookshelf(int bookshelfId);

  /// 检查小说是否在指定书架中
  ///
  /// [novelUrl] 小说URL
  /// [bookshelfId] 书架ID
  ///
  /// 返回是否在书架中
  ///
  /// 特殊处理：
  /// - bookshelfId=1（全部小说）：检查小说是否在bookshelf表中
  /// - 其他书架：检查novel_bookshelves表中是否存在关联记录
  Future<bool> isNovelInBookshelf(String novelUrl, int bookshelfId);

  // ==================== 书架排序和分组 ====================

  /// 更新书架排序顺序
  ///
  /// [bookshelfIds] 书架ID列表，按新的显示顺序排列
  ///
  /// 系统书架（ID=1,2）不会改变其位置
  ///
  /// Web平台抛出UnsupportedError异常
  Future<void> reorderBookshelves(List<int> bookshelfIds);

  /// 更新书架信息
  ///
  /// [bookshelf] 书架对象
  ///
  /// 返回更新的行数
  ///
  /// 限制：
  /// - 系统书架（isSystem=true）只能更新sort_order
  /// - 用户书架可以更新name、icon、color、sort_order
  ///
  /// Web平台抛出UnsupportedError异常
  Future<int> updateBookshelf(Bookshelf bookshelf);
}

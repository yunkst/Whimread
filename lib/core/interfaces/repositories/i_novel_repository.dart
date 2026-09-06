import '../../../models/novel.dart';

/// 小说数据仓库接口
///
/// 负责小说元数据和阅读进度的数据访问操作。
///
/// 写操作（addToBookshelf / removeFromBookshelf / updateTitle /
/// updateCoverMediaIdByUrl / createNovel）已移至内部 `IBookshelfWriter` 接口，
/// 仅 [NovelRepository] 实现，调用方须经 BookshelfMutationNotifier 走统一写入路径。
abstract class INovelRepository {
  /// 获取所有小说
  ///
  /// 返回小说列表，按最后阅读时间和添加时间降序排列
  Future<List<Novel>> getNovels();

  /// 检查小说是否在书架中
  ///
  /// [novelUrl] 小说的URL
  /// 返回是否在书架中
  Future<bool> isInBookshelf(String novelUrl);

  /// 更新最后阅读章节
  ///
  /// [novelUrl] 小说的URL
  /// [chapterIndex] 章节索引
  /// 返回受影响的行数
  Future<int> updateLastReadChapter(String novelUrl, int chapterIndex);

  /// 更新小说背景设定
  ///
  /// [novelUrl] 小说的URL
  /// [backgroundSetting] 背景设定内容
  /// 返回受影响的行数
  Future<int> updateBackgroundSetting(
      String novelUrl, String? backgroundSetting);

  /// 获取小说背景设定
  ///
  /// [novelUrl] 小说的URL
  /// 返回背景设定内容，如果不存在则返回null
  Future<String?> getBackgroundSetting(String novelUrl);

  /// 获取上次阅读的章节索引
  ///
  /// [novelUrl] 小说的URL
  /// 返回章节索引，如果不存在则返回0
  Future<int> getLastReadChapter(String novelUrl);

  /// 根据 title 查找小说
  ///
  /// [title] 小说标题
  /// 返回小说对象，如果不存在则返回null
  Future<Novel?> getNovelByTitle(String title);

  /// 根据 URL 查找小说
  ///
  /// [novelUrl] 小说 URL（唯一标识）
  /// 返回小说对象，如果不存在则返回null
  Future<Novel?> getNovelByUrl(String novelUrl);

  // ========== ID-based 查询方法（Agent 工具用） ==========

  /// 根据 ID 查询小说
  ///
  /// [id] bookshelf.id
  /// 返回 Novel 对象，不存在则返回 null
  Future<Novel?> getNovelById(int id);

  /// 根据 ID 获取小说 URL（内部 ID→URL 解析用）
  ///
  /// [id] bookshelf.id
  /// 返回小说 URL，不存在则返回 null
  Future<String?> getNovelUrlById(int id);

  /// 根据 ID 更新小说背景设定（解析 URL 后委托 updateBackgroundSetting）
  ///
  /// [id] bookshelf.id
  /// [setting] 背景设定内容
  /// 返回受影响的行数，ID 不存在则返回 0
  Future<int> updateBackgroundSettingById(int id, String? setting);

  /// 根据 ID 更新小说封面媒体 ID
  ///
  /// [id] bookshelf.id
  /// [mediaId] 媒体资源 ID（来自 create_images / create_image_to_video），
  ///   传 null 表示清空封面（回到程序化占位）
  /// 返回受影响的行数，ID 不存在则返回 0
  Future<int> updateCoverMediaIdById(int id, String? mediaId);
}

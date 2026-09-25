import '../../../models/novel.dart';
import '../../../models/reading_anchor.dart';

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
  ///
  /// URL 机械变体（协议/大小写/尾部斜杠/锚点/默认端口，经
  /// NovelUrlNormalizer 归一化）视为同一本。
  Future<bool> isInBookshelf(String novelUrl);

  /// 查找书架中与 [novelUrl] 归一化后相同的既有行原始 URL
  ///
  /// 书架去重与后续写操作的统一判定入口：命中时返回书架里已存的原始 URL
  /// （章节缓存/阅读进度须沿用该键写入）；未命中返回 null。
  Future<String?> findExistingBookshelfUrl(String novelUrl);

  /// 更新最后阅读章节
  ///
  /// [novelUrl] 小说的URL
  /// [chapterIndex] 章节索引
  /// 返回受影响的行数
  Future<int> updateLastReadChapter(String novelUrl, int chapterIndex);

  /// 获取章内阅读位置锚点
  ///
  /// [novelUrl] 小说的URL
  /// 无锚点（从未读过/旧版本数据/格式损坏）时返回 null。
  Future<ReadingAnchor?> getLastReadAnchor(String novelUrl);

  /// 更新章内阅读位置锚点（高频写入，仅更新 lastReadAnchor 列）
  ///
  /// 注意：本方法刻意**不走** BookshelfMutationNotifier 收口——锚点
  /// 不展示在任何 UI 上（书架列表不读它），无需 invalidate 触发刷新，
  /// 而高频滚动节流写入若每次 invalidate 反复重建底层路由的监听者。
  /// 若未来有 UI 展示锚点，应改为经 Notifier 并补 invalidate。
  Future<int> updateLastReadAnchor(String novelUrl, ReadingAnchor anchor);

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
  /// [mediaId] 媒体资源 ID（来自 create_images），
  ///   传 null 表示清空封面（回到程序化占位）
  /// 返回受影响的行数，ID 不存在则返回 0
  Future<int> updateCoverMediaIdById(int id, String? mediaId);
}

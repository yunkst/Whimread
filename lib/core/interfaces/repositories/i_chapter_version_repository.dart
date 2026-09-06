import '../../../models/chapter_version.dart';

/// 章节版本仓库接口
///
/// 负责章节历史版本的增删查操作，以及版本淘汰逻辑
abstract class IChapterVersionRepository {
  /// 保存一个历史版本
  ///
  /// [version] 版本对象，id 应为 null（自增）
  /// 返回插入后的行 ID
  Future<int> saveVersion(ChapterVersion version);

  /// 获取指定章节的所有版本（按创建时间降序，最新的在前）
  ///
  /// [chapterUrl] 章节URL
  Future<List<ChapterVersion>> getVersions(String chapterUrl);

  /// 获取指定章节的版本数量
  ///
  /// [chapterUrl] 章节URL
  Future<int> getVersionCount(String chapterUrl);

  /// 获取指定版本（by id）
  ///
  /// [id] 版本记录 ID
  Future<ChapterVersion?> getVersionById(int id);

  /// 删除指定版本
  ///
  /// [id] 版本记录 ID
  /// 返回受影响行数
  Future<int> deleteVersion(int id);

  /// 删除指定章节的所有版本（级联删除用）
  ///
  /// [chapterUrl] 章节URL
  /// 返回受影响行数
  Future<int> deleteVersionsByChapter(String chapterUrl);

  /// 删除指定小说所有章节的版本（级联删除用）
  ///
  /// [novelUrl] 小说URL
  /// 返回受影响行数
  Future<int> deleteVersionsByNovel(String novelUrl);

  /// 淘汰最老版本，使版本数不超过 [maxCount]
  ///
  /// [chapterUrl] 章节URL
  /// [maxCount] 最大保留版本数，默认 5
  /// 返回被删除的版本数量
  Future<int> evictOldestVersions(String chapterUrl, {int maxCount = 5});
}

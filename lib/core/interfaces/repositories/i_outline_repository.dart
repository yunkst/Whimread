import '../../../models/outline.dart';

/// 大纲数据仓库接口
///
/// 负责管理小说大纲的数据库操作，包括大纲的创建、更新、查询和删除。
/// 每本小说对应一个大纲记录，通过 novelUrl 进行关联。
abstract class IOutlineRepository {
  /// 创建或更新大纲
  ///
  /// 如果小说URL已存在大纲则更新，否则创建新的。
  ///
  /// 参数：
  /// - [outline] 要保存的大纲对象
  ///
  /// 返回：
  /// - 受影响的行数（更新）或新插入记录的ID（创建）
  Future<int> saveOutline(Outline outline);

  /// 根据小说URL获取大纲
  ///
  /// 参数：
  /// - [novelUrl] 小说的URL，作为唯一标识
  ///
  /// 返回：
  /// - 找到的大纲对象，如果不存在则返回 null
  Future<Outline?> getOutlineByNovelUrl(String novelUrl);

  /// 获取所有大纲
  ///
  /// 返回：
  /// - 所有大纲的列表，按更新时间降序排列（最近更新的在前）
  Future<List<Outline>> getAllOutlines();

  /// 删除大纲
  ///
  /// 参数：
  /// - [novelUrl] 要删除大纲的小说URL
  ///
  /// 返回：
  /// - 受影响的行数，如果大纲不存在则返回 0
  Future<int> deleteOutline(String novelUrl);

  /// 更新大纲内容
  ///
  /// 直接更新大纲的标题和内容，同时更新时间戳。
  ///
  /// 参数：
  /// - [novelUrl] 小说URL
  /// - [title] 新的标题
  /// - [content] 新的内容
  ///
  /// 返回：
  /// - 受影响的行数，如果大纲不存在则返回 0
  Future<int> updateOutlineContent(
    String novelUrl,
    String title,
    String content,
  );
}

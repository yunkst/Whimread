/// 章节相关常量定义
///
/// 统一管理章节列表、缓存和上下文相关的所有魔法数字
class ChapterConstants {
  // 私有构造函数，防止实例化
  ChapterConstants._();

  /// 最大内存缓存章节数
  ///
  /// ChapterRepository 中内存缓存的最大章节数量
  static const int maxMemoryCacheSize = 1000;

  /// 每页章节数量
  ///
  /// 章节列表分页显示时，每页显示的章节数量
  static const int chaptersPerPage = 100;
}

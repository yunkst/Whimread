/// 预加载任务
///
/// 表示一个待预加载的章节任务
class PreloadTask {
  /// 章节URL
  final String chapterUrl;

  /// 小说URL
  final String novelUrl;

  /// 小说标题
  final String novelTitle;

  /// 章节索引
  final int chapterIndex;

  /// 任务创建时间
  final DateTime createdAt;

  /// 创建预加载任务
  PreloadTask({
    required this.chapterUrl,
    required this.novelUrl,
    required this.novelTitle,
    required this.chapterIndex,
  }) : createdAt = DateTime.now();

  @override
  String toString() {
    return '$novelTitle 第${chapterIndex + 1}章';
  }

  /// 可读标题："小说标题 第N章"
  String get displayTitle => '$novelTitle 第${chapterIndex + 1}章';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PreloadTask &&
        other.chapterUrl == chapterUrl &&
        other.novelUrl == novelUrl;
  }

  @override
  int get hashCode => chapterUrl.hashCode ^ novelUrl.hashCode;
}

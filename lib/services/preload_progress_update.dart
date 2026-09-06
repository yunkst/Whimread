/// 预加载进度更新事件
///
/// 用于在 PreloadService 和 UI 层之间传递预加载进度信息
class PreloadProgressUpdate {
  /// 小说URL
  final String novelUrl;

  /// 章节URL（可选，用于精确更新单个章节的缓存状态）
  final String? chapterUrl;

  /// 小说标题（可选，用于 UI 展示）
  final String? novelTitle;

  /// 章节索引（可选，用于 UI 展示 "第N章"）
  final int? chapterIndex;

  /// 时间戳
  final DateTime timestamp;

  /// 可读标题：优先 "小说标题 第N章"，回退 novelUrl
  String get displayTitle {
    if (novelTitle != null && chapterIndex != null) {
      return '$novelTitle 第${chapterIndex! + 1}章';
    }
    if (novelTitle != null) return novelTitle!;
    return chapterUrl ?? novelUrl;
  }

  /// 创建预加载进度更新事件
  PreloadProgressUpdate({
    required this.novelUrl,
    this.chapterUrl,
    this.novelTitle,
    this.chapterIndex,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'PreloadProgressUpdate(novelUrl: $novelUrl, '
        'chapterUrl: $chapterUrl, '
        'novelTitle: $novelTitle, '
        'chapterIndex: $chapterIndex, '
        'timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PreloadProgressUpdate &&
        other.novelUrl == novelUrl &&
        other.chapterUrl == chapterUrl &&
        other.novelTitle == novelTitle &&
        other.chapterIndex == chapterIndex;
  }

  @override
  int get hashCode {
    return novelUrl.hashCode ^
        (chapterUrl?.hashCode ?? 0) ^
        (novelTitle?.hashCode ?? 0) ^
        (chapterIndex?.hashCode ?? 0);
  }
}

/// 预加载历史记录条目
///
/// 记录已处理（成功或失败）的章节快照，供 UI 详情面板展示。
/// 复用 [PreloadTask] 的标题字段，避免回查数据库。
class PreloadHistoryEntry {
  /// 小说标题
  final String novelTitle;

  /// 章节索引（0-based）
  final int chapterIndex;

  /// 章节URL
  final String chapterUrl;

  /// 小说URL
  final String novelUrl;

  /// 完成时间
  final DateTime time;

  /// 失败原因（成功为 null）
  final String? error;

  const PreloadHistoryEntry({
    required this.novelTitle,
    required this.chapterIndex,
    required this.chapterUrl,
    required this.novelUrl,
    required this.time,
    this.error,
  });

  /// 可读标题："小说标题 第N章"
  String get displayTitle => '$novelTitle 第${chapterIndex + 1}章';

  /// 是否为失败记录
  bool get isFailed => error != null;

  @override
  String toString() {
    final status = isFailed ? 'failed' : 'ok';
    return 'PreloadHistoryEntry($displayTitle, $status)';
  }
}
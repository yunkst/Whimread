class Chapter {
  /// 章节数据库主键（来自 novel_chapters.id），可空表示尚未持久化
  final int? id;
  final String title;
  final String url;
  final String? content;
  final bool isCached;
  final int? chapterIndex;
  final bool isUserInserted;
  final int? readAt;

  Chapter({
    this.id,
    required this.title,
    required this.url,
    this.content,
    this.isCached = false,
    this.chapterIndex,
    this.isUserInserted = false,
    this.readAt,
  });

  /// 是否已读（readAt 不为 null 即表示已读）
  bool get isRead => readAt != null;

  Chapter copyWith({
    int? id,
    String? title,
    String? url,
    String? content,
    bool? isCached,
    int? chapterIndex,
    bool? isUserInserted,
    int? readAt,
  }) {
    return Chapter(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      content: content ?? this.content,
      isCached: isCached ?? this.isCached,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      isUserInserted: isUserInserted ?? this.isUserInserted,
      readAt: readAt ?? this.readAt,
    );
  }
}

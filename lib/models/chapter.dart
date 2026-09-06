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
  final bool isAccompanied;

  Chapter({
    this.id,
    required this.title,
    required this.url,
    this.content,
    this.isCached = false,
    this.chapterIndex,
    this.isUserInserted = false,
    this.readAt,
    this.isAccompanied = false,
  });

  /// 是否已读（readAt 不为 null 即表示已读）
  bool get isRead => readAt != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'content': content,
      'isCached': isCached ? 1 : 0,
      'chapterIndex': chapterIndex,
      'isUserInserted': isUserInserted ? 1 : 0,
      'readAt': readAt,
      'isAccompanied': isAccompanied ? 1 : 0,
    };
  }

  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      id: map['id'] as int?,
      title: map['title'] as String,
      url: map['url'] as String,
      content: map['content'] as String?,
      isCached: (map['isCached'] as int?) == 1,
      chapterIndex: map['chapterIndex'] as int?,
      isUserInserted: (map['isUserInserted'] as int?) == 1,
      readAt: map['readAt'] as int?,
      isAccompanied: (map['isAccompanied'] as int?) == 1,
    );
  }

  Chapter copyWith({
    int? id,
    String? title,
    String? url,
    String? content,
    bool? isCached,
    int? chapterIndex,
    bool? isUserInserted,
    int? readAt,
    bool? isAccompanied,
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
      isAccompanied: isAccompanied ?? this.isAccompanied,
    );
  }
}

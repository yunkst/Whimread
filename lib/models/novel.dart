/// 小说模型
///
/// 对应数据库 `bookshelf` 表（历史遗留命名，实际存储小说元数据）。
/// 表结构（见 database_migrations.dart createV1Tables）：
///   id, title, author, url, coverUrl, description, backgroundSetting,
///   addedAt, lastReadChapter, lastReadTime
///
/// 注意：[isInBookshelf] 是内存派生标记，并非 bookshelf 表的列，
/// 因此不会出现在 [toMap]/[fromMap] 中（避免写入不存在的列）。
class Novel {
  /// 小说数据库主键（来自 bookshelf.id），可空表示尚未持久化
  final int? id;
  final String title;
  final String author;
  final String url;

  /// 内存派生标记：是否已在书架中。非表列，不参与序列化。
  final bool isInBookshelf;

  final String? coverUrl;
  final String? description;
  final String? backgroundSetting;

  /// 封面媒体资源 ID（图像/视频），经 MediaView 渲染。
  /// 由 set_novel_cover 工具写入；为 null 时 NovelCover 走程序化占位。
  /// 旧 coverUrl 字段保留兼容，但新代码优先使用本字段。
  final String? coverMediaId;

  /// 上次阅读章节索引（来自 bookshelf.lastReadChapter）
  final int? lastReadChapterIndex;

  /// 阅读进度，由调用方基于 lastReadTime 等派生，非表列
  final double? readingProgress;

  Novel({
    this.id,
    required this.title,
    required this.author,
    required this.url,
    this.isInBookshelf = false,
    this.coverUrl,
    this.description,
    this.backgroundSetting,
    this.coverMediaId,
    this.lastReadChapterIndex,
    this.readingProgress,
  });

  /// 序列化为 bookshelf 表行。
  ///
  /// 仅包含表实际存在的列（见 database_migrations.dart），
  /// 不含 [isInBookshelf]（非表列）以及 addedAt/lastReadTime
  /// （由数据库自管理或 Repository 单独更新）。
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'url': url,
      'coverUrl': coverUrl,
      'description': description,
      'backgroundSetting': backgroundSetting,
      'coverMediaId': coverMediaId,
    };
  }

  /// 从 bookshelf 表行反序列化。
  ///
  /// - `lastReadChapter` 列 -> [lastReadChapterIndex]
  /// - `lastReadTime` 列（毫秒时间戳）-> [readingProgress] 的派生输入
  ///   （此处仅原样透传时间戳占比，具体语义由调用方决定）
  factory Novel.fromMap(Map<String, dynamic> map) {
    final lastReadTime = map['lastReadTime'] as int?;
    return Novel(
      id: map['id'] as int?,
      title: map['title'] as String,
      author: map['author'] as String,
      url: map['url'] as String,
      coverUrl: map['coverUrl'] as String?,
      description: map['description'] as String?,
      backgroundSetting: map['backgroundSetting'] as String?,
      coverMediaId: map['coverMediaId'] as String?,
      lastReadChapterIndex: map['lastReadChapter'] as int?,
      readingProgress: lastReadTime?.toDouble(),
    );
  }

  Novel copyWith({
    int? id,
    String? title,
    String? author,
    String? url,
    bool? isInBookshelf,
    String? coverUrl,
    String? description,
    String? backgroundSetting,
    String? coverMediaId,
    int? lastReadChapterIndex,
    double? readingProgress,
  }) {
    return Novel(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      url: url ?? this.url,
      isInBookshelf: isInBookshelf ?? this.isInBookshelf,
      coverUrl: coverUrl ?? this.coverUrl,
      description: description ?? this.description,
      backgroundSetting: backgroundSetting ?? this.backgroundSetting,
      coverMediaId: coverMediaId ?? this.coverMediaId,
      lastReadChapterIndex:
          lastReadChapterIndex ?? this.lastReadChapterIndex,
      readingProgress: readingProgress ?? this.readingProgress,
    );
  }
}

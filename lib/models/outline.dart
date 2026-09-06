/// 大纲数据模型
/// 用于存储小说的完整大纲，一本书对应一个大纲
class Outline {
  final int? id;
  final String novelUrl;
  final String title;
  final String content; // JSON或Markdown格式的大纲内容
  final DateTime createdAt;
  final DateTime updatedAt;

  const Outline({
    this.id,
    required this.novelUrl,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 转换为Map，用于数据库存储
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'novel_url': novelUrl,
      'title': title,
      'content': content,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// 从Map创建实例，用于从数据库读取
  factory Outline.fromMap(Map<String, dynamic> map) {
    return Outline(
      id: map['id'] as int?,
      novelUrl: map['novel_url'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  /// 创建副本
  Outline copyWith({
    int? id,
    String? novelUrl,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Outline(
      id: id ?? this.id,
      novelUrl: novelUrl ?? this.novelUrl,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'Outline(id: $id, novelUrl: $novelUrl, title: $title, '
        'createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}

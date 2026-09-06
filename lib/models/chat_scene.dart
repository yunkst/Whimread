/// 聊天场景数据模型
///
/// 用于存储角色聊天的预设场景信息
class ChatScene {
  final int? id;
  final String title; // 场景标题
  final String content; // 场景内容描述
  final DateTime createdAt; // 创建时间
  final DateTime? updatedAt; // 更新时间

  ChatScene({
    this.id,
    required this.title,
    required this.content,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 将对象转换为Map，用于数据库存储
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  /// 从Map创建对象，用于数据库读取
  factory ChatScene.fromMap(Map<String, dynamic> map) {
    return ChatScene(
      id: map['id']?.toInt(),
      title: map['title'] as String,
      content: map['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : null,
    );
  }

  /// 创建对象的副本，用于编辑功能
  ChatScene copyWith({
    int? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatScene(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'ChatScene(id: $id, title: $title, content: ${content.substring(0, content.length > 20 ? 20 : content.length)}..., createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ChatScene &&
        other.id == id &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        title.hashCode ^
        content.hashCode ^
        createdAt.hashCode ^
        updatedAt.hashCode;
  }
}

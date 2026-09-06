/// AI 对话会话（chat_sessions 表）
///
/// 一个会话对应一个 scenarioId 下的一轮连续对话，可被浏览 / 切换 / 重命名 / 删除。
/// 注意：旧 Agent 聊天窗口没有 session 概念，本表对应的旧数据不需要迁移（用户决策）。
library;

import '../utils/format_utils.dart';

class ChatSession {
  final int? id;
  final String scenarioId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? currentNovelId;
  final String? currentNovelTitle;

  ChatSession({
    this.id,
    required this.scenarioId,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.currentNovelId,
    this.currentNovelTitle,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'scenarioId': scenarioId,
      'title': title,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'currentNovelId': currentNovelId,
      'currentNovelTitle': currentNovelTitle,
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    final createdMs = map['createdAt'];
    final updatedMs = map['updatedAt'];
    return ChatSession(
      id: map['id'] as int?,
      scenarioId: map['scenarioId'] as String,
      title: map['title'] as String? ?? '',
      createdAt: createdMs is int
          ? DateTime.fromMillisecondsSinceEpoch(createdMs)
          : DateTime.now(),
      updatedAt: updatedMs is int
          ? DateTime.fromMillisecondsSinceEpoch(updatedMs)
          : DateTime.now(),
      currentNovelId: map['currentNovelId'] as int?,
      currentNovelTitle: map['currentNovelTitle'] as String?,
    );
  }

  ChatSession copyWith({
    int? id,
    String? scenarioId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? currentNovelId,
    String? currentNovelTitle,
    bool clearCurrentNovel = false,
  }) {
    return ChatSession(
      id: id ?? this.id,
      scenarioId: scenarioId ?? this.scenarioId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currentNovelId: clearCurrentNovel ? null : (currentNovelId ?? this.currentNovelId),
      currentNovelTitle:
          clearCurrentNovel ? null : (currentNovelTitle ?? this.currentNovelTitle),
    );
  }

  /// 列表展示用标题，空标题回退到「新对话 YYYY/MM/DD HH:mm」
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    return '新对话 ${FormatUtils.formatDateTimeShort(updatedAt)}';
  }

  @override
  String toString() =>
      'ChatSession(id: $id, scenarioId: $scenarioId, title: $title, '
      'updatedAt: $updatedAt)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatSession &&
        other.id == id &&
        other.scenarioId == scenarioId &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.currentNovelId == currentNovelId &&
        other.currentNovelTitle == currentNovelTitle;
  }

  @override
  int get hashCode => Object.hash(
        id,
        scenarioId,
        title,
        createdAt,
        updatedAt,
        currentNovelId,
        currentNovelTitle,
      );
}

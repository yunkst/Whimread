import 'dart:convert';
import 'saved_tag_group.dart';

/// 用户提示词历史记录模型
class PromptHistory {
  final int? id;
  final String promptText;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 关联的标签组快照（来自历史记录时的选择状态）
  final List<SavedTagGroup> tagGroups;

  const PromptHistory({
    this.id,
    required this.promptText,
    required this.createdAt,
    required this.updatedAt,
    this.tagGroups = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'prompt_text': promptText,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'tag_group_ids': jsonEncode(tagGroups.map((t) => t.toJson()).toList()),
      };

  factory PromptHistory.fromMap(Map<String, dynamic> map) => PromptHistory(
        id: map['id'] as int?,
        promptText: map['prompt_text'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        tagGroups: _parseTagGroups(map['tag_group_ids']),
      );

  static List<SavedTagGroup> _parseTagGroups(dynamic raw) {
    if (raw == null || (raw is String && raw.isEmpty)) return [];
    try {
      final list = jsonDecode(raw as String) as List;
      return list
          .map((e) => SavedTagGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  PromptHistory copyWith({
    int? id,
    String? promptText,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<SavedTagGroup>? tagGroups,
  }) =>
      PromptHistory(
        id: id ?? this.id,
        promptText: promptText ?? this.promptText,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        tagGroups: tagGroups ?? this.tagGroups,
      );
}

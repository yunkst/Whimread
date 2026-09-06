import 'relation_type.dart';

/// 角色关系 v2(区间模型)。
///
/// 关系 (source -> target, relationType) 表示
/// "A 是 B 的 [relationType.forward]"。
///
/// [startChapter]/[endChapter] 为章节 index(0-based),定义关系生效区间:
/// 在时间轴某章节 c 下,关系生效当且仅当 `startChapter <= c` 且
/// `endChapter == null || endChapter >= c`。
class CharacterRelationship {
  final int? id;
  final int sourceCharacterId;
  final int targetCharacterId;
  final RelationType relationType;
  final int strength; // 1-5,默认 3
  final int startChapter; // 0-based,必填
  final int? endChapter; // 0-based,可空=持续至今
  final String? description;
  final String novelUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CharacterRelationship({
    this.id,
    required this.sourceCharacterId,
    required this.targetCharacterId,
    required this.relationType,
    this.strength = 3,
    required this.startChapter,
    this.endChapter,
    this.description,
    required this.novelUrl,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'source_character_id': sourceCharacterId,
        'target_character_id': targetCharacterId,
        'relation_type': relationType.name,
        'strength': strength,
        'start_chapter': startChapter,
        'end_chapter': endChapter,
        'description': description,
        'novel_url': novelUrl,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };

  factory CharacterRelationship.fromMap(Map<String, dynamic> map) {
    return CharacterRelationship(
      id: map['id']?.toInt(),
      sourceCharacterId: map['source_character_id'] as int,
      targetCharacterId: map['target_character_id'] as int,
      relationType:
          RelationType.values.byName(map['relation_type'] as String),
      strength: (map['strength'] as int?) ?? 3,
      startChapter: map['start_chapter'] as int,
      endChapter: map['end_chapter'] as int?,
      description: map['description'] as String?,
      novelUrl: map['novel_url'] as String,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
    );
  }

  CharacterRelationship copyWith({
    int? id,
    int? sourceCharacterId,
    int? targetCharacterId,
    RelationType? relationType,
    int? strength,
    int? startChapter,
    int? endChapter,
    String? description,
    String? novelUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      CharacterRelationship(
        id: id ?? this.id,
        sourceCharacterId: sourceCharacterId ?? this.sourceCharacterId,
        targetCharacterId: targetCharacterId ?? this.targetCharacterId,
        relationType: relationType ?? this.relationType,
        strength: strength ?? this.strength,
        startChapter: startChapter ?? this.startChapter,
        // 注意:用 ?? 无法把 endChapter 显式设回 null。区间模型里关系通常
        // 只从 null 变为有值(结束),此处满足当前需求;若需显式清空,另加
        // sentinel 或专用方法。
        endChapter: endChapter ?? this.endChapter,
        description: description ?? this.description,
        novelUrl: novelUrl ?? this.novelUrl,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  @override
  String toString() =>
      'CharacterRelationship($sourceCharacterId->$targetCharacterId, '
      '${relationType.name}, §$startChapter-${endChapter ?? "∞"})';
}

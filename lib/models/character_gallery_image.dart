/// 角色图集条目
///
/// `character_images` 表（v50）的一行：角色 ↔ 媒体的多对多之外的一对多
/// 关联。mediaId 指向 media_items（本地生成/上传共享），删除图集条目
/// 只删关联行，不级联删媒体文件（同一 mediaId 可能还被头像/聊天引用）。
library;

class CharacterGalleryImage {
  final int? id;
  final int characterId;
  final String mediaId;
  final int sort;
  final DateTime createdAt;

  const CharacterGalleryImage({
    this.id,
    required this.characterId,
    required this.mediaId,
    this.sort = 0,
    required this.createdAt,
  });

  factory CharacterGalleryImage.fromMap(Map<String, dynamic> map) =>
      CharacterGalleryImage(
        id: map['id'] as int?,
        characterId: map['characterId'] as int,
        mediaId: map['mediaId'] as String,
        sort: (map['sort'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as int?) ?? 0),
      );

  Map<String, dynamic> toMap() => {
        'characterId': characterId,
        'mediaId': mediaId,
        'sort': sort,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  CharacterGalleryImage copyWith({
    int? id,
    int? characterId,
    String? mediaId,
    int? sort,
    DateTime? createdAt,
  }) =>
      CharacterGalleryImage(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        mediaId: mediaId ?? this.mediaId,
        sort: sort ?? this.sort,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  String toString() =>
      'CharacterGalleryImage(id: $id, characterId: $characterId, '
      'mediaId: $mediaId, sort: $sort)';
}

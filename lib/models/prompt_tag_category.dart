class PromptTagCategory {
  final int? id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PromptTagCategory({
    this.id,
    required this.name,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory PromptTagCategory.fromMap(Map<String, dynamic> map) =>
      PromptTagCategory(
        id: map['id'] as int?,
        name: map['name'] as String,
        sortOrder: (map['sort_order'] as int?) ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );

  PromptTagCategory copyWith({
    int? id,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PromptTagCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

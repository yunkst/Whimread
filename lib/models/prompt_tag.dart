class PromptTag {
  final int? id;
  final int categoryId;
  final String name;
  final String reason; // 使用场景描述（简短一句话，说明何时该用这个标签）
  final String promptText;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PromptTag({
    this.id,
    required this.categoryId,
    required this.name,
    this.reason = '',
    required this.promptText,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'reason': reason,
        'prompt_text': promptText,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory PromptTag.fromMap(Map<String, dynamic> map) => PromptTag(
        id: map['id'] as int?,
        categoryId: map['category_id'] as int,
        name: map['name'] as String,
        reason: (map['reason'] as String?) ?? '',
        promptText: map['prompt_text'] as String,
        sortOrder: (map['sort_order'] as int?) ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );

  PromptTag copyWith({
    int? id,
    int? categoryId,
    String? name,
    String? reason,
    String? promptText,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PromptTag(
        id: id ?? this.id,
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        reason: reason ?? this.reason,
        promptText: promptText ?? this.promptText,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

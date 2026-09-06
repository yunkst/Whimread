/// LLM 配置模型
///
/// 一个 LLM 配置包含名称、API URL、API Key、默认模型等信息。
/// 用户可创建多个配置，其中最多一个为默认配置（isDefault = true）。
library;

class LlmConfig {
  final int? id;
  final String name;
  final String apiUrl;
  final String apiKey;
  final String model;
  final bool isDefault;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LlmConfig({
    this.id,
    required this.name,
    required this.apiUrl,
    required this.apiKey,
    this.model = '',
    this.isDefault = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'api_url': apiUrl,
        'api_key': apiKey,
        'model': model,
        'is_default': isDefault ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory LlmConfig.fromMap(Map<String, dynamic> map) => LlmConfig(
        id: map['id'] as int?,
        name: map['name'] as String,
        apiUrl: map['api_url'] as String,
        apiKey: (map['api_key'] as String?) ?? '',
        model: (map['model'] as String?) ?? '',
        isDefault: (map['is_default'] as int?) == 1,
        sortOrder: (map['sort_order'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['updated_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
      );

  /// 生成一个用于「复制」的无 id 副本。
  ///
  /// 必须用这个方法而不是 `copyWith(id: null)`：copyWith 用 `id ?? this.id`
  /// 处理可空字段，传 null 会沿用原 id，导致 [LlmConfigRepository.save] 走
  /// update 分支把原配置覆盖掉（复制 bug 的根因）。这里走构造函数，强制 id 为 null。
  LlmConfig duplicate({String suffix = ' (副本)'}) {
    final now = DateTime.now();
    return LlmConfig(
      name: '$name$suffix',
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      isDefault: false,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  LlmConfig copyWith({
    int? id,
    String? name,
    String? apiUrl,
    String? apiKey,
    String? model,
    bool? isDefault,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      LlmConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        apiUrl: apiUrl ?? this.apiUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        isDefault: isDefault ?? this.isDefault,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() => 'LlmConfig(id: $id, name: $name, apiUrl: $apiUrl, model: $model, isDefault: $isDefault)';
}

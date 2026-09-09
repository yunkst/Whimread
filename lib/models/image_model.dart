/// 生图模型
///
/// 用户导入的本地 SD 模型（或映射的后端 ComfyUI 工作流）及其元数据。
/// - [name] 全局唯一，agent 作为 create_images 的 modelName key
/// - [description] / [tags] 是模型的"特点"，agent 据此为用户需求挑选模型
/// - [backendType] 决定 create_images 路由到哪个 ImageGenerationBackend
library;

import 'dart:convert';

/// 生图后端类型
///
/// 与数据库 backend_type 列的字符串字面量一一对应；新增后端（如 qnn）时
/// 在此扩展枚举 + [dbName] / [parse] 两个映射即可。
///
/// 注：旧版本曾包含 `comfyui`（异步任务后端），现已移除——生图完全走
/// 客户端本地引擎。存量数据中 backend_type='comfyui' 的行 [parse] 时
/// 会回退到 [ImageModelBackendType.localSd]（file_path 为空 → 校验失败
/// 提示用户重新导入），实现平滑迁移。
enum ImageModelBackendType {
  /// 本地 sd.cpp 引擎（dart:ffi，端侧 CPU 推理）
  localSd;

  /// 数据库 backend_type 列名
  String get dbName => 'local_sd';

  static ImageModelBackendType parse(String? name) {
    switch (name) {
      case 'local_sd':
        return ImageModelBackendType.localSd;
      default:
        // 兼容旧值（如已下线的 'comfyui'）：回退到本地引擎
        return ImageModelBackendType.localSd;
    }
  }

  /// UI 展示名
  String get displayName => '本地引擎';
}

class ImageModel {
  final int? id;

  /// 用户自定义名字，全局唯一（agent 用作 modelName key）
  final String name;

  /// 自由文本特点描述（agent 推理选型依据）
  final String description;

  /// 结构化标签（如 古风 / 写实 / 赛博朋克），jsonEncode 存单列
  final List<String> tags;

  final ImageModelBackendType backendType;

  /// 导入的模型文件绝对路径（local_sd 必填；comfyui 为空）
  final String filePath;

  /// 模型文件字节数（UI 展示用）
  final int fileSize;

  /// 可选预览图，关联 media_items.media_id
  final String? previewMediaId;

  /// 出图默认参数（agent 未显式指定时采用）
  final int defaultWidth;
  final int defaultHeight;
  final int defaultSteps;
  final double defaultCfg;

  final bool isEnabled;
  final bool isDefault;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ImageModel({
    this.id,
    required this.name,
    this.description = '',
    this.tags = const [],
    this.backendType = ImageModelBackendType.localSd,
    this.filePath = '',
    this.fileSize = 0,
    this.previewMediaId,
    this.defaultWidth = 512,
    this.defaultHeight = 512,
    this.defaultSteps = 20,
    this.defaultCfg = 7.0,
    this.isEnabled = true,
    this.isDefault = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'tags': jsonEncode(tags),
        'backend_type': backendType.dbName,
        'file_path': filePath,
        'file_size': fileSize,
        'preview_media_id': previewMediaId,
        'default_width': defaultWidth,
        'default_height': defaultHeight,
        'default_steps': defaultSteps,
        'default_cfg': defaultCfg,
        'is_enabled': isEnabled ? 1 : 0,
        'is_default': isDefault ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ImageModel.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'] as String?;
    List<String> tags;
    if (rawTags == null || rawTags.isEmpty) {
      tags = const [];
    } else {
      try {
        tags = (jsonDecode(rawTags) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {
        tags = const [];
      }
    }
    return ImageModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: (map['description'] as String?) ?? '',
      tags: tags,
      backendType: ImageModelBackendType.parse(map['backend_type'] as String?),
      filePath: (map['file_path'] as String?) ?? '',
      fileSize: (map['file_size'] as int?) ?? 0,
      previewMediaId: map['preview_media_id'] as String?,
      defaultWidth: (map['default_width'] as int?) ?? 512,
      defaultHeight: (map['default_height'] as int?) ?? 512,
      defaultSteps: (map['default_steps'] as int?) ?? 20,
      defaultCfg: (map['default_cfg'] as double?) ?? 7.0,
      isEnabled: (map['is_enabled'] as int?) != 0,
      isDefault: (map['is_default'] as int?) == 1,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  /// 生成一个用于「复制」的无 id 副本。
  ///
  /// 必须用这个方法而不是 `copyWith(id: null)`：copyWith 用 `id ?? this.id`
  /// 处理可空字段，传 null 会沿用原 id，导致 save 走 update 分支覆盖原记录
  /// （与 LlmConfig.duplicate 注释同一根因）。名字加后缀避免唯一索引冲突。
  ImageModel duplicate({String suffix = ' (副本)'}) {
    final now = DateTime.now();
    return ImageModel(
      name: '$name$suffix',
      description: description,
      tags: List.of(tags),
      backendType: backendType,
      filePath: filePath,
      fileSize: fileSize,
      previewMediaId: previewMediaId,
      defaultWidth: defaultWidth,
      defaultHeight: defaultHeight,
      defaultSteps: defaultSteps,
      defaultCfg: defaultCfg,
      isEnabled: isEnabled,
      isDefault: false,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  ImageModel copyWith({
    int? id,
    String? name,
    String? description,
    List<String>? tags,
    ImageModelBackendType? backendType,
    String? filePath,
    int? fileSize,
    String? previewMediaId,
    int? defaultWidth,
    int? defaultHeight,
    int? defaultSteps,
    double? defaultCfg,
    bool? isEnabled,
    bool? isDefault,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ImageModel(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        tags: tags ?? this.tags,
        backendType: backendType ?? this.backendType,
        filePath: filePath ?? this.filePath,
        fileSize: fileSize ?? this.fileSize,
        previewMediaId: previewMediaId ?? this.previewMediaId,
        defaultWidth: defaultWidth ?? this.defaultWidth,
        defaultHeight: defaultHeight ?? this.defaultHeight,
        defaultSteps: defaultSteps ?? this.defaultSteps,
        defaultCfg: defaultCfg ?? this.defaultCfg,
        isEnabled: isEnabled ?? this.isEnabled,
        isDefault: isDefault ?? this.isDefault,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() => 'ImageModel(id: $id, name: $name, '
      'backendType: ${backendType.dbName}, isDefault: $isDefault)';
}

/// 生图模型
///
/// 用户导入的本地 SD 模型及其元数据。
/// - [name] 全局唯一，agent 作为 create_images 的 modelName key
/// - [description] / [tags] 是模型的"特点"，agent 据此为用户需求挑选模型
/// - [backendType] 决定 create_images 路由到哪个 ImageGenerationBackend
/// - [status] 生命周期（downloading→converting→ready），半成品对 agent 不可见
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
}

/// 生图模型生命周期状态
///
/// 完整链路：downloading ─pause→ paused        （下载进度 progress）
///              │                 ▲resume
///              ▼ 自动            │
///           converting ─失败→ failed ─retry─┐
///              │ 成功                        │
///              ▼                            ▼
///            ready                        （可删除）
///
/// 仅 [ImageModelStatus.ready] 的模型会被 [ImageModelRepository.getEnabled]
/// 返回——agent 永远看不到半成品。
enum ImageModelStatus {
  downloading,
  paused,
  converting,
  ready,
  failed;

  /// 数据库 status 列名
  String get dbName {
    switch (this) {
      case ImageModelStatus.downloading:
        return 'downloading';
      case ImageModelStatus.paused:
        return 'paused';
      case ImageModelStatus.converting:
        return 'converting';
      case ImageModelStatus.ready:
        return 'ready';
      case ImageModelStatus.failed:
        return 'failed';
    }
  }

  static ImageModelStatus parse(String? name) {
    switch (name) {
      case 'downloading':
        return ImageModelStatus.downloading;
      case 'paused':
        return ImageModelStatus.paused;
      case 'converting':
        return ImageModelStatus.converting;
      case 'failed':
        return ImageModelStatus.failed;
      case 'ready':
      default:
        // 兼容：空值/未知值一律视为 ready（存量行语义）
        return ImageModelStatus.ready;
    }
  }

  /// 是否进行中（UI 据此显示进度条/取消按钮）
  bool get isActive =>
      this == ImageModelStatus.downloading ||
      this == ImageModelStatus.converting;

  /// 是否已就绪（agent 可用）
  bool get isReady => this == ImageModelStatus.ready;
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

  /// 导入的模型文件绝对路径（local_sd 必填）
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

  // ===== 生命周期 / 预设 / 来源（v42）=====

  /// 负向提示词预设（LLM 只传正向 prompt，负向随模型走）
  final String negativePrompt;

  /// 生命周期状态（downloading/paused/converting/ready/failed）
  final ImageModelStatus status;

  /// 下载/转换进度 0-100
  final int progress;

  /// 文件直链（断点续传/重试用）
  final String sourceUrl;

  /// 介绍页 URL（下载来源页面）
  final String sourcePageUrl;

  /// 介绍页文本快照（≤50KB，AI 填充 description/tags 的原料）
  final String pageSnapshot;

  /// 失败原因摘要（status=failed 时展示）
  final String errorMessage;

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
    this.negativePrompt = '',
    this.status = ImageModelStatus.ready,
    this.progress = 0,
    this.sourceUrl = '',
    this.sourcePageUrl = '',
    this.pageSnapshot = '',
    this.errorMessage = '',
  });

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
      negativePrompt: (map['negative_prompt'] as String?) ?? '',
      status: ImageModelStatus.parse(map['status'] as String?),
      progress: (map['progress'] as int?) ?? 0,
      sourceUrl: (map['source_url'] as String?) ?? '',
      sourcePageUrl: (map['source_page_url'] as String?) ?? '',
      pageSnapshot: (map['page_snapshot'] as String?) ?? '',
      errorMessage: (map['error_message'] as String?) ?? '',
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
    String? negativePrompt,
    ImageModelStatus? status,
    int? progress,
    String? sourceUrl,
    String? sourcePageUrl,
    String? pageSnapshot,
    String? errorMessage,
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
        negativePrompt: negativePrompt ?? this.negativePrompt,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        sourcePageUrl: sourcePageUrl ?? this.sourcePageUrl,
        pageSnapshot: pageSnapshot ?? this.pageSnapshot,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  @override
  String toString() => 'ImageModel(id: $id, name: $name, '
      'backendType: ${backendType.dbName}, isDefault: $isDefault)';
}

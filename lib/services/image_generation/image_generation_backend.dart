/// 生图后端抽象层
///
/// 当前唯一实现是 [LocalSdCppBackend]（端侧 sd.cpp 推理）。抽象层的意义：
/// 未来接入 NPU（qnn）等新后端时，MediaExecutor 与 UI 无需改动——
/// 后端负责完成"提交"和"让图最终能被 resolve 出来"的全过程，返回的
/// mediaId 已经是 MediaProxy 已登记的句柄（本地生成的 bytes 直接写入
/// MediaStore，UI 一次 resolve 即可见）。
library;

import '../../models/image_model.dart';

/// 生图请求
class ImageGenerationRequest {
  /// 要用的模型（必填；其 backendType 决定路由到哪个后端）
  final ImageModel model;

  /// 正向提示词
  final String prompt;

  /// 负向提示词（可选；仅模型对应后端支持时生效）
  final String? negativePrompt;

  /// 生成张数（1-4，由调用方限幅）
  final int count;

  /// 出图参数；null 表示沿用 [ImageModel] 的默认值
  final int? width;
  final int? height;
  final int? steps;
  final double? cfg;
  final int? seed;

  const ImageGenerationRequest({
    required this.model,
    required this.prompt,
    this.negativePrompt,
    this.count = 1,
    this.width,
    this.height,
    this.steps,
    this.cfg,
    this.seed,
  });

  int get effectiveWidth => width ?? model.defaultWidth;
  int get effectiveHeight => height ?? model.defaultHeight;
  int get effectiveSteps => steps ?? model.defaultSteps;
  double get effectiveCfg => cfg ?? model.defaultCfg;
}

/// 生图提交结果
///
/// [mediaIds] 已通过 MediaProxy 登记，UI 可直接 [MediaProxy.resolve] 取图。
/// 本地引擎生成的 bytes 在提交时即已写入 MediaStore，UI 一次 resolve 即可显示。
class ImageGenerationResult {
  final List<String> mediaIds;
  final String modelName;

  const ImageGenerationResult({
    required this.mediaIds,
    required this.modelName,
  });
}

/// 生图后端抽象接口
abstract class ImageGenerationBackend {
  /// 后端唯一标识（对应 ImageModel.backendType.dbName）
  String get id;

  /// 是否支持指定 backendType
  bool supports(ImageModelBackendType type);

  /// 校验模型在本后端是否可用（local_sd 检查文件存在且头 magic 正确）
  ///
  /// 返回 null 表示通过；返回非 null 字符串作为 UI 错误文案
  Future<String?> validate(ImageModel model);

  /// 提交生图请求。
  ///
  /// [onProgress] 步进回调：本地引擎去噪循环每步触发一次，
  /// UI 据此渲染进度/预览。
  Future<ImageGenerationResult> submit(
    ImageGenerationRequest request, {
    void Function(int step, int total)? onProgress,
  });

  /// 释放后端持有的资源（FFI handle 等）；stub 阶段无操作
  Future<void> dispose();
}
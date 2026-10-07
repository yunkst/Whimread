/// 生图统一提交门面
///
/// [generate] 是全 App 唯一的生图入口（Agent 工具 create_images 与文字
/// 游戏 create_scene_image 共用）：收敛模型选取（三级回退）、请求构造
/// （负向提示词取模型预设、count 限幅、aspect_ratio 校验）、后端提交与
/// 异常→结构化错误码映射，四处只此一份实现。
///
/// 同步语义：调用方 await 到生成完成（本机引擎数十秒），结果里的
/// mediaId 已登记进 MediaStore，UI 一次 resolve 即可见。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/image_model_providers.dart'
    show imageModelRepositoryProvider;
import 'image_generation_backend.dart';
import 'image_generation_providers.dart';
import 'image_model_picker.dart';

/// 出图参数覆盖（**仅模型测试面板使用**；业务路径走模型预设）
///
/// 收敛进一个对象后，业务调用方（create_images / create_scene_image）的
/// 签名只留业务参数，出图调参不再混进主签名——测试面板的可调项以后增减也
/// 不影响业务面。null 字段 = 沿用模型预设。
class GenerationOverrides {
  final int? steps;
  final double? cfg;
  final int? seed;
  final String? negativePrompt;

  const GenerationOverrides({
    this.steps,
    this.cfg,
    this.seed,
    this.negativePrompt,
  });
}

/// 一次生成尝试的结果
class ImageGenerationOutcome {
  /// 成功时非空（mediaIds 已登记，可直接渲染）
  final ImageGenerationResult? result;

  /// 失败时的结构化错误 JSON（含 error/message，可能含引导字段）；
  /// 调用方直接 jsonEncode 后作为工具结果返回
  final Map<String, dynamic>? errorJson;

  const ImageGenerationOutcome.success(ImageGenerationResult this.result)
      : errorJson = null;

  const ImageGenerationOutcome.failure(Map<String, dynamic> this.errorJson)
      : result = null;

  bool get ok => result != null;
}

class ImageGenerationService {
  final Ref _ref;

  ImageGenerationService(this._ref);

  /// aspect_ratio 合法格式："宽:高" 数字比例（如 1:1、3:4、16:9）
  static final RegExp _aspectRatioPattern =
      RegExp(r'^\s*\d{1,4}\s*:\s*\d{1,4}\s*$');

  /// 提交一次生图。
  ///
  /// [modelName] 为 null 时走三级回退（默认模型 → 第一个启用模型）；
  /// [negativePrompt] 来自模型预设（用户在管理页配置），LLM 不传；
  /// [onProgress] 透传引擎采样步进（step 从 1 计，模型测试页渲染进度用）。
  Future<ImageGenerationOutcome> generate({
    String? modelName,
    required String prompt,
    int count = 1,
    String? aspectRatio,
    void Function(int step, int total)? onProgress,

    /// 出图参数覆盖（仅模型测试面板传；null = 沿用模型预设）
    GenerationOverrides? overrides,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return const ImageGenerationOutcome.failure({
        'error': 'empty_prompt',
        'message': 'prompt 不能为空',
      });
    }
    if (aspectRatio != null &&
        aspectRatio.isNotEmpty &&
        !_aspectRatioPattern.hasMatch(aspectRatio)) {
      return const ImageGenerationOutcome.failure({
        'error': 'invalid_aspect_ratio',
        'message': 'aspect_ratio 需为 "宽:高" 格式的比例（如 "1:1"、"3:4"、"16:9"）。',
      });
    }

    final repo = _ref.read(imageModelRepositoryProvider);
    final pick = await pickImageModel(repo, modelName: modelName);
    if (pick.errorJson != null) {
      return ImageGenerationOutcome.failure(pick.errorJson!);
    }
    final model = pick.model!;

    final backend =
        _ref.read(imageGenerationBackendByTypeProvider(model.backendType));
    // 比例回退：调用方显式传值 → 模型默认预设（仅 SDXL 包生效，由后端门控）。
    // 模型预设是编辑对话框下拉选的；万一有脏值（不匹配 宽:高）直接忽略。
    final String? ratio;
    if (aspectRatio != null && aspectRatio.isNotEmpty) {
      ratio = aspectRatio;
    } else if (model.defaultAspectRatio.isNotEmpty &&
        _aspectRatioPattern.hasMatch(model.defaultAspectRatio)) {
      ratio = model.defaultAspectRatio;
    } else {
      ratio = null;
    }
    try {
      final result = await backend.submit(ImageGenerationRequest(
        model: model,
        prompt: trimmed,
        // 负向提示词：覆盖（测试面板）→ 模型预设（用户配置）
        negativePrompt: overrides?.negativePrompt ??
            (model.negativePrompt.isEmpty ? null : model.negativePrompt),
        count: count.clamp(1, 4),
        aspectRatio: ratio,
        steps: overrides?.steps,
        cfg: overrides?.cfg,
        seed: overrides?.seed,
      ));
      return ImageGenerationOutcome.success(result);
    } on LocalEngineNotReadyException catch (e) {
      return ImageGenerationOutcome.failure({
        'error': 'engine_not_ready',
        'message': e.message,
      });
    } catch (e, st) {
      // 引入 logger 会造成 providers ↔ services 反向依赖，失败详情由
      // 调用方记日志；这里只归一错误码
      assert(() {
        // debug 下保留排查线索
        // ignore: avoid_print
        print('生图失败（model=${model.name}）: $e\n$st');
        return true;
      }());
      return ImageGenerationOutcome.failure({
        'error': 'generation_failed',
        'message': '生图失败：$e',
      });
    }
  }
}

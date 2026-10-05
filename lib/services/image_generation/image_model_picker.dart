/// 生图模型共享选取器
///
/// 「显式 modelName → 默认模型 → 第一个启用模型」的三级回退逻辑，
/// 原 media_executor.createImages 私有实现，文字游戏异步生图
/// 文字游戏场景生图（create_scene_image）需要同款行为，故抽取为共享函数。
/// 错误以可直接返回给 LLM 的 JSON Map 表达（与工具错误约定一致）。
library;

import '../../models/image_model.dart';
import '../../repositories/image_model_repository.dart';

/// 选取结果：model 与 errorJson 二选一
class ImageModelPickResult {
  final ImageModel? model;
  final Map<String, dynamic>? errorJson;

  const ImageModelPickResult.ok(this.model) : errorJson = null;
  const ImageModelPickResult.error(this.errorJson) : model = null;
}

/// 按三级回退选取生图模型
Future<ImageModelPickResult> pickImageModel(
  ImageModelRepository repo, {
  String? modelName,
}) async {
  if (modelName != null && modelName.isNotEmpty) {
    final model = await repo.getByName(modelName);
    if (model == null) {
      final available = (await repo.getEnabled()).map((m) => m.name).toList();
      return ImageModelPickResult.error({
        'error': 'model_not_found',
        'message': '生图模型 "$modelName" 不存在或未启用。'
            '请先查看可用模型列表再选择。'
            '可用模型：${available.isEmpty ? "（无）" : available.join("、")}',
      });
    }
    if (!model.isEnabled) {
      return ImageModelPickResult.error({
        'error': 'model_disabled',
        'message': '生图模型 "${model.name}" 已被用户停用，请改用其他模型。',
      });
    }
    return ImageModelPickResult.ok(model);
  }
  // 三级回退：显式名 → 默认 → 第一个启用模型。默认模型须过启用校验——
  // repo.getDefault() 只看 is_default 标记，被用户停用/未就绪的默认模型
  // 若不校验会直接选中，生成必败（回退链失效）
  final enabled = await repo.getEnabled();
  final defaultModel = await repo.getDefault();
  final model = (defaultModel != null && defaultModel.isEnabled)
      ? defaultModel
      : (enabled.isEmpty ? null : enabled.first);
  if (model == null) {
    return const ImageModelPickResult.error({
      'error': 'no_models_available',
      'message': '还没有可用的生图模型。请引导用户到「设置 → 生图模型管理」'
          '导入 .gguf 模型或添加 Local Dream 设备模型后再试。',
    });
  }
  return ImageModelPickResult.ok(model);
}

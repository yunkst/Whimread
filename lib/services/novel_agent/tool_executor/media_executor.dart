/// 文生图子执行器 — list_text2img_models / create_images
///
/// 依赖 ImageModelRepository（本地模型元数据）、LocalSdCppBackend
/// （客户端本地引擎生图）、MediaProxy（媒体登记由后端完成）。
///
/// 注：图生视频（create_image_to_video）依赖的 ComfyUI 后端已随
/// "生图完全客户端化" 移除，该工具已从 AgentTools 注销。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/image_model_providers.dart';
import '../../../models/image_model.dart';
import '../../logger_service.dart';
import '../../image_generation/image_generation_backend.dart';
import '../../image_generation/image_generation_providers.dart';
import '../../image_generation/local_sd_backend.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../tool_executor_helpers.dart';

class MediaExecutor with ToolExecutorHelpers {
  MediaExecutor(this.ref);
  @override
  final Ref ref;

  /// 列出用户管理的生图模型（image_models 表中已启用的条目）。
  ///
  /// 返回 [{name, description, tags, isDefault, promptSkill, backendType}]，
  /// name 作为 create_images 的 modelName 参数；description/tags 是模型的
  /// "特点"，LLM 据此为用户需求挑选最匹配的模型；promptSkill（描述+标签摘要）
  /// 是提示词写作建议。
  Future<String> listText2ImgModels(Map<String, dynamic> args) async {
    final repo = ref.read(imageModelRepositoryProvider);
    try {
      final models = await repo.getEnabled();
      LoggerService.instance.i('列出生图模型: ${models.length} 个',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'list_text2img_models']);

      final defaultModel = models
          .where((m) => m.isDefault)
          .firstOrNull ??
          (models.isEmpty ? null : models.first);

      return jsonEncode({
        'models': models
            .map((m) => {
                  'name': m.name,
                  'description': m.description,
                  'tags': m.tags,
                  'isDefault': m.isDefault,
                  'promptSkill': _buildPromptSkill(m),
                  'backendType': m.backendType.dbName,
                })
            .toList(),
        'count': models.length,
        if (defaultModel != null) 'defaultModelName': defaultModel.name,
        if (models.isEmpty)
          'message': '还没有可用的生图模型。请引导用户到「设置 → 生图模型管理」'
              '导入 .gguf 模型后再试。',
      });
    } catch (e) {
      LoggerService.instance.e('列出生图模型失败: $e',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'list_text2img_models', 'error']);
      return jsonEncode({
        'error': 'list_models_failed',
        'message': '读取生图模型列表失败：$e',
      });
    }
  }

  /// 提交文生图任务（客户端本地引擎推理）。
  ///
  /// 按 [modelName] 查本地 image_models 表得到模型条目，交给
  /// LocalSdCppBackend 执行端侧推理；生成结果以 mediaId 返回，UI 直接
  /// 通过 MediaProxy.resolve 取本地 bytes。未指定 modelName 时用默认
  /// 模型，再退回第一个启用模型。
  Future<String> createImages(
    Map<String, dynamic> args,
  ) async {
    final parser = ToolArgParser(args);
    final (prompt, promptErr) = parser.requireString('prompt');
    if (promptErr != null) return promptErr;
    final (countRaw, countErr) = parser.optionalInt('count');
    if (countErr != null) return countErr;
    final (modelName, modelNameErr) = parser.nullableString('modelName');
    if (modelNameErr != null) return modelNameErr;

    final count = (countRaw ?? 1).clamp(1, 4);

    // ---------- 选模型 ----------
    final repo = ref.read(imageModelRepositoryProvider);
    ImageModel? model;
    if (modelName != null && modelName.isNotEmpty) {
      model = await repo.getByName(modelName);
      if (model == null) {
        final available = (await repo.getEnabled()).map((m) => m.name).toList();
        return jsonEncode({
          'error': 'model_not_found',
          'message': '生图模型 "$modelName" 不存在或未启用。'
              '请先调用 list_text2img_models 查看可用模型，'
              '从中选择一个 name。可用模型：${available.isEmpty ? "（无）" : available.join("、")}',
        });
      }
      if (!model.isEnabled) {
        return jsonEncode({
          'error': 'model_disabled',
          'message': '生图模型 "${model.name}" 已被用户停用，请改用其他模型。',
        });
      }
    } else {
      final enabled = await repo.getEnabled();
      model = await repo.getDefault() ?? (enabled.isEmpty ? null : enabled.first);
    }
    if (model == null) {
      return jsonEncode({
        'error': 'no_models_available',
        'message': '还没有可用的生图模型。请引导用户到「设置 → 生图模型管理」'
            '导入 .gguf 模型后再试。',
      });
    }

    // ---------- 本地引擎生图 ----------
    final backend = ref.read(imageGenerationBackendByTypeProvider(model.backendType));
    // 负向提示词来自模型预设（用户配置），LLM 不传
    final negativePrompt =
        model.negativePrompt.isEmpty ? null : model.negativePrompt;
    try {
      final result = await backend.submit(
        ImageGenerationRequest(
          model: model,
          prompt: prompt,
          negativePrompt: negativePrompt,
          count: count,
        ),
      );

      LoggerService.instance.i(
          '提交文生图任务: count=$count, model=${model.name}, '
          'hasNegativePrompt=${negativePrompt != null}',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_images']);

      return jsonEncode({
        'success': true,
        'message': '已生成 $count 张图片，画廊将自动展示。',
        'images': result.mediaIds
            .map((mediaId) => {
                  'mediaId': mediaId,
                  'prompt': prompt,
                  'modelName': model!.name,
                  if (negativePrompt != null) 'negativePrompt': negativePrompt,
                })
            .toList(),
        'count': result.mediaIds.length,
      });
    } on LocalEngineNotReadyException catch (e) {
      return jsonEncode({
        'error': 'engine_not_ready',
        'message': e.message,
      });
    } catch (e) {
      LoggerService.instance.e('本地生图失败: $e',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_images', 'error']);
      return jsonEncode({
        'error': 'generation_failed',
        'message': '生图失败：$e',
      });
    }
  }

  /// 由模型的描述 + 标签拼出 promptSkill（提示词写作建议）
  String _buildPromptSkill(ImageModel m) {
    final parts = <String>[];
    if (m.tags.isNotEmpty) parts.add('标签：${m.tags.join('、')}');
    if (m.description.isNotEmpty) {
      final desc = m.description.length > 200
          ? '${m.description.substring(0, 200)}…'
          : m.description;
      parts.add(desc);
    }
    return parts.isEmpty ? '' : parts.join('。');
  }
}
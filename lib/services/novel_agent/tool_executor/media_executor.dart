/// 文生图子执行器 — list_text2img_models / create_images
///
/// 依赖 ImageModelRepository（本地模型元数据）、ImageGenerationService
/// （生图统一门面）、CharacterRepository（create_images 指定 character
/// 时自动入角色图集）。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/character_providers.dart';
import '../../../core/providers/database_providers.dart'
    show characterRepositoryProvider;
import '../../../core/providers/image_model_providers.dart';
import '../../../models/character.dart';
import '../../../models/image_model.dart';
import '../../logger_service.dart';
import '../../image_generation/image_generation_providers.dart';
import '../agent_scenario.dart' show AgentScenarioContext;
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

  /// 提交文生图任务（local_sd 端侧引擎 / local_dream 远程设备）。
  ///
  /// 按 [modelName] 查本地 image_models 表得到模型条目，交给对应
  /// ImageGenerationBackend 执行；生成结果以 mediaId 返回，UI 直接
  /// 通过 MediaProxy.resolve 取本地 bytes。未指定 modelName 时用默认
  /// 模型，再退回第一个启用模型。
  ///
  /// 可选 [character]（当前小说中的角色名）：命中角色后生成的图片全部
  /// 写入该角色图集（character_images，v50）并刷新
  /// characterGalleryProvider，详情页开着时实时可见。
  ///
  /// 注：不自动拼接角色的 facePrompts/bodyPrompts——LLM 已通过
  /// list_characters 拿到这些字段并自行写进 prompt（自动追加会造成
  /// 特征重复与场景冲突，如背影图被强加面部描述）。
  Future<String> createImages(
    Map<String, dynamic> args, {
    AgentScenarioContext? scenarioContext,
  }) async {
    final parser = ToolArgParser(args);
    final (prompt, promptErr) = parser.requireString('prompt');
    if (promptErr != null) return promptErr;
    final (countRaw, countErr) = parser.optionalInt('count');
    if (countErr != null) return countErr;
    final (modelName, modelNameErr) = parser.nullableString('modelName');
    if (modelNameErr != null) return modelNameErr;
    final (characterName, characterErr) = parser.nullableString('character');
    if (characterErr != null) return characterErr;
    final (aspectRatio, aspectErr) = parser.nullableString('aspect_ratio');
    if (aspectErr != null) return aspectErr;

    final count = (countRaw ?? 1).clamp(1, 4);

    // ---------- 角色图集关联（可选） ----------
    final characterRepo = ref.read(characterRepositoryProvider);
    Character? character;
    if (characterName != null && characterName.isNotEmpty) {
      final novelResolve = await resolveCurrentNovelUrl(scenarioContext);
      if (novelResolve.errorJson != null) return jsonEncode(novelResolve.errorJson);
      final resolved =
          await characterRepo.findCharacterByName(novelResolve.url!, characterName);
      if (resolved == null || resolved.id == null) {
        return jsonEncode(guidanceError(
          'character_not_found',
          '当前小说中找不到角色 "$characterName"。'
              '请先调用 list_characters 查看角色列表，按 name 传入。',
          suggestedTool: 'list_characters',
        ));
      }
      character = resolved;
    }

    // ---------- 生图（统一门面：选模型 + 构造请求 + 错误码映射） ----------
    final outcome = await ref.read(imageGenerationServiceProvider).generate(
          modelName: modelName,
          prompt: prompt,
          count: count,
          aspectRatio: aspectRatio,
        );
    if (!outcome.ok) {
      // 失败详情只回给 Agent 的话，日志里什么都没有（历史反馈「生图失败」
      // 就是这么查不到原因的）。用 warning 级——LogReporterService 默认只
      // 上传 warning+，用户反馈时才带得回来。
      LoggerService.instance.w(
        'Agent 生图失败：model=$modelName，'
        'error=${outcome.errorJson?['error']}，'
        'message=${outcome.errorJson?['message']}',
        category: LogCategory.ai,
        tags: const ['image', 'generate', 'agent-failed'],
      );
      return jsonEncode(outcome.errorJson!);
    }
    final result = outcome.result!;

    // ---------- 角色图集入集 ----------
    if (character != null) {
      for (final mediaId in result.mediaIds) {
        await characterRepo.addCharacterImage(character.id!, mediaId);
      }
      ref.invalidate(characterGalleryProvider(character.id!));
    }

    LoggerService.instance.i(
        '提交文生图任务: count=$count, model=${result.modelName}, '
        'character=${character?.name}',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'create_images']);

    return jsonEncode({
      'success': true,
      'message': character != null
          ? '已生成 ${result.mediaIds.length} 张图片，'
              '并已加入角色「${character.name}」的图集。'
          : '已生成 ${result.mediaIds.length} 张图片，画廊将自动展示。',
      'images': result.mediaIds
          .map((mediaId) => {
                'mediaId': mediaId,
                'prompt': prompt,
                'modelName': result.modelName,
                if (character != null) 'character': character.name,
                if (character != null) 'addedToGallery': true,
              })
          .toList(),
      'count': result.mediaIds.length,
    });
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
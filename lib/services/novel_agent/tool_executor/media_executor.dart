/// 文生图 / 图生视频子执行器 — list_text2img_models / create_images /
/// create_image_to_video
///
/// 依赖 ApiServiceWrapper（提交 / 列出任务）、MediaProxy（注册媒体元数据、
/// 解析输入图本地字节）、MediaStore（取字节）。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/services/network_service_providers.dart';
import '../../logger_service.dart';
import '../../media/media_proxy.dart';
import '../../media/media_store.dart';
import '../../media/media_types.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../tool_executor_helpers.dart';

/// 后端 HOST 未配置时的标准错误文案（引导用户去设置）
const String _kBackendUnconfiguredMsg = 'AI 出图是进阶功能，需要本地部署后端服务（含 ComfyUI）。'
    '如已部署，请在「设置 → 进阶服务 → 后端服务配置」填入地址；'
    '未部署可暂时跳过，不影响阅读与 AI 写作。';

/// 后端 HOST 已配置但调用失败时的标准错误文案（前缀带异常细节）
String _kBackendUnreachableMsg(Object e) =>
    '无法连接到后端服务：$e。AI 出图是进阶功能，需要本地部署后端服务（含 ComfyUI）。'
    '请在「设置 → 进阶服务 → 后端服务配置」检查地址，或确认后端与 ComfyUI 已启动。';

/// 三处 catch 共用的错误响应构造：先读 host 决定走哪个分支文案
Future<Map<String, dynamic>> _buildBackendError(Ref ref, Object e) async {
  final host = await ref.read(apiServiceWrapperProvider).getHost();
  final isUnconfigured = host == null || host.isEmpty;
  return {
    'error': 'backend_unavailable',
    'message': isUnconfigured ? _kBackendUnconfiguredMsg : _kBackendUnreachableMsg(e),
  };
}

class MediaExecutor with ToolExecutorHelpers {
  MediaExecutor(this.ref);
  @override
  final Ref ref;

  /// 列出可用文生图工作流（GET /api/models 的 text2img 节）。
  ///
  /// 返回精简字段 [{name, description, isDefault, promptSkill}]，name 作为
  /// create_images 的 modelName 参数；promptSkill 是该工作流的提示词写作技巧
  /// （含正向/负向 prompt 的具体写法建议），可为 null。
  /// 后端/ComfyUI 不可用时返回 error，引导告知用户。
  Future<String> listText2ImgModels(Map<String, dynamic> args) async {
    final api = ref.read(apiServiceWrapperProvider);
    try {
      final models = await api.getText2ImgModels();
      LoggerService.instance.i('列出文生图模型: ${models.length} 个',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'list_text2img_models']);
      return jsonEncode({
        'models': models,
        'count': models.length,
        if (models.isEmpty)
          'message': '后端未配置任何文生图工作流（workflows.yaml 的 t2i 节为空）。',
      });
    } catch (e) {
      LoggerService.instance.e('列出文生图模型失败: $e',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'list_text2img_models', 'error']);
      return jsonEncode(await _buildBackendError(ref, e));
    }
  }

  /// 提交文生图任务（POST /api/text2img/generate × count）。
  ///
  /// 并发提交 N 个独立任务，每个任务返回独立 task_id。组装 images 数组
  /// （含前端生成的 imageId）返回；UI 据此渲染画廊并轮询取图。
  /// imageId 格式 `img_{ts}_{idx}`，作为本地缓存文件名。
  /// [negativePrompt] 可选；仅工作流含「负向提示词在这里替换」占位符时生效，
  /// 否则后端静默忽略。
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
    final (negativePrompt, negPromptErr) = parser.nullableString('negativePrompt');
    if (negPromptErr != null) return negPromptErr;

    final count = (countRaw ?? 1).clamp(1, 4);

    final api = ref.read(apiServiceWrapperProvider);
    final mediaProxy = ref.read(mediaProxyProvider);

    try {
      // 并发提交 N 个独立任务；每个 task_id 即统一 mediaId
      final submissions = await Future.wait(
        List.generate(count, (i) => i).map((i) async {
          final taskId = await api.submitText2ImgTask(
            prompt: prompt,
            modelName: modelName,
            negativePrompt: negativePrompt,
          );
          // 注册媒体元数据，UI 据 mediaId 回源 GET /api/text2img/image/{mediaId}
          await mediaProxy.register(
            mediaId: taskId,
            kind: MediaKind.image,
            source: MediaSource.text2img,
            prompt: prompt,
            modelName: modelName,
          );
          return {
            'mediaId': taskId,
            'prompt': prompt,
            if (modelName != null) 'modelName': modelName,
            if (negativePrompt != null) 'negativePrompt': negativePrompt,
          };
        }),
      );

      LoggerService.instance.i(
          '提交文生图任务: count=$count, modelName=${modelName ?? "(默认)"}, '
          'hasNegativePrompt=${negativePrompt != null}',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_images']);

      return jsonEncode({
        'success': true,
        'message': '已提交 $count 张图片生成任务，画廊将自动刷新直到出图。',
        'images': submissions,
        'count': submissions.length,
      });
    } catch (e) {
      LoggerService.instance.e('提交文生图任务失败: $e',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_images', 'error']);
      return jsonEncode(await _buildBackendError(ref, e));
    }
  }

  /// 提交图生视频任务（POST /api/image-to-video/generate × count）。
  ///
  /// 输入图来自 sourceMediaId（文生图结果或用户上传）。先经 MediaProxy 解析把
  /// 输入图落到本地字节（文生图可能尚未回源下载），再 multipart 上传到后端。
  /// 每个任务返回独立 task_id（即视频 mediaId），注册 source=imageToVideo，
  /// UI 据此回源 GET /api/image-to-video/video/{mediaId}。
  Future<String> createImageToVideo(
    Map<String, dynamic> args,
  ) async {
    final parser = ToolArgParser(args);
    final (prompt, promptErr) = parser.requireString('prompt');
    if (promptErr != null) return promptErr;
    final (sourceMediaId, sourceErr) = parser.requireString('sourceMediaId');
    if (sourceErr != null) return sourceErr;
    final (countRaw, countErr) = parser.optionalInt('count');
    if (countErr != null) return countErr;
    final (modelName, modelNameErr) = parser.nullableString('modelName');
    if (modelNameErr != null) return modelNameErr;

    final count = (countRaw ?? 1).clamp(1, 2);

    final api = ref.read(apiServiceWrapperProvider);
    final mediaProxy = ref.read(mediaProxyProvider);

    // 1. 先把输入图解析到本地（文生图结果可能尚未回源下载）
    final sourceResult = await mediaProxy.resolve(sourceMediaId);
    if (!sourceResult.isLoaded) {
      return jsonEncode({
        'error': 'source_image_not_ready',
        'message': '输入图片尚未就绪（状态：${sourceResult.status.name}，'
            'code：${sourceResult.code}）。请稍后重试，或先确认该图片已生成完成。',
      });
    }
    final imageBytes =
        await MediaStore.instance.getBytes(sourceMediaId, MediaKind.image);
    if (imageBytes == null || imageBytes.isEmpty) {
      return jsonEncode({
        'error': 'source_image_missing',
        'message': '输入图片本地字节缺失，无法上传。',
      });
    }

    try {
      // 2. 并发提交 N 个图生视频任务
      final submissions = await Future.wait(
        List.generate(count, (i) => i).map((i) async {
          final taskId = await api.submitImageToVideoTask(
            prompt: prompt,
            imageBytes: imageBytes,
            imageFilename: '$sourceMediaId.png',
            modelName: modelName,
          );
          await mediaProxy.register(
            mediaId: taskId,
            kind: MediaKind.video,
            source: MediaSource.imageToVideo,
            prompt: prompt,
            modelName: modelName,
          );
          return {
            'mediaId': taskId,
            'sourceMediaId': sourceMediaId,
            'prompt': prompt,
            if (modelName != null) 'modelName': modelName,
          };
        }),
      );

      LoggerService.instance.i(
          '提交图生视频任务: count=$count, source=$sourceMediaId, '
          'modelName=${modelName ?? "(默认)"}',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_image_to_video']);

      return jsonEncode({
        'success': true,
        'message': '已提交 $count 个视频生成任务，画廊将自动刷新直到出视频。',
        'videos': submissions,
        'count': submissions.length,
      });
    } catch (e) {
      LoggerService.instance.e('提交图生视频任务失败: $e',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_image_to_video', 'error']);
      return jsonEncode(await _buildBackendError(ref, e));
    }
  }
}

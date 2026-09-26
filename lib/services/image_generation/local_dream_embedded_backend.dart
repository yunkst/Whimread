/// Local Dream 嵌入式引擎生图后端
///
/// 引擎子进程由 [LocalDreamEngineManager] 管理（localhost:8081），
/// 生图协议复用 [LocalDreamClient] 的 /generate SSE 链路。
/// 与远程 local_dream 后端的差异：无控制端口（/select /status 是
/// Local Dream App 的 Kotlin 层）——模型切换由 manager 重启进程完成。
///
/// 模型条目约定（复用现有列，免迁移）：
/// - filePath = 模型包目录（docs 下的 local_dream_models/id 目录）
/// - remoteModelId = 包类型 dbName（sd15cpu/sd15npu/sdxl）
library;

import 'dart:io' show Directory;

import '../../models/image_model.dart';
import '../logger_service.dart';
import '../local_dream_embedded/engine_manager.dart';
import '../local_dream_embedded/model_pack.dart';
import '../media/media_proxy.dart';
import '../media/media_types.dart';
import 'image_generation_backend.dart';
import 'local_dream_client.dart';
import 'local_sd_backend.dart' show LocalEngineNotReadyException;

class LocalDreamEmbeddedBackend implements ImageGenerationBackend {
  final MediaProxy _mediaProxy;
  final LocalDreamEngineManager _engineManager;

  /// 测试注入用：自定义 client 构造（默认连 127.0.0.1 协议常量端口）
  final LocalDreamClient Function()? _clientFactory;

  LocalDreamEmbeddedBackend({
    required MediaProxy mediaProxy,
    required LocalDreamEngineManager engineManager,
    LocalDreamClient Function()? clientFactory,
  })  : _mediaProxy = mediaProxy,
        _engineManager = engineManager,
        _clientFactory = clientFactory;

  @override
  String get id => 'local_dream_embedded';

  @override
  bool supports(ImageModelBackendType type) =>
      type == ImageModelBackendType.localDreamEmbedded;

  /// 从模型条目解析包类型（remoteModelId 列存包类型 dbName）
  LocalDreamPackType? packTypeOf(ImageModel model) =>
      LocalDreamPackType.parse(model.remoteModelId);

  @override
  Future<String?> validate(ImageModel model) async {
    final typeError = _resolvePack(model);
    if (typeError != null) return typeError;

    if (!await _engineManager.isBinaryAvailable()) {
      return '引擎未打包：缺少 libstable_diffusion_core.so，'
          '请按 docs/local_dream_engine.md 放置 Local Dream 引擎产物后重新安装';
    }

    final packDir = model.filePath;
    if (packDir.isEmpty || !Directory(packDir).existsSync()) {
      return '模型包目录不存在：$packDir，请重新导入或下载';
    }
    final missing =
        LocalDreamModelPack.missingFiles(packDir, packTypeOf(model)!);
    if (missing.isNotEmpty) {
      return '模型包缺少文件：${missing.join('、')}，'
          '请补齐或重新下载';
    }
    return null;
  }

  @override
  Future<ImageGenerationResult> submit(
    ImageGenerationRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    final model = request.model;
    final packError = _resolvePack(model);
    if (packError != null) {
      // 引擎/包不可用属环境错误：抛 LocalEngineNotReadyException，
      // Agent 侧（media_executor）据此映射为结构化 engine_not_ready 错误码
      throw LocalEngineNotReadyException(packError);
    }
    final type = packTypeOf(model)!;

    // 确保引擎以该模型运行（相同参数复用实例，不同参数重启切换）
    try {
      await _engineManager.ensureStarted(
        type: type,
        modelDir: model.filePath,
      );
    } on LocalDreamEngineException catch (e) {
      // 启动失败（未打包/缺 QNN 运行库/超时/进程退出）= 引擎当前不可用
      throw LocalEngineNotReadyException(e.message);
    }

    final negative = request.negativePrompt ?? model.negativePrompt;
    final baseSeed =
        request.seed ?? DateTime.now().millisecondsSinceEpoch;
    final client =
        _clientFactory?.call() ?? LocalDreamClient(host: '127.0.0.1');
    final mediaIds = <String>[];
    try {
      for (var i = 0; i < request.count; i++) {
        final genRequest = LocalDreamGenerateRequest(
          prompt: request.prompt,
          negativePrompt: negative,
          // 画布恒为包类型原生尺寸（SD1.5=512、SDXL=1024），不透传模型条目
          // 像素——非原生分辨率需要独立下载的 resolution patch，且 SDXL 的
          // 非方图由 aspect_ratio 在固定画布上合成裁切（Local Dream 同款）
          width: type.generationSize,
          height: type.generationSize,
          steps: request.effectiveSteps,
          cfg: request.effectiveCfg,
          seed: baseSeed + i,
          // 比例预设仅 SDXL 引擎路径生效（SD1.5 恒为 1:1，发过去也被忽略）
          aspectRatio:
              type == LocalDreamPackType.sdxl ? request.aspectRatio : null,
        );
        final complete =
            await client.generateAndWait(genRequest, onProgress: onProgress);
        final mediaId = await _mediaProxy.upload(
          complete.bytes,
          MediaKind.image,
          prompt: request.prompt,
        );
        mediaIds.add(mediaId);
        LoggerService.instance.i(
            '本机引擎出图成功: model=${model.name}, '
            'seed=${complete.seed}, size=${complete.width}x${complete.height}, '
            '耗时=${complete.generationTimeMs}ms',
            category: LogCategory.ai,
            tags: ['image_gen', 'local_dream_embedded', 'done']);
      }
    } finally {
      client.close();
    }
    return ImageGenerationResult(mediaIds: mediaIds, modelName: model.name);
  }

  @override
  Future<void> dispose() async {}

  /// 校验模型条目的包类型/目录配置；错误返回用户文案，null 通过
  String? _resolvePack(ImageModel model) {
    final type = packTypeOf(model);
    if (type == null) {
      return '未配置模型包类型（sd15cpu/sd15npu/sdxl），请编辑该模型重新选择';
    }
    if (model.filePath.isEmpty) {
      return '未配置模型包目录，请重新导入或下载';
    }
    return null;
  }

}

/// Local Dream 远程设备生图后端
///
/// 对接局域网内 Local Dream 安卓端"宿主模式"HTTP API（协议细节见
/// [LocalDreamClient] 文档）。与 [LocalSdCppBackend] 的差异：
/// - 无本地模型文件：模型在设备上，提交前经控制端口 /select 远程激活
///   （已在跑目标模型则跳过），生成后保持运行，方便连续出图；
/// - 每次请求出一张图（设备侧 g_generation_mutex 串行），count>1 时
///   在本端循环多次、seed 递增保证出图有差异；
/// - 结果为设备编码好的 PNG bytes，直接走 MediaProxy.upload 落盘登记。
library;

import 'dart:math' show min;

import '../../models/image_model.dart';
import '../logger_service.dart';
import '../media/media_proxy.dart';
import '../media/media_types.dart';
import 'image_generation_backend.dart';
import 'local_dream_client.dart';

class LocalDreamBackend implements ImageGenerationBackend {
  final MediaProxy _mediaProxy;

  /// 测试注入用：自定义 client 构造（默认按协议常量端口连 host）
  final LocalDreamClient Function(String host)? _clientFactory;

  LocalDreamBackend({
    required MediaProxy mediaProxy,
    LocalDreamClient Function(String host)? clientFactory,
  })  : _mediaProxy = mediaProxy,
        _clientFactory = clientFactory;

  @override
  String get id => 'local_dream';

  @override
  bool supports(ImageModelBackendType type) =>
      type == ImageModelBackendType.localDream;

  /// 校验设备可达且已安装目标模型；返回 null 表示通过
  @override
  Future<String?> validate(ImageModel model) async {
    if (model.remoteHost.isEmpty || model.remoteModelId.isEmpty) {
      return '未配置设备地址或模型 id';
    }
    final client = _clientFor(model);
    try {
      final info = await client.info();
      if (info.app != 'localdream') {
        return '${model.remoteHost} 不是 Local Dream 设备';
      }
      final catalog = await client.models();
      final installed = catalog.any((m) => m.id == model.remoteModelId);
      if (!installed) {
        return '设备上未安装模型 "${model.remoteModelId}"，'
            '请在 Local Dream 中下载后再试';
      }
      return null;
    } on LocalDreamException catch (e) {
      return e.message;
    } finally {
      client.close();
    }
  }

  @override
  Future<ImageGenerationResult> submit(
    ImageGenerationRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    final model = request.model;
    if (model.remoteHost.isEmpty || model.remoteModelId.isEmpty) {
      throw const LocalDreamException('未配置设备地址或模型 id');
    }
    final client = _clientFor(model);
    try {
      // 自动激活：idle 时选中并等待加载；已在跑其他模型时切换
      await client.select(
        model.remoteModelId,
        width: request.effectiveWidth,
        height: request.effectiveHeight,
      );

      final negative =
          request.negativePrompt ?? model.negativePrompt;
      final baseSeed =
          request.seed ?? DateTime.now().millisecondsSinceEpoch;
      final mediaIds = <String>[];
      for (var i = 0; i < request.count; i++) {
        final genRequest = LocalDreamGenerateRequest(
          prompt: request.prompt,
          negativePrompt: negative,
          width: request.effectiveWidth,
          height: request.effectiveHeight,
          steps: request.effectiveSteps,
          cfg: request.effectiveCfg,
          seed: baseSeed + i,
        );
        final complete = await _generateOne(client, genRequest,
            onProgress: onProgress);
        final mediaId = await _mediaProxy.upload(
          complete.bytes,
          MediaKind.image,
          prompt: request.prompt,
        );
        mediaIds.add(mediaId);
        LoggerService.instance.i(
            'Local Dream 出图成功: model=${model.name}, '
            'seed=${complete.seed}, '
            'size=${complete.width}x${complete.height}, '
            '耗时=${complete.generationTimeMs}ms',
            category: LogCategory.ai,
            tags: ['image_gen', 'local_dream', 'done']);
      }
      return ImageGenerationResult(mediaIds: mediaIds, modelName: model.name);
    } finally {
      client.close();
    }
  }

  /// 消费一次 SSE 流，返回 complete 事件；progress 透传给 [onProgress]，
  /// error 事件转成异常抛出。
  Future<LocalDreamCompleteEvent> _generateOne(
    LocalDreamClient client,
    LocalDreamGenerateRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    LocalDreamCompleteEvent? complete;
    await for (final event in client.generate(request)) {
      switch (event) {
        case LocalDreamProgressEvent(:final step, :final totalSteps):
          // 真实设备会发出重复帧与 step > total 的帧（8 步实测出现过
          // step=10），归一化后再透传，保证上层 step/total 恒在 0..1
          if (totalSteps > 0) {
            onProgress?.call(min(step, totalSteps), totalSteps);
          }
        case LocalDreamCompleteEvent():
          complete = event;
        case LocalDreamErrorEvent(:final message):
          throw LocalDreamException('设备生成失败：$message');
      }
    }
    if (complete == null) {
      throw const LocalDreamException('设备连接中断，未返回完整图片');
    }
    return complete;
  }

  @override
  Future<void> dispose() async {}

  LocalDreamClient _clientFor(ImageModel model) =>
      _clientFactory?.call(model.remoteHost) ??
      LocalDreamClient(host: LocalDreamClient.normalizeHost(model.remoteHost));
}

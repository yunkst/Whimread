/// 本地 sd.cpp 生图后端（阶段 B：真实现）
///
/// 端侧 dart:ffi 调用 vendored stable-diffusion.cpp（master-859-7f410a3）
/// 编出的 libsds.so。出图流程：
///
/// 1. 提交时复用单槽 _loadedCtx（GGUF mmap 已加载、模型在内存）—— 加载 GGUF
///    是 10-60 秒的开销，必须缓存；切换模型时 free 旧的、new 新的。
/// 2. 在推理 isolate（Isolate.spawn）中：
///    - 填充 FFI 结构体（SdCtxParams / SdImgGenParams）
///    - 调 generate_image（阻塞直到采样完成）
///    - 把生成的 RGBA8 字节拷贝到 Dart Uint8List 并通过 SendPort 传回主 isolate
///    - free_sd_images 释放原生侧图像数组
/// 3. 主 isolate 把 Uint8List 用 `image` 包编成 PNG，经 MediaProxy.upload
///    落盘并登记到 media_items（source=localUpload，UI 一次 resolve 即出图）。
///
/// 进度回调（NativeCallable.listener）：
/// - listener 在主 isolate 创建（保持主 isolate 事件循环畅通）
/// - sd_set_progress_callback 在推理 isolate 入口注册（全局）
/// - 采样每步从采样线程触发回调，listener 把消息送主 isolate 事件循环，
///   再 forward 到 backend.submit 的 onProgress 回调
/// - 推理 isolate 退出前调 sd_set_progress_callback(nullptr, nullptr) 摘除，
///   避免下一次提交撞上同一回调
///
/// ⚠️ 已知不可用场景（与 convert 同源约束）：
/// - 当前 libsds.so 仅在 Android arm64-v8a 设备随包发布；
///   其他平台走不可用分支，由 [isEngineBinaryAvailable] 探测，
///   不可用时 executor 返回 engine_not_ready。
/// - 端侧内存吃紧时（SDXL Q8_0 约 5-7GB）低端机会 OOM，由 sd.cpp 抛
///   generate_image=false，上层转 generation_failed 错误响应。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

import '../../models/image_model.dart';
import '../conversion/gguf_writer.dart' show kGgufMagic;
import '../logger_service.dart';
import '../media/media_proxy.dart';
import '../media/media_types.dart';
import 'image_generation_backend.dart';
import 'sd_bindings.dart';

class LocalEngineNotReadyException implements Exception {
  final String message;
  const LocalEngineNotReadyException(this.message);
  @override
  String toString() => message;
}

class LocalSdCppBackend implements ImageGenerationBackend {
  /// sd.cpp 编译产物名（Android arm64）。cpp/CMakeLists.txt 设 OUTPUT_NAME=sds。
  static const String engineBinaryName = 'libsds.so';

  final MediaProxy _mediaProxy;

  /// libsds.so 句柄（首次访问时解析并缓存；解析失败抛异常）
  SdLibrary? _libCache;

  /// 当前已加载的 GGUF 路径 + 对应 sd_ctx_t*；
  /// 切换模型时 free 旧的再 new 新的；卸载后端时一起 free。
  String? _loadedModelPath;
  Pointer<SdCtxC>? _loadedCtx;

  LocalSdCppBackend({required MediaProxy mediaProxy}) : _mediaProxy = mediaProxy;

  @override
  String get id => 'local_sd';

  @override
  bool supports(ImageModelBackendType type) =>
      type == ImageModelBackendType.localSd;

  /// 真正的二进制探测：libsds.so 是否能被 DynamicLibrary 解析。
  /// - Android 设备上：arm64-v8a 才有 libsds.so；armeabi-v7a/x86/x86_64 探测失败
  ///   返回 false
  /// - 非 Android 平台：返回 false
  Future<bool> isEngineBinaryAvailable() async {
    try {
      SdLibrary.open();
      return true;
    } on LocalEngineNotReadyException {
      return false;
    } on Exception {
      return false;
    }
  }

  SdLibrary _ensureLib() {
    final cached = _libCache;
    if (cached != null) return cached;
    try {
      final lib = SdLibrary.open();
      _libCache = lib;
      return lib;
    } catch (e) {
      // 把底层不可用（无 so / ABI 不符 / 加载失败）转成业务侧统一语义
      throw LocalEngineNotReadyException(
          '本地生图引擎不可用：$e（libsds.so 仅在 Android arm64-v8a 设备随包发布）');
    }
  }

  // ===== 校验（与阶段 A 行为相同；magic + 大小）=====
  @override
  Future<String?> validate(ImageModel model) async {
    if (model.filePath.isEmpty) {
      return '该模型未关联模型文件，请重新导入 .gguf 文件。';
    }
    final file = File(model.filePath);
    if (!await file.exists()) {
      return '模型文件已丢失（${model.filePath}），请重新导入。';
    }
    final size = await file.length();
    if (size < 16) {
      return '模型文件异常（仅 $size 字节），请重新导入。';
    }
    final raf = await file.open(mode: FileMode.read);
    try {
      final header = await raf.read(4);
      for (var i = 0; i < 4; i++) {
        if (header[i] != kGgufMagic[i]) {
          return '模型文件头校验失败，不是有效的 GGUF 文件，请重新导入。';
        }
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  // ===== 提交 =====
  @override
  Future<ImageGenerationResult> submit(
    ImageGenerationRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    final modelName = request.model.name;

    // ---- 先校验：文件丢失/损坏走 generation_failed；引擎不可用走 engine_not_ready ----
    // 顺序很重要：validate 不依赖 FFI，能区分"用户模型有问题"和"环境没有引擎"。
    final err = await validate(request.model);
    if (err != null) {
      LoggerService.instance.w('本地生图模型校验失败: $modelName, $err',
          category: LogCategory.ai,
          tags: ['image_gen', 'local_sd', 'validate_failed']);
      throw StateError(err);
    }

    final lib = _ensureLib();

    final params = _InferenceParams(
      modelPath: request.model.filePath,
      prompt: request.prompt,
      negativePrompt: request.negativePrompt ?? request.model.negativePrompt,
      width: request.effectiveWidth,
      height: request.effectiveHeight,
      steps: request.effectiveSteps,
      cfg: request.effectiveCfg,
      seed: request.seed ?? DateTime.now().millisecondsSinceEpoch,
      threadCount: _resolveThreadCount(),
    );

    // ---- 创建 progress listener（主 isolate 创建 → 主 isolate 事件循环）----
    final cb = NativeCallable<SdProgressCbNative>.listener(
      (int step, int steps, double time, Pointer<Void> data) {
        try {
          onProgress?.call(step, steps);
        } catch (_) {
          // 回调异常不能传给原生侧；吞掉避免 isolate 被标 fatal
        }
      },
    );
    try {
      lib.setProgressCallback(cb.nativeFunction, nullptr);

      // ---- 单端口协议：('ctx', addr) / ('ok', result) / ('err', error, stack) ----
      // 单端口保证 isolate 任意阶段崩溃都有消息到达，主 isolate 不会永久挂起。
      final port = ReceivePort();
      var ctxAddress = 0;
      final resultCompleter = Completer<_InferenceResult>();

      late final StreamSubscription<dynamic> sub;
      sub = port.listen((msg) {
        if (msg is List && msg.isNotEmpty) {
          switch (msg[0]) {
            case 'ctx':
              ctxAddress = msg[1] as int;
            case 'ok':
              resultCompleter.complete(msg[1] as _InferenceResult);
              sub.cancel();
              port.close();
            case 'err':
              resultCompleter.completeError(msg[1] as Object, msg[2] as StackTrace?);
              sub.cancel();
              port.close();
          }
        }
      });

      // ---- 启动推理 isolate（不在消息里塞 SdLibrary，isolate 内部自己 open）----
      final oldCtxAddr = _loadedCtx?.address ?? 0;
      final oldModelPath = _loadedModelPath;
      await Isolate.spawn<_InferenceMessage>(
        _inferenceIsolateEntry,
        _InferenceMessage(
          params: params,
          currentlyLoadedCtxAddress: oldCtxAddr,
          currentlyLoadedModelPath: oldModelPath,
          resultPort: port.sendPort,
        ),
      );

      // 等待采样完成
      final result = await resultCompleter.future;

      // ---- 更新主 isolate 的 ctx 缓存（切换模型时释放旧的）----
      if (ctxAddress != 0 && ctxAddress != oldCtxAddr) {
        if (_loadedCtx != null) {
          try {
            lib.freeSdCtx(_loadedCtx!);
          } catch (_) {/* 旧 ctx 释放失败不影响新链路 */}
        }
        _loadedCtx = Pointer<SdCtxC>.fromAddress(ctxAddress);
        _loadedModelPath = params.modelPath;
      }

      // ---- 保存到 MediaStore + 注册到 media_items ----
      final mediaIds = <String>[];
      for (final bytes in result.rgbaImages) {
        final png = _encodePng(bytes, result.width, result.height);
        if (png == null) {
          throw StateError('本地生图结果编码 PNG 失败');
        }
        final mediaId = await _mediaProxy.upload(
          png,
          MediaKind.image,
          prompt: request.prompt,
        );
        mediaIds.add(mediaId);
      }

      LoggerService.instance.i(
          '本地生图完成: model=$modelName, count=${mediaIds.length}, '
          'size=${result.width}x${result.height}, seed=${params.seed}',
          category: LogCategory.ai,
          tags: ['image_gen', 'local_sd', 'done']);

      return ImageGenerationResult(
        mediaIds: mediaIds,
        modelName: modelName,
      );
    } finally {
      // 摘除全局回调；listener 关闭
      try {
        lib.setProgressCallback(nullptr, nullptr);
      } catch (_) {/* 析构阶段忽略 */}
      try {
        cb.close();
      } catch (_) {/* 已 close 时忽略 */}
    }
  }

  // ===== 资源释放（UI 退出 / 用户切换后端时）=====
  @override
  Future<void> dispose() async {
    final lib = _libCache;
    final ctx = _loadedCtx;
    if (lib != null && ctx != null) {
      try {
        lib.freeSdCtx(ctx);
      } catch (_) {/* 析构阶段忽略 */}
    }
    _loadedCtx = null;
    _loadedModelPath = null;
    _libCache = null;
  }

  // ===== helpers =====

  int _resolveThreadCount() {
    final n = (Platform.numberOfProcessors / 2).floor();
    return n.clamp(2, 8);
  }

  /// RGBA8 → PNG bytes。失败返回 null。
  Uint8List? _encodePng(Uint8List rgba, int width, int height) {
    try {
      final decoded = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodePng(decoded));
    } catch (e) {
      LoggerService.instance.w('本地生图 PNG 编码失败: $e',
          category: LogCategory.ai,
          tags: ['image_gen', 'local_sd', 'encode_png']);
      return null;
    }
  }
}

// ============================================================
// 推理 isolate 通信协议
// ============================================================

/// isolate 间传递的入参（不包含 SdLibrary，isolate 内自行 open）
class _InferenceMessage {
  final _InferenceParams params;
  final int currentlyLoadedCtxAddress;
  final String? currentlyLoadedModelPath;
  final SendPort resultPort;

  _InferenceMessage({
    required this.params,
    required this.currentlyLoadedCtxAddress,
    required this.currentlyLoadedModelPath,
    required this.resultPort,
  });
}

class _InferenceParams {
  final String modelPath;
  final String prompt;
  final String negativePrompt;
  final int width;
  final int height;
  final int steps;
  final double cfg;
  final int seed;
  final int threadCount;

  _InferenceParams({
    required this.modelPath,
    required this.prompt,
    required this.negativePrompt,
    required this.width,
    required this.height,
    required this.steps,
    required this.cfg,
    required this.seed,
    required this.threadCount,
  });
}

class _InferenceResult {
  final List<Uint8List> rgbaImages;
  final int width;
  final int height;

  _InferenceResult({
    required this.rgbaImages,
    required this.width,
    required this.height,
  });
}

/// 推理 isolate 入口（顶层 `Future<void> async`；与 model_converter 一致）
Future<void> _inferenceIsolateEntry(_InferenceMessage msg) async {
  try {
    final result = await _runInference(msg);
    msg.resultPort.send(['ok', result]);
  } catch (e, st) {
    msg.resultPort.send(['err', e, st]);
  }
}

Future<_InferenceResult> _runInference(_InferenceMessage msg) async {
  final lib = SdLibrary.open();
  final params = msg.params;

  // ---- 加载 / 复用 context ----
  Pointer<SdCtxC>? ctxPtr;
  Pointer<Utf8>? modelPathPtr;

  if (msg.currentlyLoadedCtxAddress != 0 &&
      msg.currentlyLoadedModelPath == params.modelPath) {
    ctxPtr = Pointer<SdCtxC>.fromAddress(msg.currentlyLoadedCtxAddress);
    msg.resultPort.send(['ctx', ctxPtr.address]);
  } else {
    final ctxParams = calloc<SdCtxParamsC>();
    try {
      lib.ctxParamsInit(ctxParams);
      modelPathPtr = params.modelPath.toNativeUtf8();
      ctxParams.ref
        ..nThreads = params.threadCount
        ..wType = 45 // SD_TYPE_COUNT：保持 gguf 内 dtype（已 Q8_0 量化）
        ..rngType = SdRngType.cpu
        ..samplerRngType = SdRngType.cpu
        ..prediction = SdPrediction.auto // sd.cpp 从 GGUF 自动检测 v-pred
        ..enableMmap = true
        ..flashAttn = false // CPU 后端；flash-attn 是 GPU 优化
        ..modelPath = modelPathPtr;

      final newCtx = lib.newSdCtx(ctxParams);
      if (newCtx == nullptr) {
        throw const LocalEngineNotReadyException(
            'new_sd_ctx 返回 null（GGUF 加载失败：可能不是 SD1.x/SDXL、文件损坏或内存不足）');
      }
      ctxPtr = newCtx;
      msg.resultPort.send(['ctx', ctxPtr.address]);
    } finally {
      calloc.free(ctxParams);
      if (modelPathPtr != null) malloc.free(modelPathPtr);
    }
  }

  if (ctxPtr == nullptr) {
    throw const LocalEngineNotReadyException('模型 context 创建失败');
  }

  // ---- 准备生成参数 ----
  Pointer<Utf8>? promptPtr;
  Pointer<Utf8>? negPromptPtr;
  final genParams = calloc<SdImgGenParamsC>();
  final outImages = calloc<Pointer<SdImageC>>();
  final outCount = calloc<Int32>();
  try {
    lib.imgGenParamsInit(genParams);
    promptPtr = params.prompt.toNativeUtf8();
    negPromptPtr = params.negativePrompt.toNativeUtf8();
    genParams.ref
      ..prompt = promptPtr
      ..negativePrompt = negPromptPtr
      ..width = params.width
      ..height = params.height
      ..batchCount = 1
      ..clipSkip = -1
      ..seed = params.seed
      ..strength = 1.0
      ..sampleParams.guidance.txtCfg = params.cfg
      ..sampleParams.sampleMethod = SdSampleMethod.eulerA
      ..sampleParams.scheduler = SdScheduler.discrete
      ..sampleParams.sampleSteps = params.steps;

    // ---- 推理（阻塞直到 generate_image 返回）----
    final ok = lib.generateImage(ctxPtr, genParams, outImages, outCount);
    if (!ok) {
      throw LocalEngineNotReadyException(
          'generate_image 返回 false（采样失败：可能 OOM、参数非法或模型与图片尺寸不兼容）');
    }

    final count = outCount.value;
    final imagesPtr = outImages.value;
    final rgbaImages = <Uint8List>[];
    var w = 0;
    var h = 0;
    if (count > 0 && imagesPtr != nullptr) {
      final first = imagesPtr[0];
      w = first.width;
      h = first.height;
      final len = first.width * first.height * first.channel;
      rgbaImages.add(Uint8List.fromList(first.data.asTypedList(len).toList()));
      for (var i = 1; i < count; i++) {
        final im = imagesPtr[i];
        final l = im.width * im.height * im.channel;
        rgbaImages.add(Uint8List.fromList(im.data.asTypedList(l).toList()));
      }
    }
    return _InferenceResult(rgbaImages: rgbaImages, width: w, height: h);
  } finally {
    if (outImages.value != nullptr) {
      lib.freeSdImages(outImages.value, outCount.value);
    }
    calloc.free(outImages);
    calloc.free(outCount);
    if (promptPtr != null) malloc.free(promptPtr);
    if (negPromptPtr != null) malloc.free(negPromptPtr);
    calloc.free(genParams);
  }
}
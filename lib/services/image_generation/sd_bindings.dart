/// stable-diffusion.cpp FFI 绑定层
///
/// 对应 vendored sd.cpp 版本 master-859-7f410a3（android/app/src/main/cpp/sd.cpp，
/// 见 CMakeLists.txt 注释），手写而非 ffigen：本机构建环境无 LLVM。
///
/// ⚠️ 布局约束（升级 sd.cpp 时必须重新核对 stable-diffusion.h）：
/// 1. Dart [Struct] 字段顺序必须与 C 声明**完全一致**（FFI 按声明顺序 +
///    自然对齐布局，缺一个字段整体错位 → 原生侧读到垃圾值甚至崩溃）；
/// 2. `bool` 一律 `@Bool()`（C99 bool 1 字节）；`int` 一律 `@Int32()`；
///    `size_t` 用 `@Size()`；`float` 一律 `@Float()`（Dart 侧映射 double）；
/// 3. 我们只用 txt2img 子集：单 checkpoint gguf（UNet+CLIP+VAE 合一，
///    转换器产物）+ CPU 推理 + 无 init/control/lora/ip-adapter。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ============================================================
// 枚举常量（sd.h 用 C enum，FFI 侧统一按 Int32 传递；这里只列用到的）
// ============================================================

/// sd.h enum sample_method_t（完整枚举见 stable-diffusion.h）
abstract final class SdSampleMethod {
  static const euler = 0;
  static const eulerA = 1;
  static const dpm2 = 3;
  static const dpmpp2m = 6;
  static const dpmpp2Mv2 = 7;
  static const lcm = 10;
  static const ddimTrailing = 11;
}

/// sd.h enum scheduler_t
abstract final class SdScheduler {
  static const discrete = 0;
  static const karras = 1;
  static const exponential = 2;
  static const simple = 6;
  static const beta = 15;
}

/// sd.h enum rng_type_t
abstract final class SdRngType {
  static const stdDefault = 0;
  static const cpu = 2;
}

/// sd.h enum prediction_t
abstract final class SdPrediction {
  static const eps = 0;
  static const v = 1;
  static const edmV = 2;

  /// PREDICTION_COUNT：不显式指定，sd.cpp 从 GGUF 张量自动检测
  /// （SDXL：有 v_pred marker 张量 → V_PRED；有 edm_vpred.sigma_max → EDM_V_PRED；
  ///  否则 EPS_PRED。转换器透传全部张量，marker 会保留在 GGUF 里。）
  static const auto = 8;
}

/// sd.h enum sd_log_level_t
abstract final class SdLogLevel {
  static const debug = 0;
  static const verbose = 1;
  static const info = 2;
  static const warn = 3;
  static const error = 4;

  static String name(int level) => switch (level) {
        debug => 'DEBUG',
        verbose => 'VERBOSE',
        info => 'INFO',
        warn => 'WARN',
        error => 'ERROR',
        _ => 'LOG?$level',
      };
}

/// sd.h enum sd_cancel_mode_t
abstract final class SdCancelMode {
  static const all = 0;
  static const newLatents = 1;
  static const reset = 2;
}

// ============================================================
// 结构体（字段顺序严格镜像 stable-diffusion.h，未用字段也要占位）
// ============================================================

/// sd.h sd_image_t（RGBA8）
final class SdImageC extends Struct {
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int channel;
  external Pointer<Uint8> data;
}

/// sd.h sd_tiling_params_t
final class SdTilingParamsC extends Struct {
  @Bool()
  external bool enabled;
  @Bool()
  external bool temporalTiling;
  @Int32()
  external int tileSizeX;
  @Int32()
  external int tileSizeY;
  @Float()
  external double targetOverlap;
  @Float()
  external double relSizeX;
  @Float()
  external double relSizeY;
  external Pointer<Utf8> extraTilingArgs;
}

/// sd.h sd_embedding_t
final class SdEmbeddingC extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> path;
}

/// sd.h sd_ctx_params_t（建模加载参数；txt2img 只填 model_path/线程数/通用开关）
final class SdCtxParamsC extends Struct {
  external Pointer<Utf8> modelPath;
  external Pointer<Utf8> clipLPath;
  external Pointer<Utf8> clipGPath;
  external Pointer<Utf8> clipVisionPath;
  external Pointer<Utf8> t5xxlPath;
  external Pointer<Utf8> llmPath;
  external Pointer<Utf8> llmVisionPath;
  external Pointer<Utf8> diffusionModelPath;
  external Pointer<Utf8> highNoiseDiffusionModelPath;
  external Pointer<Utf8> uncondDiffusionModelPath;
  external Pointer<Utf8> embeddingsConnectorsPath;
  external Pointer<Utf8> vaePath;
  external Pointer<Utf8> audioVaePath;
  external Pointer<Utf8> taesdPath;
  external Pointer<Utf8> controlNetPath;
  external Pointer<Utf8> ipAdapterPath;
  external Pointer<Utf8> motionModulePath;
  external Pointer<SdEmbeddingC> embeddings;
  @Uint32()
  external int embeddingCount;
  external Pointer<Utf8> photoMakerPath;
  external Pointer<Utf8> pulidWeightsPath;
  external Pointer<Utf8> tensorTypeRules;
  @Int32()
  external int nThreads;
  @Int32()
  external int wType;
  @Int32()
  external int rngType;
  @Int32()
  external int samplerRngType;
  @Int32()
  external int prediction;
  @Int32()
  external int loraApplyMode;
  @Bool()
  external bool enableMmap;
  @Bool()
  external bool flashAttn;
  @Bool()
  external bool diffusionFlashAttn;
  @Bool()
  external bool taePreviewOnly;
  @Bool()
  external bool diffusionConvDirect;
  @Bool()
  external bool vaeConvDirect;
  @Bool()
  external bool forceSdxlVaeConvScale;
  @Int32()
  external int vaeFormat;
  external Pointer<Utf8> maxVram;
  @Bool()
  external bool disablePrefetch;
  @Bool()
  external bool eagerLoad;
  external Pointer<Utf8> backend;
  external Pointer<Utf8> paramsBackend;
  external Pointer<Utf8> splitMode;
  @Bool()
  external bool autoFit;
  external Pointer<Utf8> rpcServers;
  external Pointer<Utf8> modelArgs;
  @Bool()
  external bool disableSegmentedCompute;
  @Float()
  external double linearScale;
  @Float()
  external double attnScale;
}

/// sd.h sd_audio_t
final class SdAudioC extends Struct {
  @Uint32()
  external int sampleRate;
  @Uint32()
  external int channels;
  @Uint64()
  external int sampleCount;
  external Pointer<Float> data;
}

/// sd.h sd_slg_params_t
final class SdSlgParamsC extends Struct {
  external Pointer<Int32> layers;
  @Size()
  external int layerCount;
  @Float()
  external double layerStart;
  @Float()
  external double layerEnd;
  @Float()
  external double scale;
}

/// sd.h sd_guidance_params_t
final class SdGuidanceParamsC extends Struct {
  @Float()
  external double txtCfg;
  @Float()
  external double imgCfg;
  @Float()
  external double distilledGuidance;
  external SdSlgParamsC slg;
}

/// sd.h sd_sample_params_t
final class SdSampleParamsC extends Struct {
  external SdGuidanceParamsC guidance;
  @Int32()
  external int scheduler;
  @Int32()
  external int sampleMethod;
  @Int32()
  external int sampleSteps;
  @Float()
  external double eta;
  @Int32()
  external int shiftedTimestep;
  external Pointer<Float> customSigmas;
  @Int32()
  external int customSigmasCount;
  @Float()
  external double flowShift;
  external Pointer<Utf8> extraSampleArgs;
}

/// sd.h sd_pm_params_t（photo maker，不用但占位）
final class SdPmParamsC extends Struct {
  external Pointer<SdImageC> idImages;
  @Int32()
  external int idImagesCount;
  external Pointer<Utf8> idEmbedPath;
  @Float()
  external double styleStrength;
}

/// sd.h sd_pulid_params_t（不用但占位）
final class SdPulidParamsC extends Struct {
  external Pointer<Utf8> idEmbeddingPath;
  @Float()
  external double idWeight;
}

/// sd.h sd_cache_params_t（step 缓存加速，端侧不用，占位保布局）
final class SdCacheParamsC extends Struct {
  @Int32()
  external int mode;
  @Float()
  external double reuseThreshold;
  @Float()
  external double startPercent;
  @Float()
  external double endPercent;
  @Float()
  external double errorDecayRate;
  @Bool()
  external bool useRelativeThreshold;
  @Bool()
  external bool resetErrorOnCompute;
  @Int32()
  external int fnComputeBlocks;
  @Int32()
  external int bnComputeBlocks;
  @Float()
  external double residualDiffThreshold;
  @Int32()
  external int maxWarmupSteps;
  @Int32()
  external int maxCachedSteps;
  @Int32()
  external int maxContinuousCachedSteps;
  @Int32()
  external int taylorseerNDerivatives;
  @Int32()
  external int taylorseerSkipInterval;
  external Pointer<Utf8> scmMask;
  @Bool()
  external bool scmPolicyDynamic;
  @Float()
  external double spectrumW;
  @Int32()
  external int spectrumM;
  @Float()
  external double spectrumLam;
  @Int32()
  external int spectrumWindowSize;
  @Float()
  external double spectrumFlexWindow;
  @Int32()
  external int spectrumWarmupSteps;
  @Int32()
  external int spectrumStopPercent;
}

/// sd.h sd_lora_t
final class SdLoraC extends Struct {
  @Bool()
  external bool isHighNoise;
  @Float()
  external double multiplier;
  external Pointer<Utf8> path;
}

/// sd.h sd_hires_params_t（hires fix，不用但占位）
final class SdHiresParamsC extends Struct {
  @Bool()
  external bool enabled;
  @Int32()
  external int upscaler;
  external Pointer<Utf8> modelPath;
  @Float()
  external double scale;
  @Int32()
  external int targetWidth;
  @Int32()
  external int targetHeight;
  @Int32()
  external int steps;
  @Float()
  external double denoisingStrength;
  @Int32()
  external int upscaleTileSize;
  external Pointer<Float> customSigmas;
  @Int32()
  external int customSigmasCount;
}

/// sd.h sd_img_gen_params_t（单张 txt2img 生成参数）
final class SdImgGenParamsC extends Struct {
  external Pointer<SdLoraC> loras;
  @Uint32()
  external int loraCount;
  external Pointer<Utf8> prompt;
  external Pointer<Utf8> negativePrompt;
  @Int32()
  external int clipSkip;
  external SdImageC initImage;
  external Pointer<SdImageC> refImages;
  @Int32()
  external int refImagesCount;
  external Pointer<Utf8> refImageArgs;
  external SdImageC maskImage;
  @Int32()
  external int width;
  @Int32()
  external int height;
  external SdSampleParamsC sampleParams;
  @Float()
  external double strength;
  @Int64()
  external int seed;
  @Int32()
  external int batchCount;
  external SdImageC controlImage;
  @Float()
  external double controlStrength;
  external SdImageC ipAdapterImage;
  @Float()
  external double ipAdapterStrength;
  external SdPmParamsC pmParams;
  external SdPulidParamsC pulidParams;
  external SdTilingParamsC vaeTilingParams;
  external SdCacheParamsC cache;
  external SdHiresParamsC hires;
  @Int32()
  external int qwenImageLayers;
  @Bool()
  external bool circularX;
  @Bool()
  external bool circularY;
}

/// sd.h sd_ctx_t（不透明句柄）
final class SdCtxC extends Opaque {}

// ============================================================
// 回调签名
// ============================================================

/// sd.h sd_progress_cb_t（原生侧签名）
typedef SdProgressCbNative = Void Function(
    Int32 step, Int32 steps, Float time, Pointer<Void> data);

/// sd.h sd_progress_cb_t（Dart 侧闭包签名，NativeCallable.listener 用）
typedef SdProgressCbDart = void Function(
    int step, int steps, double time, Pointer<Void> data);

/// sd.h sd_log_cb_t（原生侧签名）
typedef SdLogCbNative = Void Function(
    Int32 level, Pointer<Utf8> text, Pointer<Void> data);

// ============================================================
// 绑定入口
// ============================================================

/// libsds.so 函数绑定集合。
///
/// [open] 失败（无 so / ABI 不符）抛 [ArgumentError]，由调用方转成
/// engine_not_ready 语义；所有 late final 在首次访问时才 lookup，
/// 保证非 Android 平台构造 [SdLibrary] 本身不炸。
final class SdLibrary {
  SdLibrary._(this._lib);

  final DynamicLibrary _lib;

  static SdLibrary? _instance;

  /// 打开 libsds.so（仅 Android arm64 设备上会成功）。
  /// 失败抛异常，调用方捕获后按"引擎不可用"降级。
  static SdLibrary open() {
    final cached = _instance;
    if (cached != null) return cached;
    if (!Platform.isAndroid) {
      throw const _SdLibUnavailable('libsds.so 仅在 Android 构建中打包');
    }
    final inst = SdLibrary._(DynamicLibrary.open('libsds.so'));
    _instance = inst;
    return inst;
  }

  // ---- 全局 ----
  late final sdVersion = _lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'sd_version');
  late final sdCommit = _lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'sd_commit');
  late final sdGetSystemInfo = _lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'sd_get_system_info');
  late final sdGetNumPhysicalCores = _lib
      .lookupFunction<Int32 Function(), int Function()>(
          'sd_get_num_physical_cores');
  late final setLogCallback = _lib.lookupFunction<
      Void Function(Pointer<NativeFunction<SdLogCbNative>>, Pointer<Void>),
      void Function(
          Pointer<NativeFunction<SdLogCbNative>>, Pointer<Void>)>('sd_set_log_callback');
  late final setProgressCallback = _lib.lookupFunction<
      Void Function(Pointer<NativeFunction<SdProgressCbNative>>, Pointer<Void>),
      void Function(Pointer<NativeFunction<SdProgressCbNative>>,
          Pointer<Void>)>('sd_set_progress_callback');

  // ---- 初始化 ----
  late final ctxParamsInit = _lib
      .lookupFunction<Void Function(Pointer<SdCtxParamsC>), void Function(Pointer<SdCtxParamsC>)>(
          'sd_ctx_params_init');
  late final sampleParamsInit = _lib.lookupFunction<
      Void Function(Pointer<SdSampleParamsC>),
      void Function(Pointer<SdSampleParamsC>)>('sd_sample_params_init');
  late final imgGenParamsInit = _lib.lookupFunction<
      Void Function(Pointer<SdImgGenParamsC>),
      void Function(Pointer<SdImgGenParamsC>)>('sd_img_gen_params_init');

  // ---- context 生命周期 ----
  late final newSdCtx = _lib.lookupFunction<
      Pointer<SdCtxC> Function(Pointer<SdCtxParamsC>),
      Pointer<SdCtxC> Function(Pointer<SdCtxParamsC>)>('new_sd_ctx');
  late final freeSdCtx = _lib
      .lookupFunction<Void Function(Pointer<SdCtxC>), void Function(Pointer<SdCtxC>)>(
          'free_sd_ctx');
  late final ctxSupportsImageGeneration = _lib.lookupFunction<
      Bool Function(Pointer<SdCtxC>),
      bool Function(Pointer<SdCtxC>)>('sd_ctx_supports_image_generation');
  late final getModelVersionName = _lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<SdCtxC>),
      Pointer<Utf8> Function(Pointer<SdCtxC>)>('sd_get_model_version_name');

  // ---- 生成 ----
  late final generateImage = _lib.lookupFunction<
      Bool Function(
          Pointer<SdCtxC>,
          Pointer<SdImgGenParamsC>,
          Pointer<Pointer<SdImageC>>,
          Pointer<Int32>),
      bool Function(Pointer<SdCtxC>, Pointer<SdImgGenParamsC>,
          Pointer<Pointer<SdImageC>>, Pointer<Int32>)>('generate_image');
  late final cancelGeneration = _lib.lookupFunction<
      Void Function(Pointer<SdCtxC>, Int32),
      void Function(Pointer<SdCtxC>, int)>('sd_cancel_generation');
  late final freeSdImages = _lib.lookupFunction<
      Void Function(Pointer<SdImageC>, Int32),
      void Function(Pointer<SdImageC>, int)>('free_sd_images');
}

/// libsds.so 不可用（非 Android 平台 / so 缺失 / ABI 不符）
class _SdLibUnavailable implements Exception {
  const _SdLibUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

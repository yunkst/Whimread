/// 本地 sd.cpp 生图后端（阶段 A：接口 + 校验 + stub）
///
/// 阶段 A 交付范围：
/// - [validate]：检查导入的 .gguf 模型文件是否存在、可读、头 magic 正确
/// - [submit]  ：抛 [LocalEngineNotReadyException]，executor 据此给用户明确文案
/// - 引擎二进制探测 [isEngineBinaryAvailable]，管理页可据此显示"引擎就绪/未集成"
///
/// 阶段 B（待实现）将在此文件接入 dart:ffi：
/// 1. ffigen 从 stable-diffusion.h 生成 bindings
/// 2. sds_context_t 生命周期管理（lazy init + dispose）
/// 3. 生成跑在 Isolate.run，进度经 NativeCallable/ReceivePort 回调 onProgress
/// 4. 出图 bytes → MediaStore.saveBytes + MediaProxy.register(localUpload)
library;

import 'dart:io';

import '../../models/image_model.dart';
import '../conversion/gguf_writer.dart' show kGgufMagic;
import '../logger_service.dart';
import 'image_generation_backend.dart';

/// 本地引擎尚未接入时的异常（executor 转成 engine_not_ready 错误响应）
class LocalEngineNotReadyException implements Exception {
  final String message;
  const LocalEngineNotReadyException(this.message);

  @override
  String toString() => message;
}

class LocalSdCppBackend implements ImageGenerationBackend {
  /// sd.cpp 编译产物名（Android arm64）。阶段 B 由 NDK 构建产出放入 jniLibs。
  static const String engineBinaryName = 'libsds.so';

  @override
  String get id => 'local_sd';

  @override
  bool supports(ImageModelBackendType type) =>
      type == ImageModelBackendType.localSd;

  /// 引擎二进制是否已随 App 打包（阶段 B 后恒为 true）
  Future<bool> isEngineBinaryAvailable() async {
    // 阶段 A：引擎未集成。阶段 B 改为探测 DynamicLibrary.open 是否成功。
    return false;
  }

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
    // 头 magic 校验，拒绝损坏/被改写的文件
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

  @override
  Future<ImageGenerationResult> submit(
    ImageGenerationRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    final modelName = request.model.name;

    // 先做文件级校验，缺文件/坏文件给更具体的错误
    final validateError = await validate(request.model);
    if (validateError != null) {
      LoggerService.instance.w('本地生图模型校验失败: $modelName, $validateError',
          category: LogCategory.ai,
          tags: ['image_gen', 'local_sd', 'validate_failed']);
      throw StateError(validateError);
    }

    // 阶段 A：FFI 推理链路未接入。抛明确异常，executor 格式化为
    // {error: engine_not_ready, message: ...} 响应，不静默失败。
    LoggerService.instance.w('本地生图引擎尚未集成，无法执行推理: $modelName',
        category: LogCategory.ai,
        tags: ['image_gen', 'local_sd', 'engine_not_ready']);
    throw const LocalEngineNotReadyException(
        '本地推理引擎尚未集成（当前为管理功能先行版本）。'
        '模型已保存，待引擎接入后即可直接使用。');
  }

  @override
  Future<void> dispose() async {
    // 阶段 A 无资源；阶段 B 在此释放 FFI context
  }
}
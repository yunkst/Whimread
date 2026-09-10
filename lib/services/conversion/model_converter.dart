/// safetensors → gguf（Q8_0）模型转换器
///
/// 对齐 stable-diffusion.cpp（MIT）`src/convert.cpp` + `model_loader.cpp`
/// 的行为约定（已对照 v0.10/master 源码确认）：
/// 1. 张量名原样透传（Civitai 原始 CompVis 命名进 GGUF，loader 侧按前缀补齐）
/// 2. GGUF v3 容器、零 KV 元数据、32 字节对齐
/// 3. 量化排除规则（tensor_should_be_converted）：
///    - ne[0] % 32 != 0（Q8_0 块大小）
///    - 名称以 .bias / .scale / .weight_scale 结尾
///    - UNet 的 time_embed. / label_emb.、含 embedding 的名字
///    - MMDiT/Flux 的 embedder 层（img_in./txt_in./x_embedder. 等）
///    - 不满足排除 → 量化为 Q8_0
/// 4. 被排除张量保持原 dtype（F32/F16/BF16 → ggml 对应类型，字节原样拷贝）
///
/// 内存模型：逐张量 流式处理（读源张量 → 量化/拷贝 → 写目标文件后释放），
/// 峰值 ≈ 最大单张量（UNet 中约 200-300MB）× 2（输入解码+输出块）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'arch_detector.dart';
import 'gguf_writer.dart';
import 'quantize_q8_0.dart';
import 'safetensors_reader.dart';

/// 转换进度
class ConversionProgress {
  final int currentTensor;
  final int totalTensors;

  /// 0-100
  final int percent;

  /// 当前正在处理的张量名
  final String tensorName;

  const ConversionProgress({
    required this.currentTensor,
    required this.totalTensors,
    required this.percent,
    required this.tensorName,
  });
}

/// 转换结果
class ConversionResult {
  final String outputPath;

  /// 输出文件字节数
  final int outputSize;

  /// 识别出的架构
  final SdArch arch;

  /// 量化张量数 / 保留张量数
  final int quantizedCount;
  final int keptCount;

  const ConversionResult({
    required this.outputPath,
    required this.outputSize,
    required this.arch,
    required this.quantizedCount,
    required this.keptCount,
  });
}

/// 转换前检查结果（convertAndReport 前置）
class ConversionPlan {
  final SafetensorsFile source;
  final ArchDetection detection;

  /// 估算输出大小（字节）
  final int estimatedOutputSize;

  const ConversionPlan({
    required this.source,
    required this.detection,
    required this.estimatedOutputSize,
  });
}

/// 转换失败（架构不支持等，UI 直接展示 message）
class ConversionException implements Exception {
  final String message;
  const ConversionException(this.message);
  @override
  String toString() => message;
}

/// 分析源文件并生成转换计划（不写盘）。
///
/// 抛 [ConversionException]：非 safetensors / 架构不支持。
Future<ConversionPlan> planConversion(File sourceFile) async {
  final SafetensorsFile st;
  try {
    st = await parseSafetensors(sourceFile);
  } on FormatException catch (e) {
    throw ConversionException('无法读取模型文件：${e.message}');
  }

  final detection0 = detectArch(st.tensors.map((t) => t.name));

  // v-pred 检测（元数据优先）：modelspec.predict_key == 'v' 或显式 v_pred 标记。
  // v-pred 模型可正常转换，但阶段 B 推理时需 use_v_pred 采样开关（记标志待用）。
  final predictKey =
      (st.metadata['modelspec.predict_key'] ?? '').toLowerCase();
  final metaSaysVPred =
      predictKey == 'v' || st.metadata.containsKey('v_pred');
  final detection = metaSaysVPred && !detection0.isVPrediction
      ? ArchDetection(arch: detection0.arch, isVPrediction: true)
      : detection0;

  if (!detection.isSupported) {
    throw ConversionException(
        '该模型不是 SD 1.x / SDXL 架构（当前仅支持这两类，Flux 等新架构暂不支持）。');
  }

  var estimated = 0;
  for (final t in st.tensors) {
    final ne = t.shape.reversed.toList();
    if (_shouldQuantize(t.name, ne)) {
      final numElements = t.numElements;
      estimated += (numElements ~/ 32) * 34;
    } else {
      estimated += t.byteLength;
    }
  }

  return ConversionPlan(
      source: st, detection: detection, estimatedOutputSize: estimated);
}

/// 执行转换（同 isolate 内）。一般用 [runConversion] 跑在后台 isolate。
///
/// [onProgress] 在张量粒度回调（UNet+CLIP+VAE 约 1000+ 个张量）。
Future<ConversionResult> convertToGguf(
  ConversionPlan plan,
  String outputPath, {
  void Function(ConversionProgress progress)? onProgress,
  bool Function()? isCancelled,
}) async {
  final st = plan.source;
  final entries = <GgufTensorEntry>[];
  var quantized = 0;
  var kept = 0;

  for (var i = 0; i < st.tensors.length; i++) {
    if (isCancelled?.call() ?? false) {
      throw const ConversionException('转换已取消');
    }
    final t = st.tensors[i];
    final ne = t.shape.reversed.toList(); // ggml 序
    onProgress?.call(ConversionProgress(
      currentTensor: i + 1,
      totalTensors: st.tensors.length,
      percent: ((i + 1) * 100 ~/ st.tensors.length),
      tensorName: t.name,
    ));

    if (_shouldQuantize(t.name, ne)) {
      quantized++;
      entries.add(GgufTensorEntry(
        name: t.name,
        ne: ne,
        ggmlType: kGgmlTypeQ8_0,
        dataLoader: () async {
          final raw = await st.readTensorBytes(t);
          final f32 = decodeToFloat32(
              raw, _stDtypeName(t.dtype), t.numElements);
          return quantizeQ8_0(f32, t.numElements);
        },
      ));
    } else {
      kept++;
      final ggmlType = _ggmlTypeOf(t.dtype);
      // F32 原样拷贝；F16/BF16 原样拷贝（ggml 同名类型字节兼容）
      entries.add(GgufTensorEntry(
        name: t.name,
        ne: ne,
        ggmlType: ggmlType,
        dataLoader: () => st.readTensorBytes(t),
      ));
    }
  }

  await writeGgufFile(outputPath, entries);

  return ConversionResult(
    outputPath: outputPath,
    outputSize: await File(outputPath).length(),
    arch: plan.detection.arch,
    quantizedCount: quantized,
    keptCount: kept,
  );
}

/// 在后台 isolate 中运行完整转换（plan 也隔离内算，避免跨 isolate 传 File 句柄）。
///
/// [onProgress] 经 SendPort 回传主 isolate（消息只含可发送的简单对象）。
/// 注意：不能用 `Isolate.run` —— 它会把闭包整体序列化，捕获了 repo/service
/// 的 onProgress 回调会导致 "object is unsendable" 崩溃。
Future<ConversionResult> runConversion({
  required String sourcePath,
  required String outputPath,
  void Function(ConversionProgress progress)? onProgress,
}) async {
  final resultPort = ReceivePort();
  final progressPort = ReceivePort();
  late final StreamSubscription<dynamic> progressSub;

  final isolate = await Isolate.spawn(
    _conversionIsolateEntry,
    _ConversionIsolateMessage(
      sourcePath: sourcePath,
      outputPath: outputPath,
      resultPort: resultPort.sendPort,
      progressPort: progressPort.sendPort,
    ),
    errorsAreFatal: true,
  );

  final completer = Completer<ConversionResult>();
  progressSub = progressPort.listen((msg) {
    if (msg is List && msg.length == 4 && onProgress != null) {
      onProgress(ConversionProgress(
        currentTensor: msg[0] as int,
        totalTensors: msg[1] as int,
        percent: msg[2] as int,
        tensorName: msg[3] as String,
      ));
    }
  });
  resultPort.listen((msg) {
    progressSub.cancel();
    progressPort.close();
    if (msg is List && msg[0] == 'ok') {
      final r = msg[1] as List;
      completer.complete(ConversionResult(
        outputPath: r[0] as String,
        outputSize: r[1] as int,
        arch: SdArch.values[r[2] as int],
        quantizedCount: r[3] as int,
        keptCount: r[4] as int,
      ));
    } else if (msg is List && msg[0] == 'error') {
      completer.completeError(ConversionException(msg[1] as String));
    } else {
      completer.completeError(const ConversionException('转换 isolate 异常退出'));
    }
    isolate.kill(priority: Isolate.beforeNextEvent);
  });

  try {
    return await completer.future;
  } finally {
    resultPort.close();
  }
}

/// isolate 入口（必须是顶层/静态函数，参数与返回值全部可发送）
Future<void> _conversionIsolateEntry(_ConversionIsolateMessage msg) async {
  try {
    final plan = await planConversion(File(msg.sourcePath));
    final result = await convertToGguf(plan, msg.outputPath,
        onProgress: (p) =>
            msg.progressPort.send([p.currentTensor, p.totalTensors, p.percent, p.tensorName]));
    msg.resultPort.send([
      'ok',
      [result.outputPath, result.outputSize, result.arch.index, result.quantizedCount, result.keptCount]
    ]);
  } on ConversionException catch (e) {
    msg.resultPort.send(['error', e.message]);
  } catch (e) {
    msg.resultPort.send(['error', e.toString()]);
  }
}

class _ConversionIsolateMessage {
  final String sourcePath;
  final String outputPath;
  final SendPort resultPort;
  final SendPort progressPort;

  const _ConversionIsolateMessage({
    required this.sourcePath,
    required this.outputPath,
    required this.resultPort,
    required this.progressPort,
  });
}

/// sd.cpp tensor_should_be_converted 的 Dart 移植（Q8_0 目标类型）
bool _shouldQuantize(String name, List<int> ne) {
  // Q8_0 块大小约束
  if (ne.isEmpty || ne[0] % 32 != 0) return false;
  if (name.endsWith('.bias')) return false;
  if (name.endsWith('.scale')) return false;
  if (name.endsWith('.weight_scale')) return false;
  // UNet 嵌入层
  if (name.contains('time_embed.') || name.contains('label_emb.')) return false;
  // TE embedding 表
  if (name.contains('embedding')) return false;
  // MMDiT / Flux（防御性；这些架构已在 detect 拒绝）
  const mmditKeys = [
    'img_in.', 'txt_in.', 'time_in.', 'vector_in.', 'guidance_in.',
    'final_layer.', 'x_embedder.', 't_embedder.', 'y_embedder.',
    'pos_embed', 'context_embedder.'
  ];
  for (final k in mmditKeys) {
    if (name.contains(k)) return false;
  }
  return true;
}

int _ggmlTypeOf(StDtype dtype) {
  switch (dtype) {
    case StDtype.f32:
      return kGgmlTypeF32;
    case StDtype.f16:
      return kGgmlTypeF16;
    case StDtype.bf16:
      return kGgmlTypeBF16;
    default:
      // 非浮点张量（理论不出现在 SD checkpoint 权重）按 F32 处理
      return kGgmlTypeF32;
  }
}

/// safetensors dtype 枚举 → JSON dtype 字符串（decodeToFloat32 的入参约定）
String _stDtypeName(StDtype dtype) {
  switch (dtype) {
    case StDtype.f32:
      return 'F32';
    case StDtype.f16:
      return 'F16';
    case StDtype.bf16:
      return 'BF16';
    default:
      throw FormatException('非浮点 dtype 不能量化: $dtype');
  }
}

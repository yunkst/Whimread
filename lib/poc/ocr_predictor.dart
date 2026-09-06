import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import '../services/logger_service.dart';

/// PP-OCRv6 rec 离线识别器。
///
/// 模型：assets/models/inference.onnx — 番茄字体反爬 PUA 单字识别
/// 字典：assets/models/ppocrv6_dict.txt — 18708 行 CTC 字符表
///
/// 产品用法（编排见 OcrRestoreService）：
///   1. WebView canvas 用反爬字体把单个 PUA 渲染为 base64 PNG
///   2. recognizeImage(base64Png) → base64 → ui.Image
///   3. NCHW float32 tensor，2x-1 归一化（PP-OCR 标准 mean=0.5/std=0.5）
///   4. onnxruntime 推理 → [1, T, 18710] logits
///   5. CTC greedy decode，blank=index 0，dict idx = ctc_idx - 1
///
/// 模型不渲染字体；WebView 渲染是为了保留 @font-face 上下文。
class OcrPredictor {
  OcrPredictor();

  OrtSession? _session;
  List<String> _vocab = const [];
  int _vocabSize = 0;

  bool get isLoaded => _session != null && _vocab.isNotEmpty;

  /// 从 asset 加载模型与字典。可重复调用以热重载。
  Future<void> load({
    String modelAsset = 'assets/models/inference.onnx',
    String dictAsset = 'assets/models/ppocrv6_dict.txt',
  }) async {
    // 加载字典
    final dictStr = await rootBundle.loadString(dictAsset);
    _vocab = [
      for (final line in dictStr.split('\n'))
        if (line.isNotEmpty) line.trim(),
    ];
    _vocabSize = _vocab.length;
    if (_vocabSize < 1000) {
      throw StateError('字典加载异常：仅 $_vocabSize 行');
    }

    // 加载模型并创建 session
    //
    // 显式锁定 CPU EP（providers: [OrtProvider.CPU]）：
    // - ORT 默认本就是 CPU EP，硬件加速必须显式注册才生效；
    // - 这里显式锁定的目的不是"开启 CPU"，而是**干净排除 NNAPI/XNNPACK 嫌疑**——
    //   真机 100% SIGABRT + 模拟器不崩，最大嫌疑是厂商 NNAPI 驱动对动态 shape
    //   算子（Reshape/Slice/Squeeze，本模型各有 8 个）兼容失败。
    //   若锁定 CPU 后真机仍崩，则排除 EP 假设，箭头转向 Android 16 内存安全层
    //   / 插件 FFI 异常逃逸。
    // - 同时打印 getAvailableProviders() 与 getInputInfo()/getOutputInfo() 作为
    //   运行时探针：前者确认本机有哪些 EP，后者让包自报输入签名（与 Python
    //   onnx 包读到的 [DynamicDimension.0, 3, 48, DynamicDimension.1] 对比，
    //   验证 w=64 是否真是包支持的宽度）。
    // 重复调用 load()（热重载）前先关闭旧 session：closeSession 是 native
    // sessions 注册表的唯一清理入口，不关则旧 OrtSession + 模型 buffer 永久驻留。
    final previousSession = _session;
    _session = null;
    if (previousSession != null) {
      await previousSession.close();
    }

    final ort = OnnxRuntime();

    // 诊断 1：本机可用 EP 清单
    try {
      final providers = await ort.getAvailableProviders();
      LoggerService.instance.i(
        'ORT 可用 EP: $providers',
        category: LogCategory.ai,
        tags: ['ocr', 'onnx', 'ep-available'],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'ORT getAvailableProviders 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['ocr', 'onnx', 'ep-available-fail'],
      );
    }

    // 显式锁定 CPU EP
    final options = OrtSessionOptions(
      providers: [OrtProvider.CPU],
      intraOpNumThreads: 4,
      interOpNumThreads: 1,
      useArena: true,
    );
    _session = await ort.createSessionFromAsset(modelAsset, options: options);

    // 诊断 2：模型输入/输出签名（包自报，与 Python onnx 签名对比）
    try {
      final inputs = await _session!.getInputInfo();
      for (final i in inputs) {
        LoggerService.instance.i(
          'ORT input info: ${i.entries.map((e) => "${e.key}=${e.value}").join(", ")}',
          category: LogCategory.ai,
          tags: ['ocr', 'onnx', 'input-info'],
        );
      }
      final outputs = await _session!.getOutputInfo();
      for (final o in outputs) {
        LoggerService.instance.i(
          'ORT output info: ${o.entries.map((e) => "${e.key}=${e.value}").join(", ")}',
          category: LogCategory.ai,
          tags: ['ocr', 'onnx', 'output-info'],
        );
      }
    } catch (e, st) {
      LoggerService.instance.e(
        'ORT getInputInfo/getOutputInfo 失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['ocr', 'onnx', 'info-fail'],
      );
    }
  }

  /// 确保模型已加载，否则抛 [StateError]（防御 _session 空指针 → native crash）。
  void _ensureLoaded() {
    if (_session == null) {
      throw StateError('OCR 模型尚未加载完成，请稍后重试');
    }
  }

  /// 识别 WebView canvas 渲染好的单字图（base64 PNG，不带 data:image/png;base64, 前缀）。
  ///
  /// 渲染由调用方在 WebView canvas 完成（保留 @font-face 上下文），本方法只做
  /// base64 → ui.Image → 预处理 → onnx 推理 → CTC 解码。
  ///
  /// 抛出 [StateError] 如果模型尚未加载（防御 _session 空指针崩溃）。
  Future<String> recognizeImage(String base64Png) async {
    _ensureLoaded();

    // 诊断日志：确认崩溃发生在哪个阶段
    final t0 = DateTime.now();
    final pngLen = base64Png.length;
    LoggerService.instance.i(
      'OCR recognizeImage 开始 pngLen=$pngLen',
      category: LogCategory.ai,
      tags: ['ocr', 'onnx', 'recognize-begin'],
    );

    Uint8List bytes;
    try {
      bytes = base64Decode(base64Png);
      LoggerService.instance.i(
        'OCR base64Decode 完成 byteLen=${bytes.length} 耗时=${DateTime.now().difference(t0).inMilliseconds}ms',
        category: LogCategory.ai,
        tags: ['ocr', 'onnx', 'base64-ok'],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'OCR base64Decode 崩溃: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['ocr', 'onnx', 'base64-crash'],
      );
      rethrow;
    }

    ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      LoggerService.instance.i(
        'OCR instantiateImageCodec 完成 耗时=${DateTime.now().difference(t0).inMilliseconds}ms',
        category: LogCategory.ai,
        tags: ['ocr', 'onnx', 'codec-ok'],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        'OCR instantiateImageCodec 崩溃: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['ocr', 'onnx', 'codec-crash'],
      );
      rethrow;
    }
    // 用 try/finally 释放 GPU 资源：codec 持有解码器状态，frame.image 持有
    // GPU 纹理（Dart GC 不回收 GPU 纹理，必须显式 dispose）。否则每章 200+ PUA
    // 字符累积 ~11MB 不可回收 GPU 内存，低内存设备可能 OOM。
    // toByteData 返回的是拷贝，dispose image 不影响 _preprocess 已读出的字节。
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final (tensor, w) = await _preprocess(image);
        final inputValue = await OrtValue.fromList(tensor, [1, 3, 48, w]);
        // 兜底初始化为空：run() 抛异常时 finally 只需释放 input。
        Map<String, OrtValue> outputs = const {};
        try {
          LoggerService.instance.i(
            'OCR ONNX 推理开始 耗时=${DateTime.now().difference(t0).inMilliseconds}ms',
            category: LogCategory.ai,
            tags: ['ocr', 'onnx', 'session-run-begin'],
          );
          outputs = await _session!.run({'x': inputValue});
          LoggerService.instance.i(
            'OCR ONNX 推理完成 耗时=${DateTime.now().difference(t0).inMilliseconds}ms',
            category: LogCategory.ai,
            tags: ['ocr', 'onnx', 'session-run-ok'],
          );
          final value = outputs.values.first;
          final nested = await value.asList();
          final logits = (nested[0] as List)
              .map((e) => (e as List).map((x) => (x as num).toDouble()).toList())
              .toList();
          final (text, _) = _ctcDecode(logits);
          LoggerService.instance.i(
            'OCR CTC 解码完成 result="$text" 总耗时=${DateTime.now().difference(t0).inMilliseconds}ms',
            category: LogCategory.ai,
            tags: ['ocr', 'onnx', 'recognize-done'],
          );
          return text;
        } catch (e, st) {
          LoggerService.instance.e(
            'OCR ONNX 推理崩溃: $e',
            stackTrace: st.toString(),
            category: LogCategory.ai,
            tags: ['ocr', 'onnx', 'session-run-crash'],
          );
          rethrow;
        } finally {
          // OrtValue 是 native tensor 的句柄（Dart 侧仅持 id 字符串），必须
          // 显式 dispose：Android 插件维护 ortValues 注册表，只有
          // releaseOrtValue 会移除条目，closeSession 也不清空。不释放则每次
          // 推理驻留 ~634KB native 内存（output [1,T,18710] float32 占大头）。
          await inputValue.dispose();
          for (final v in outputs.values) {
            await v.dispose();
          }
        }
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// 释放 session。
  Future<void> dispose() async {
    final s = _session;
    _session = null;
    if (s != null) {
      await s.close();
    }
  }

  // --- 预处理：rawRgba → Float32List NCHW，2x-1 归一化 ---

  Future<(Float32List, int)> _preprocess(ui.Image rendered) async {
    // ui.Image (rendered.width x rendered.height, RGBA) → image.Image
    final rgba = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    final src = rgba!.buffer.asUint8List();
    final srcImg = img.Image.fromBytes(
      width: rendered.width,
      height: rendered.height,
      bytes: src.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    // resize 到 (W, 48)，W = ceil(rendered.width * 48 / rendered.height / 32) * 32
    final scale = 48.0 / rendered.height;
    final w = (max(1, rendered.width * scale) / 32).ceil() * 32;
    final resized = img.copyResize(
      srcImg,
      width: w,
      height: 48,
      interpolation: img.Interpolation.linear,
    );

    // NCHW float32，2x-1
    final pixels = resized.getBytes(order: img.ChannelOrder.rgb);
    final tensor = Float32List(1 * 3 * 48 * w);
    final hw = 48 * w;
    for (int y = 0; y < 48; y++) {
      for (int x = 0; x < w; x++) {
        final p = (y * w + x) * 3;
        final r = pixels[p] / 255.0;
        final g = pixels[p + 1] / 255.0;
        final b = pixels[p + 2] / 255.0;
        tensor[0 * hw + y * w + x] = 2.0 * r - 1.0;
        tensor[1 * hw + y * w + x] = 2.0 * g - 1.0;
        tensor[2 * hw + y * w + x] = 2.0 * b - 1.0;
      }
    }
    return (tensor, w);
  }

  // --- CTC greedy decode ---

  (String, List<int>) _ctcDecode(List<List<double>> logits) {
    final raw = <int>[];
    final out = StringBuffer();
    int lastIdx = -1;
    for (final timestep in logits) {
      // argmax
      int bestIdx = 0;
      double bestVal = timestep[0];
      for (int i = 1; i < timestep.length; i++) {
        if (timestep[i] > bestVal) {
          bestVal = timestep[i];
          bestIdx = i;
        }
      }
      raw.add(bestIdx);
      if (bestIdx != 0 && bestIdx != lastIdx) {
        // vocab index = ctc_idx - 1
        final vIdx = bestIdx - 1;
        if (vIdx >= 0 && vIdx < _vocabSize) {
          out.write(_vocab[vIdx]);
        }
      }
      lastIdx = bestIdx;
    }
    return (out.toString(), raw);
  }
}

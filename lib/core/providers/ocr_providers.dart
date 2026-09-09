/// OCR 相关 Provider。
///
/// `ocrModelDownloaderProvider`:单例下载器,`main()` 启动后 schedule 一次
///   `ensureLocal()`;`ocrPredictorProvider` await 它,保证模型本地就绪才加载。
/// `ocrPredictorProvider`:全局单例(keepAlive),应用生命周期加载一次 onnx 模型。
/// `OcrRestoreService` 不在此全局注册--它需要注入 `_renderPua` 回调
/// (依赖具体 WebView 实例),由各调用方(content/list service、save_script executor)
/// 就地 `OcrRestoreService(ref, renderPua)` 构造。
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../poc/ocr_predictor.dart';
import '../../services/ocr_model_downloader.dart';
import '../../utils/device_arch.dart';

/// OCR 模型下载器单例。main() 在 post-frame 里触发 ensureLocal()。
final ocrModelDownloaderProvider = Provider<OcrModelDownloader>((ref) {
  return OcrModelDownloader(
    dio: Dio(),
    // manifest 里的 key 是 'arm64-v8a' / 'armeabi-v7a' / 'x86_64',
    // 与 DeviceArch.apkNameSegment 输出一致
    archProvider: () async {
      final arch = await DeviceArchDetector.getCurrent();
      final seg = arch.apkNameSegment;
      return seg.isEmpty ? 'arm64-v8a' : seg;
    },
  );
});

/// PP-OCRv6 识别器单例。lazy + cached,应用生命周期加载一次(~1s)。
///
/// 加载前置:await downloader.ensureLocal()(同一启动周期只跑一次,
/// 首启后台已提前触发,这里一般是直接命中缓存)。
/// 失败时 ensureLocal 会抛 StateError("OCR 模型 xx 下载失败"),由
/// OcrRestoreService 捕获转为"模型下载中/失败"提示,不产生 native crash。
final ocrPredictorProvider = FutureProvider<OcrPredictor>((ref) async {
  final downloader = ref.read(ocrModelDownloaderProvider);
  await downloader.ensureLocal();
  final modelPath = await downloader.localModelPath();
  final dictPath = await downloader.localDictPath();

  final predictor = OcrPredictor();
  await predictor.load(modelPath: modelPath, dictPath: dictPath);
  ref.onDispose(() => predictor.dispose());
  return predictor;
});

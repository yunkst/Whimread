/// OCR 相关 Provider。
///
/// `ocrPredictorProvider` 全局单例（keepAlive），应用生命周期加载一次 onnx 模型。
/// `OcrRestoreService` 不在此全局注册--它需要注入 `_renderPua` 回调
/// （依赖具体 WebView 实例），由各调用方（content/list service、save_script executor）
/// 就地 `OcrRestoreService(ref, renderPua)` 构造。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../poc/ocr_predictor.dart';

/// PP-OCRv6 识别器单例。lazy + cached，应用生命周期加载一次（~1s）。
final ocrPredictorProvider = FutureProvider<OcrPredictor>((ref) async {
  final predictor = OcrPredictor();
  await predictor.load();
  ref.onDispose(() => predictor.dispose());
  return predictor;
});

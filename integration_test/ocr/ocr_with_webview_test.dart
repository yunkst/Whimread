/// OCR + WebView 共存 integration test
///
/// 目的：验证 OCR 推理崩溃是否由 WebView 与 onnxruntime native 库共存引起。
///
/// 背景：独立 OCR test（ocr_inference_test.dart）在真机上**不崩**，证明
/// recognizeImage 本身没问题。但产品路径必崩。两者的关键差异是：产品路径
/// 在调用 OCR 时，进程里已经有 HeadlessWebView（加载了 chromium/WebView
/// 的一堆 native 库）。怀疑 WebView 的 native 库与 libonnxruntime.so 在
/// 内存/线程/信号处理上冲突。
///
/// 本 test 的做法：先创建一个 InAppWebView 并保持存活，然后在 WebView
/// 存在的情况下调 recognizeImage。若崩 → WebView 共存冲突坐实；若不崩 →
/// 排除该假设，继续往 HeadlessWebViewPool / agent 上下文方向逼近。
///
/// ## 运行（真机）
///   cd novel_app
///   flutter test integration_test/ocr/ocr_with_webview_test.dart -d DEVICE_ID
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:novel_app/poc/ocr_predictor.dart';
import '../helpers/webview_test_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OCR recognizeImage 在 WebView 共存下推理', (tester) async {
    final sw = Stopwatch()..start();

    // ── 1. 先创建 WebView 并保持存活（模拟产品路径的上下文） ──
    // ignore: avoid_print
    print('[OCR-WV-TEST] === step 1: 创建 InAppWebView ===');
    final wvHelper = WebViewTestHelper();
    try {
      final controller = await wvHelper.createWebView(tester);
      // ignore: avoid_print
      print('[OCR-WV-TEST] WebView 创建成功，存活中 elapsed=${sw.elapsedMilliseconds}ms');
      // 引用一下 controller 避免被优化掉
      // ignore: unnecessary_statements
      controller.runtimeType;
    } catch (e, st) {
      // ignore: avoid_print
      print('[OCR-WV-TEST] WebView 创建失败: $e\n$st');
      rethrow;
    }

    // ── 2. 加载 OCR 模型（在 WebView 存活的情况下） ──
    // ignore: avoid_print
    print('[OCR-WV-TEST] === step 2: load() 加载 OCR 模型（WebView 存活中） ===');
    final ocr = OcrPredictor();
    try {
      await ocr.load();
      // ignore: avoid_print
      print('[OCR-WV-TEST] load() 完成 isLoaded=${ocr.isLoaded} '
          'elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      // ignore: avoid_print
      print('[OCR-WV-TEST] load() 抛异常: $e\n$st');
      rethrow;
    }

    // ── 3. 生成测试 PNG（与独立 test 一致：120×120 白底黑块） ──
    final pngImage = img.Image(width: 120, height: 120);
    img.fill(pngImage, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      pngImage,
      x1: 40,
      y1: 40,
      x2: 80,
      y2: 80,
      color: img.ColorRgb8(0, 0, 0),
    );
    final blankPngBase64 = base64Encode(img.encodePng(pngImage));
    // ignore: avoid_print
    print('[OCR-WV-TEST] === step 3: PNG 生成 b64Len=${blankPngBase64.length} ===');

    // ── 4. 在 WebView 存活下调 recognizeImage（关键观察点） ──
    // ignore: avoid_print
    print('[OCR-WV-TEST] === step 4: 调 recognizeImage（WebView 存活，预期可能崩） === '
        'elapsed=${sw.elapsedMilliseconds}ms');
    String result;
    try {
      result = await ocr.recognizeImage(blankPngBase64);
      // ignore: avoid_print
      print('[OCR-WV-TEST] recognizeImage 完成 result="$result" '
          'elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      // ignore: avoid_print
      print('[OCR-WV-TEST] recognizeImage 抛 Dart 异常（非 native abort）: $e\n$st');
      rethrow;
    }

    expect(result, isA<String>(),
        reason: 'recognizeImage 应返回 String（空或字符均可）');

    await ocr.dispose();
    await wvHelper.dispose();
    // ignore: avoid_print
    print('[OCR-WV-TEST] === DONE 总耗时=${sw.elapsedMilliseconds}ms ===');
  });
}

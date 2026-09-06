/// OCR 真机推理 integration test
///
/// 目的：绕开 agent / WebView / HeadlessWebViewPool 整条链路，在真机上
/// 直接调 OcrPredictor.recognizeImage，复现 vivo Android 16 真机的
/// session.run SIGABRT。
///
/// 纯 Dart 单元测试在 PC 上跑用 mock，根本不加载真机的 libonnxruntime.so，
/// 所以 20/20 单测全过但真机照崩。本 test 走 integration_test 框架，在真机
/// 上跑、加载真实 native 库、调真实 plugin。
///
/// 测试用的 PNG 是硬编码的 120×120 白底黑块（模拟 WebView canvas.toDataURL
/// 输出），零外部依赖、可重复。黑块不是真实字形，但崩溃点在 session.run
/// 本身（backtrace 跨 ORT 版本一致已证明是固定 abort 路径，与输入数据无关），
/// 所以任意合法 PNG 都能触发。
///
/// ## 运行（真机）
///   cd novel_app
///   flutter test integration_test/ocr/ocr_inference_test.dart -d DEVICE_ID
///
/// ## AS Debug 跑
///   打开本文件 → 行号旁点 Debug（虫子）→ 选 device → 在 recognizeImage
///   调用处（ocr_predictor.dart _session.run）打断点。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:novel_app/poc/ocr_predictor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OCR recognizeImage 真机推理（复现 SIGABRT）', (tester) async {
    final sw = Stopwatch()..start();

    // 生成 120×120 白底 + 中心 40×40 黑块 PNG（模拟 WebView canvas.toDataURL 输出）。
    // 用 image 包现场生成，避免硬编码 base64 拷贝错误。与 ocr_render_js.dart
    // 的 canvas 120×120 + ctx.fillRect 黑字一致。
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

    // ── 1. 构造 OcrPredictor 并加载模型 ──
    // ignore: avoid_print
    print('[OCR-TEST] === step 1: 构造 OcrPredictor ===');
    final ocr = OcrPredictor();

    // ignore: avoid_print
    print('[OCR-TEST] === step 2: load() 加载模型 + 字典 + 创建 session ===');
    try {
      await ocr.load();
      // ignore: avoid_print
      print('[OCR-TEST] load() 完成 isLoaded=${ocr.isLoaded} '
          'elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      // ignore: avoid_print
      print('[OCR-TEST] load() 抛异常: $e\n$st');
      rethrow;
    }

    // ── 2. 解码 base64 → 字节，确认输入合法 ──
    // ignore: avoid_print
    print('[OCR-TEST] === step 3: base64 解码 === '
        'b64Len=${blankPngBase64.length}');
    final bytes = base64Decode(blankPngBase64);
    // ignore: avoid_print
    print('[OCR-TEST] base64Decode OK byteLen=${bytes.length} '
        'elapsed=${sw.elapsedMilliseconds}ms');

    // ── 3. 调 recognizeImage（崩溃预期在此内部 session.run） ──
    // 这里是关键：若真机在此 SIGABRT，前面的 print 已落盘，且 Dart 侧
    // try/catch 接不住 native abort（与产品路径现象一致）。
    // ignore: avoid_print
    print('[OCR-TEST] === step 4: 调 recognizeImage（预期崩溃点） === '
        'elapsed=${sw.elapsedMilliseconds}ms');
    String result;
    try {
      result = await ocr.recognizeImage(blankPngBase64);
      // ignore: avoid_print
      print('[OCR-TEST] recognizeImage 完成 result="$result" '
          'elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      // 如果走到这里，说明是 Dart 异常（非 native abort），反而是好消息——
      // 能拿到完整错误信息。
      // ignore: avoid_print
      print('[OCR-TEST] recognizeImage 抛 Dart 异常（非 native abort）: $e\n$st');
      rethrow;
    }

    // ── 4. 断言（仅在不崩时校验） ──
    // 黑块不是真实字形，模型可能返回空串或某个字符，都算正常。
    // 关键是没崩、没抛异常。
    expect(result, isA<String>(),
        reason: 'recognizeImage 应返回 String（空或字符均可）');

    await ocr.dispose();
    // ignore: avoid_print
    print('[OCR-TEST] === DONE 总耗时=${sw.elapsedMilliseconds}ms ===');
  });
}

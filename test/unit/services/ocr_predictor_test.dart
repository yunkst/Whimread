// OcrPredictor 产品化 Task 5：recognizeImage(base64Png) 入口测试。
//
// 测试分两组：
//   1. 结构测试（不依赖 onnxruntime 原生库，必过）：验证无参构造、
//      recognizeImage 方法存在、deprecated PoC 路径（recognizeGlyph）
//      已从源文件移除、源文件 import 了 dart:convert。
//   2. 真实推理测试（需 onnxruntime 原生库）：桌面 flutter test 大概率
//      无 onnxruntime-android 原生库，load() 抛异常时整组不 FAIL
//      （body 内 if-return + print skip 原因）。
import 'dart:convert';
import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/ocr/ocr_predictor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 结构测试（不依赖 onnx，必过）──
  group('OcrPredictor 结构', () {
    test('无参构造存在', () {
      final ocr = OcrPredictor();
      expect(ocr, isA<OcrPredictor>());
    });

    test('recognizeImage 方法存在', () {
      final ocr = OcrPredictor();
      expect(ocr.recognizeImage, isA<Function>());
    });

    test('recognizeGlyph 已从源文件移除（P2 清理生效）', () async {
      final src = await File('lib/services/ocr/ocr_predictor.dart').readAsString();
      expect(src, isNot(contains('recognizeGlyph')),
          reason: 'PoC 入口已被产品 recognizeImage 取代，应已删除');
    });

    test('源文件 import 了 dart:convert', () async {
      final src = await File('lib/services/ocr/ocr_predictor.dart').readAsString();
      expect(src, contains("import 'dart:convert'"));
    });

    test('源文件已无 @Deprecated 注解（P2 清理生效）', () async {
      final src = await File('lib/services/ocr/ocr_predictor.dart').readAsString();
      expect(src, isNot(contains('@Deprecated')),
          reason: 'deprecated PoC 路径已删除，源文件不应再含 @Deprecated');
    });

    test('recognizeImage _session=null 时抛 StateError 而非 NPE', () async {
      final ocr = OcrPredictor();
      // 不调 load()，_session 为 null
      expect(
        () => ocr.recognizeImage('iVBORw0KGgo='), // 随意 base64
        throwsA(isA<StateError>()),
      );
    });
  });

  // ── 真实推理测试（需 onnxruntime 原生库 + 模型资产，不可用则显式 skip）──
  // 桌面 flutter test 无 onnxruntime-android 原生库、asset bundle 也不含
  // 模型文件，load() 会抛 MissingPluginException/PlatformException/
  // DioException/FlutterError(Unable to load asset) —— 均属"环境不具备"，
  // 整组显式 markTestSkipped（CI 报告可见）。其余异常照常 FAIL——旧实现是
  // 裸 catch + body 内 if-return 静默 return，吞掉 predictor 真实回归恒绿。
  group('OcrPredictor.recognizeImage 推理', () {
    late OcrPredictor ocr;
    bool onnxAvailable = false;
    String unavailableReason = '';

    setUpAll(() async {
      ocr = OcrPredictor();
      try {
        await ocr.load();
        onnxAvailable = true;
      } on MissingPluginException catch (e) {
        unavailableReason = 'onnxruntime 不可用（仅 Android/iOS 提供原生库）: $e';
      } on PlatformException catch (e) {
        unavailableReason = 'onnxruntime 原生库加载失败: $e';
      } on DioException catch (e) {
        unavailableReason = '模型文件不可达: ${e.message}';
      } on FlutterError catch (e) {
        // 桌面 test 的 asset bundle 不含模型文件（Unable to load asset）
        unavailableReason = '模型资产缺失: $e';
      }
      if (unavailableReason.isNotEmpty) print('skip: $unavailableReason');
    });

    tearDownAll(() async {
      if (ocr.isLoaded) {
        await ocr.dispose();
      }
    });

    test('空白图返回空字符串', () async {
      if (!onnxAvailable) {
        markTestSkipped(unavailableReason);
        return; // markTestSkipped 是 void，不会中断执行
      }
      final blankBase64 = await _encodeBlankPng();
      final result = await ocr.recognizeImage(blankBase64);
      expect(result, isEmpty);
    });

    test('渲染单个汉字"中"的图识别返回 1-2 字符结果', () async {
      if (!onnxAvailable) {
        markTestSkipped(unavailableReason);
        return;
      }
      final charImg = await _renderCharToBase64('中');
      final result = await ocr.recognizeImage(charImg);
      // OCR 单字识别不保证 100% 命中，但渲染清晰的"中"必须至少给出
      // 非空结果（识别成空串意味着模型/输入管线完全失效），且不超过 2 字符
      expect(result, isNotEmpty, reason: '清晰单字图不应识别为空串');
      expect(result.length, lessThanOrEqualTo(2));
    });
  });
}

// ── helpers ──

/// 120x120 全白 PNG -> base64（无 data:image/png;base64, 前缀）。
Future<String> _encodeBlankPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  final pic = recorder.endRecording();
  final img = await pic.toImage(120, 120);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return base64.encode(bd!.buffer.asUint8List());
}

/// 用系统字体渲染单个汉字到 120x120 PNG -> base64（仅测试用，
/// 产品路径在 WebView canvas 渲染）。
Future<String> _renderCharToBase64(String ch) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);

  final painter = TextPainter(
    text: TextSpan(
      text: ch,
      style: const TextStyle(
        fontSize: 80,
        color: Colors.black,
        decoration: TextDecoration.none,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  );
  painter.layout();

  // 居中绘制
  final dx = (120 - painter.width) / 2;
  final dy = (120 - painter.height) / 2;
  painter.paint(canvas, ui.Offset(dx, dy));
  painter.dispose();

  final pic = recorder.endRecording();
  final img = await pic.toImage(120, 120);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return base64.encode(bd!.buffer.asUint8List());
}

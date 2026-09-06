/// OcrPredictor OrtValue 释放契约测试（P0）+ session 生命周期契约测试（P1）。
///
/// 背景：flutter_onnxruntime 的 Android 端维护插件级
/// `ortValues = ConcurrentHashMap<String, OnnxValue>` 注册表，只有
/// `releaseOrtValue` 会从中移除；`closeSession` 不清空。`recognizeImage`
/// 每次推理创建 1 个 input OrtValue、`runInference` 产出 1 个 output
/// OrtValue，若不显式 dispose，native 内存按 ~634KB/字 永久驻留
/// （番茄场景每章 200+ PUA 字符 ≈ 127MB/章）。
///
/// 通过 mock `flutter_onnxruntime` MethodChannel 计数句柄生命周期：
/// 1. P0：recognizeImage 全部 OrtValue 被释放且恰好一次；
/// 2. P0：runInference 抛异常时 input OrtValue 仍被释放（finally 路径）；
/// 3. P1：重复 load() 先关闭旧 session，dispose 再关当前 session。
///
/// mock 让 runInference 返回全零 logits → CTC argmax=0 → blank → 解码为
/// 空串，只关心句柄生命周期，不关心识别结果。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/poc/ocr_predictor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const onnxChannel = MethodChannel('flutter_onnxruntime');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempDir;
  final createdValueIds = <String>{};
  final releasedValueIds = <String>[];
  var closeSessionCalls = 0;
  var failRunInference = false;
  var nextValueId = 0;

  // mock 的 OrtValue 数据流：
  // - createOrtValue → 登记 input 句柄
  // - runInference → 产出 output 句柄（native 侧创建，不经 createOrtValue）
  // - getOrtValueData → 返回 [1,1,18710] 全零 → asList reshape 后 CTC 全 blank
  Future<Object?> onnxHandler(MethodCall call) async {
    switch (call.method) {
      case 'getAvailableProviders':
        return <String>['CPUExecutionProvider'];
      case 'createSession':
        return <String, Object?>{'sessionId': 'sess-test'};
      case 'getInputInfo':
      case 'getOutputInfo':
        return <Object?>[];
      case 'createOrtValue':
        final id = 'inp-${nextValueId++}';
        createdValueIds.add(id);
        return <String, Object?>{
          'valueId': id,
          'dataType': 'float32',
          'shape': <Object?>[1, 3, 48, 64],
        };
      case 'runInference':
        if (failRunInference) {
          throw PlatformException(
            code: 'INFERENCE_ERROR',
            message: 'mock failure',
          );
        }
        final id = 'out-${nextValueId++}';
        createdValueIds.add(id);
        return <String, Object?>{
          'output': <Object?>[id, 'float32', <Object?>[1, 1, 18710]],
        };
      case 'getOrtValueData':
        return <String, Object?>{
          'data': List<double>.filled(18710, 0.0),
        };
      case 'releaseOrtValue':
        releasedValueIds.add(call.arguments['valueId'] as String);
        return null;
      case 'closeSession':
        closeSessionCalls++;
        return null;
    }
    return null;
  }

  setUp(() {
    createdValueIds.clear();
    releasedValueIds.clear();
    closeSessionCalls = 0;
    failRunInference = false;
    nextValueId = 0;
    tempDir = Directory.systemTemp.createTempSync('ocr_dispose_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(onnxChannel, onnxHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDir.path;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(onnxChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    tempDir.deleteSync(recursive: true);
  });

  /// 本地渲染 8x8 白底 PNG 并转 base64（recognizeImage 入参格式）。
  Future<String> renderSolidPngBase64() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return base64Encode(byteData!.buffer.asUint8List());
  }

  /// 加载 predictor。modelAsset 传字典文件（真实存在于 assets，~百 KB），
  /// 避免单测解压 10MB 的 inference.onnx；mock createSession 不读文件内容。
  Future<OcrPredictor> loadPredictor() async {
    final ocr = OcrPredictor();
    await ocr.load(modelAsset: 'assets/models/ppocrv6_dict.txt');
    return ocr;
  }

  test('P0: recognizeImage 全部 OrtValue 被释放且恰好一次', () async {
    final ocr = await loadPredictor();
    final png = await renderSolidPngBase64();

    const rounds = 50;
    for (var i = 0; i < rounds; i++) {
      await ocr.recognizeImage(png);
    }
    await ocr.dispose();

    expect(createdValueIds.length, rounds * 2,
        reason: '每轮应登记 1 个 input（createOrtValue）+ '
            '1 个 output（runInference 产出）');
    expect(releasedValueIds.length, createdValueIds.length,
        reason: 'P0 回归：release 次数必须等于 create 次数'
            '（修复前 release=0，native ortValues 注册表只增不减，'
            '按 ~634KB/字 泄露）');
    expect(releasedValueIds.toSet(), createdValueIds,
        reason: '每个 OrtValue 恰好释放一次，不多不少');
  });

  test('P0: runInference 抛异常时 input OrtValue 仍被释放', () async {
    final ocr = await loadPredictor();
    final png = await renderSolidPngBase64();
    failRunInference = true;

    await expectLater(
      ocr.recognizeImage(png),
      throwsA(isA<PlatformException>()),
    );

    expect(releasedValueIds.length, 1,
        reason: '推理失败路径 input OrtValue 必须在 finally 中释放');
    await ocr.dispose();
  });

  test('P1: 重复 load() 先关闭旧 session', () async {
    final ocr = await loadPredictor();
    expect(closeSessionCalls, 0);

    await ocr.load(modelAsset: 'assets/models/ppocrv6_dict.txt');
    expect(closeSessionCalls, 1,
        reason: 'P1 回归：二次 load 前必须 close 旧 session，'
            '否则旧 OrtSession + model buffer 驻留 native sessions 注册表');

    await ocr.dispose();
    expect(closeSessionCalls, 2, reason: 'dispose 关闭当前 session');
  });
}

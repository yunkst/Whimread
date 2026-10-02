// 端到端 OCR 还原集成测试：验证 content 还原闭环。
//
// 本文件为集成层冗余测试，作为防御性回归屏障。与 Task 7 单测
// (test/unit/services/ocr_restore_service_test.dart) 的分工：
//   - Task 7 单测：细粒度按 case 分组（无 PUA / 全成功 / 单失败 /
//     renderPua 抛异常 / 去重 decodedRatio 不超 1.0）。
//   - 本集成测试：一个 case 走完整「去重 + 替换 + □ 兜底」编排，
//     另一个 case 验证真实 onnx 模型能加载（CI 无原生库时 skip）。
//
// 集成层冗余是有意为之：单测被重构/精简时，集成测试仍兜底保证
// restorePuaInText 的对外契约不退化。
library;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/ocr_providers.dart';
import 'package:novel_app/services/ocr_restore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restorePuaInText 编排：去重 + 替换 + □ 兜底', () async {
    print('集成层意图：一条用例同时覆盖去重/替换/□兜底三段编排，'
        '作为 Task 7 细粒度单测的回归兜底。');
    // mock renderPua：cp 0xE3E8 返回 'img_A'，其他返回 'img_other'
    // mock predictor：'img_A' → '我'，'img_other' → ''（识别失败）
    final svc = OcrRestoreService.forTesting(
      renderPua: (cp, _) async => cp == 0xE3E8 ? 'img_A' : 'img_other',
      recognizeImageFn: (b64) async => b64 == 'img_A' ? '我' : '',
    );
    // 文本含 0xE3E8 两次（去重应只渲染一次）+ 0xE3E9 一次（失败 → □）
    final text =
        '前${String.fromCharCode(0xE3E8)}中${String.fromCharCode(0xE3E8)}后${String.fromCharCode(0xE3E9)}';
    final r = await svc.restorePuaInText(text, 'F');
    expect(r.totalPuaCount, 2); // 去重后 2 个不同 PUA
    expect(r.decodedCount, 1); // 只有 0xE3E8 成功
    expect(r.text, '前我中我后□');
  });

  test('真实 OcrPredictor 加载（skip if no native lib）', () async {
    print('集成层意图：验证 ocrPredictorProvider 能拉起真实 onnx 模型；'
        '桌面 CI 无 onnxruntime 原生库时显式 skip，不阻塞流水线。');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    try {
      final predictor = await container.read(ocrPredictorProvider.future);
      expect(predictor.isLoaded, isTrue);
    } on MissingPluginException catch (e) {
      // 显式 skip 让 CI 报告可见；其余异常照常失败（旧实现裸 catch +
      // print 恒绿，会吞掉 predictor 的真实回归）
      markTestSkipped('onnxruntime 不可用（仅 Android/iOS 提供原生库）: $e');
      return; // markTestSkipped 是 void，不会中断执行，必须显式返回
    } on PlatformException catch (e) {
      markTestSkipped('onnxruntime 原生库加载失败: $e');
      return;
    } on DioException catch (e) {
      markTestSkipped('模型文件不可达（CI 无网/源不可用）: ${e.message}');
      return;
    } on FlutterError catch (e) {
      markTestSkipped('模型资产缺失（测试环境不打包模型文件）: $e');
      return;
    }
  });
}

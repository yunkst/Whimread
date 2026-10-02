import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/ocr_providers.dart';
import 'package:novel_app/services/ocr/ocr_predictor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ocrPredictorProvider 可解析且 isLoaded', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 环境性失败（桌面 flutter test 无法加载 onnx）显式 skip，CI 报告可见：
    // - MissingPluginException/PlatformException：flutter_onnxruntime 原生库
    //   仅 Android/iOS 提供；
    // - DioException：predictor.load 需要拉取/校验模型文件，CI 无网或源不可达。
    // 注意断言必须放在 try 外——旧实现是裸 catch (e) + print，连 expect 的
    // TestFailure（Error 子类）都会被吞掉，恒绿零覆盖。
    OcrPredictor? predictor;
    try {
      predictor = await container.read(ocrPredictorProvider.future);
    } on MissingPluginException catch (e) {
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

    expect(predictor!.isLoaded, isTrue);
    await predictor!.dispose();
  });
}

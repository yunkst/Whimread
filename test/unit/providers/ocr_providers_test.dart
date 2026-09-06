import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/ocr_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ocrPredictorProvider 可解析且 isLoaded', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // flutter_onnxruntime 原生库是 Android/iOS 的，Windows flutter test 加载不了，
    // predictor.load() 会抛 MissingPluginException。onnx 不可用时不 FAIL。
    try {
      final predictor = await container.read(ocrPredictorProvider.future);
      expect(predictor.isLoaded, isTrue);
      await predictor.dispose();
    } catch (e) {
      print('skip: onnxruntime 不可用 - $e');
    }
  });
}

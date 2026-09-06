library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/image_picker_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImagePickerService', () {
    test('图片字节 > 10MB → 抛 ImageTooLargeException', () async {
      // 直接测 internal 校验逻辑
      final huge = Uint8List(10 * 1024 * 1024 + 1);
      expect(
        () => ImagePickerService.validateSize(huge),
        throwsA(isA<ImageTooLargeException>()),
      );
    });

    test('图片字节 <= 10MB → validateSize 通过', () {
      final ok = Uint8List(1024);
      ImagePickerService.validateSize(ok); // 不抛即通过
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/ocr_restore_service.dart';

void main() {
  group('isPua', () {
    test('PUA-A 范围 U+E000-F8FF', () {
      expect(isPua(0xE000), isTrue);
      expect(isPua(0xE3E8), isTrue); // 番茄实测命中
      expect(isPua(0xF8FF), isTrue);
    });

    test('PUA-B 范围 U+F0000-FFFFD', () {
      expect(isPua(0xF0000), isTrue);
      expect(isPua(0xFFFFD), isTrue);
    });

    test('PUA-C 范围 U+100000-10FFFD', () {
      expect(isPua(0x100000), isTrue);
      expect(isPua(0x10FFFD), isTrue);
    });

    test('边界：范围下限的下一个码点不是 PUA', () {
      expect(isPua(0xDFFF), isFalse); // PUA-A 下界前
      expect(isPua(0xF900), isFalse); // PUA-A 上界后（CJK 兼容）
      expect(isPua(0xFFFFE), isFalse); // PUA-B 上界后
      expect(isPua(0x10FFFE), isFalse); // PUA-C 上界后
    });

    test('常见字符不是 PUA', () {
      expect(isPua(0x4E00), isFalse); // CJK '一'
      expect(isPua(0x0041), isFalse); // 'A'
      expect(isPua(0x3000), isFalse); // 全角空格
    });
  });
}

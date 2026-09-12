/// LlmUsageNotifier 单元测试
///
/// 传输层「AI 使用事件」pub/sub 契约：
/// - notify 扇出到全部 listener
/// - 单个 listener 抛异常不影响其他 listener、不向外抛
///
/// 运行:
///   flutter test test/unit/services/ai/llm_usage_notifier_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/services/ai/llm_usage_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LlmUsageNotifier', () {
    test('notify 扇出到所有已注册 listener', () {
      final n = LlmUsageNotifier.instance;
      var a = 0, b = 0;
      void la() => a++;
      void lb() => b++;
      n.addListener(la);
      n.addListener(lb);

      n.notify();
      n.notify();

      expect(a, 2);
      expect(b, 2);
      n.removeListener(la);
      n.removeListener(lb);
    });

    test('listener 抛异常不阻断其他 listener、不向外抛', () {
      final n = LlmUsageNotifier.instance;
      var called = 0;
      void lo() => throw StateError('消费方崩了');
      void lc() => called++;
      n.addListener(lo);
      n.addListener(lc);

      expect(() => n.notify(), returnsNormally);
      expect(called, 1, reason: '第一个 listener 崩了不应影响第二个');
      n.removeListener(lo);
      n.removeListener(lc);
    });

    test('removeListener 注销后不再被 notify 触发', () {
      final n = LlmUsageNotifier.instance;
      var called = 0;
      void lo() => called++;
      n.addListener(lo);
      n.notify();
      n.removeListener(lo);
      n.notify();
      n.notify();
      expect(called, 1);
    });

    test('无 listener 时 notify 为 no-op', () {
      final n = LlmUsageNotifier.instance;
      // 其他测试残留的 listener 仍存在；只断言不抛
      expect(() => n.notify(), returnsNormally);
    });
  });
}

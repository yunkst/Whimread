/// WebViewPageLoader 单元测试
///
/// 覆盖：
/// - onLoadStop 回调完成 Completer → loadPage 返回 loaded
/// - loadPage 超时返回 PageLoadOutcome.timeout（throwOnTimeout=false）
/// - loadPage 超时抛 PageLoadFailedException（throwOnTimeout=true）
/// - 连续两次 loadPage，第一次 Completer 不影响第二次
/// - 默认常量
///
/// 不覆盖（需集成测试 + 真实 WebView）：
/// - 真实 controller.loadUrl 调用（通过 triggerLoad 注入假回调绕过）
/// - 真实 DOM 稳定延迟效果
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/services/webview_page_loader.dart';
import 'package:novel_app/services/headless_webview_errors.dart';
import 'package:novel_app/services/logger_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LoggerService.resetForTesting();
  });

  /// 构造一个"自动触发 onLoadStop"的 triggerLoad。
  /// 调用后下一事件循环触发 loader 的 onLoadStop 回调，模拟 WebView 加载完成。
  Future<void> Function(String) _autoLoadStopTrigger(
    WebViewPageLoader loader,
  ) {
    return (url) async {
      await Future<void>.delayed(Duration.zero);
      loader.notifyLoadStop(null);
    };
  }

  // ================================================================
  // onLoadStop 回调 → Completer 协调
  // ================================================================
  group('onLoadStop 回调协调', () {
    test('onLoadStop 触发后 loadPage 返回 loaded', () async {
      final loader = WebViewPageLoader();

      final outcome = await loader.loadPage(
        controller: null,
        url: 'https://example.com',
        domStabilizeDelay: Duration.zero,
        triggerLoad: _autoLoadStopTrigger(loader),
      );

      expect(outcome, PageLoadOutcome.loaded);
    });

    test('onLoadStop 未触发 + throwOnTimeout=false 返回 timeout', () async {
      final loader = WebViewPageLoader();

      final outcome = await loader.loadPage(
        controller: null,
        url: 'https://example.com',
        timeout: const Duration(milliseconds: 50),
        domStabilizeDelay: Duration.zero,
        throwOnTimeout: false,
        triggerLoad: (_) async {}, // 不触发 onLoadStop
      );

      expect(outcome, PageLoadOutcome.timeout);
    });

    test('onLoadStop 未触发 + throwOnTimeout=true 抛 PageLoadFailedException', () async {
      final loader = WebViewPageLoader();

      expect(
        () => loader.loadPage(
          controller: null,
          url: 'https://example.com',
          timeout: const Duration(milliseconds: 50),
          domStabilizeDelay: Duration.zero,
          throwOnTimeout: true,
          triggerLoad: (_) async {}, // 不触发 onLoadStop
        ),
        throwsA(isA<PageLoadFailedException>()),
      );
    });

    test('PageLoadFailedException 包含 url 和 userMessage', () async {
      final loader = WebViewPageLoader();

      try {
        await loader.loadPage(
          controller: null,
          url: 'https://test.example.com/chapter1',
          timeout: const Duration(milliseconds: 50),
          domStabilizeDelay: Duration.zero,
          throwOnTimeout: true,
          triggerLoad: (_) async {},
        );
        fail('应该抛异常');
      } on PageLoadFailedException catch (e) {
        expect(e.url, 'https://test.example.com/chapter1');
        expect(e.userMessage, PageLoadFailedException.defaultMessage);
        expect(e.toString(), contains('PageLoadFailedException'));
      }
    });
  });

  // ================================================================
  // Completer 隔离（连续两次 loadPage 不互相干扰）
  // ================================================================
  group('Completer 隔离', () {
    test('第二次 loadPage 的 Completer 不被第一次的残留影响', () async {
      final loader = WebViewPageLoader();

      // 第一次：不触发 onLoadStop，超时
      final outcome1 = await loader.loadPage(
        controller: null,
        url: 'https://example.com/page1',
        timeout: const Duration(milliseconds: 50),
        domStabilizeDelay: Duration.zero,
        throwOnTimeout: false,
        triggerLoad: (_) async {},
      );
      expect(outcome1, PageLoadOutcome.timeout);

      // 第二次：触发 onLoadStop → loaded
      final outcome2 = await loader.loadPage(
        controller: null,
        url: 'https://example.com/page2',
        domStabilizeDelay: Duration.zero,
        triggerLoad: (url) async {
          await Future<void>.delayed(Duration.zero);
          loader.notifyLoadStop(null);
        },
      );
      expect(outcome2, PageLoadOutcome.loaded);
    });
  });

  // ================================================================
  // reset
  // ================================================================
  group('reset', () {
    test('reset 不抛异常', () {
      final loader = WebViewPageLoader();
      expect(() => loader.reset(), returnsNormally);
    });
  });

  // ================================================================
  // 默认常量
  // ================================================================
  group('默认常量', () {
    test('defaultDomStabilizeDelay 是 1500ms', () {
      expect(
        WebViewPageLoader.defaultDomStabilizeDelay,
        const Duration(milliseconds: 1500),
      );
    });

    test('defaultLoadTimeout 是 30s', () {
      expect(
        WebViewPageLoader.defaultLoadTimeout,
        const Duration(seconds: 30),
      );
    });
  });
}

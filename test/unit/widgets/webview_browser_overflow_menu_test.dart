/// WebViewBrowserScreen 溢出菜单 widget 测试
///
/// 验证:
/// - AppBar 含 ⋮ 按钮
/// - 点 ⋮ 弹出含「桌面模式」的菜单
/// - 点「桌面模式」翻转 browserDesktopModeProvider
///
/// 不覆盖真实 InAppWebView 交互（平台类，留手动验收）。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/widgets/webview_browser_overflow_menu_test.dart
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/screens/webview_browser_screen.dart';
import 'package:novel_app/core/providers/webview_providers.dart';

/// 测试用最小 PlatformInAppWebViewWidget 实现，避免真实 WebView 平台依赖。
///
/// WebViewBrowserScreen 在 build 中创建 [InAppWebView]，而
/// `flutter_inappwebview` 要求 `InAppWebViewPlatform.instance` 已注册。
/// 单元测试不验证真实 WebView 交互（平台类），此处返回占位 [SizedBox]。
class _FakeInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _FakeInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      controller as T;

  @override
  void dispose() {}
}

/// 测试用最小 [InAppWebViewPlatform] 实现，仅提供 Widget 构造。
class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) =>
      _FakeInAppWebViewWidget(params);
}

/// 等待 [browserDesktopModeProvider] 完成初始 `_load()` 并离开 loading。
///
/// 手写 StateNotifierProvider 无 `.future`，故用 `listen` + Completer 实现。
Future<void> _waitForDesktopModeLoad(ProviderContainer container) async {
  if (container.read(browserDesktopModeProvider) is! AsyncLoading) return;
  final completer = Completer<void>();
  final sub = container.listen(
    browserDesktopModeProvider,
    (_, next) {
      if (next is! AsyncLoading && !completer.isCompleted) {
        completer.complete();
      }
    },
    fireImmediately: true,
  );
  await completer.future;
  sub.close();
}

void main() {
  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AppBar 含 more_vert 溢出按钮', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WebViewBrowserScreen()),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    // 高频导航仍在外
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('点 ⋮ 弹出含桌面模式的菜单，点击翻转 provider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _waitForDesktopModeLoad(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WebViewBrowserScreen()),
      ),
    );
    await tester.pump();

    // 打开溢出菜单，桌面模式初始未勾选
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('桌面模式'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);

    final before = container.read(browserDesktopModeProvider).value;
    expect(before, isFalse);

    // 点击翻转
    await tester.tap(find.text('桌面模式'));
    await tester.pumpAndSettle();

    final after = container.read(browserDesktopModeProvider).value;
    expect(after, isTrue);

    // 重新打开菜单，桌面模式已勾选
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_box), findsOneWidget);
  });
}

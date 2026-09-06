/// BrowserSettingsNotifier / browserDesktopModeProvider 单元测试
///
/// 验证:
/// - 初始 state 从 SharedPreferences 加载（默认 false）
/// - toggle 翻转 state 并写盘
/// - setDesktopMode 写盘 + 刷新 state
///
/// 未覆盖 `_load` 失败降级为 AsyncError 分支：
/// `BrowserSettingsService` 为单例，难以注入替换；
/// 底层 `PreferencesService.getBool` 内部已 try/catch 并返回 null，
/// 实际触发需 SharedPreferences 层抛异常。该分支仅一行 `state = AsyncValue.error(e, st)`，
/// 逻辑简单，依赖代码审查与手动验收，不单独构造 mock 覆盖。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/providers/browser_desktop_mode_provider_test.dart
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/core/providers/webview_providers.dart';
import 'package:novel_app/services/browser_settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 等待 provider 完成初始 `_load()`（手写 StateNotifier 无 `.future`，
  /// 故用 listen + Completer 等 state 离开 AsyncLoading）。
  Future<void> waitForLoad(ProviderContainer container) async {
    final current = container.read(browserDesktopModeProvider);
    if (current is! AsyncLoading) return;
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

  group('browserDesktopModeProvider', () {
    test('初始 state 为 AsyncData(false)（偏好默认 false）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 等待 _load 完成
      await waitForLoad(container);

      final state = container.read(browserDesktopModeProvider);
      expect(state, isA<AsyncData<bool>>());
      expect(state.value, isFalse);
    });

    test('setDesktopMode(true) 后 state=true 且写盘', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await waitForLoad(container);
      await container
          .read(browserDesktopModeProvider.notifier)
          .setDesktopMode(true);

      expect(container.read(browserDesktopModeProvider).value, isTrue);
      // 写盘验证
      expect(await BrowserSettingsService.instance.isDesktopMode(), isTrue);
    });

    test('toggle 从 false 翻转到 true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await waitForLoad(container);
      expect(container.read(browserDesktopModeProvider).value, isFalse);

      await container.read(browserDesktopModeProvider.notifier).toggle();
      expect(container.read(browserDesktopModeProvider).value, isTrue);

      await container.read(browserDesktopModeProvider.notifier).toggle();
      expect(container.read(browserDesktopModeProvider).value, isFalse);
    });

    test('预置偏好 true 时初始 state 为 AsyncData(true)', () async {
      // 预置持久化值
      await BrowserSettingsService.instance.setDesktopMode(true);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await waitForLoad(container);
      expect(container.read(browserDesktopModeProvider).value, isTrue);
    });
  });

  group('desktopModeSettings', () {
    test('桌面模式: 桌面UA + overview + 缩放支持', () {
      final s = desktopModeSettings(true);
      expect(s.userAgent, BrowserSettingsService.desktopUserAgent);
      expect(s.useWideViewPort, isTrue);
      expect(s.loadWithOverviewMode, isTrue);
      // PC 网页在手机屏字小，需支持手势缩放（双指捏合）
      expect(s.supportZoom, isTrue);
      expect(s.builtInZoomControls, isTrue);
      expect(s.displayZoomControls, isFalse);
    });

    test('手机模式: 空UA + overview=false + 不开桌面缩放按钮', () {
      final s = desktopModeSettings(false);
      expect(s.userAgent, '');
      expect(s.loadWithOverviewMode, isFalse);
      // 显式关闭桌面缩放按钮配置，防止运行时切换 setSettings 残留
      expect(s.builtInZoomControls, isFalse);
      expect(s.displayZoomControls, isFalse);
    });
  });
}

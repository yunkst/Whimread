/// BrowserSettingsService 单元测试
///
/// 验证桌面模式偏好的读写与默认值，以及桌面 UA 常量。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/browser_settings_service_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_app/services/browser_settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BrowserSettingsService', () {
    test('isDesktopMode 默认 false', () async {
      final svc = BrowserSettingsService.instance;
      expect(await svc.isDesktopMode(), isFalse);
    });

    test('setDesktopMode(true) 后 isDesktopMode 返回 true', () async {
      final svc = BrowserSettingsService.instance;
      await svc.setDesktopMode(true);
      expect(await svc.isDesktopMode(), isTrue);
    });

    test('setDesktopMode(false) 后 isDesktopMode 返回 false', () async {
      final svc = BrowserSettingsService.instance;
      await svc.setDesktopMode(true);
      await svc.setDesktopMode(false);
      expect(await svc.isDesktopMode(), isFalse);
    });

    test('desktopUserAgent 是 Windows Chrome 字符串', () {
      expect(BrowserSettingsService.desktopUserAgent,
          contains('Windows NT 10.0'));
      expect(BrowserSettingsService.desktopUserAgent, contains('Chrome/'));
    });

    test('desktopViewportOverrideJs 含桌面宽 viewport 覆盖逻辑', () {
      final js = BrowserSettingsService.desktopViewportOverrideJs;
      // 强制桌面宽，让响应式断点命中桌面分支
      expect(js, contains('width=1200'));
      expect(js, contains('name="viewport"'));
      // 仅桌面 UA 执行：手机 UA 直接 return，不破坏手机布局
      expect(js, contains('Windows NT'));
      expect(js, contains('return;'));
      // 允许用户双指缩放（PC 页在手机屏字小）
      expect(js, contains('user-scalable=yes'));
    });

    test('desktopViewportOverrideJs 锁死 viewport 防篡改', () {
      final js = BrowserSettingsService.desktopViewportOverrideJs;
      // MutationObserver 监听 DOM 变化，站点改回 device-width 时瞬间改回 1200
      expect(js, contains('MutationObserver'));
      expect(js, contains('attributeFilter'));
      // prepend 到 head 最前，确保最先生效
      expect(js, contains('prepend'));
    });
  });
}

/// desktopModeSettings 纯函数单元测试
///
/// 验证桌面/手机模式下 InAppWebViewSettings 的关键字段构造正确。
/// （InAppWebViewController 是平台类无法 mock，故把配置构造抽成纯函数测）
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/providers/desktop_mode_settings_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:novel_app/core/providers/webview_providers.dart';
import 'package:novel_app/services/browser_settings_service.dart';

void main() {
  group('desktopModeSettings', () {
    test('桌面模式: UA=桌面字符串, overview=true, 缩放控件开', () {
      final s = desktopModeSettings(true);
      expect(s.userAgent, BrowserSettingsService.desktopUserAgent);
      expect(s.useWideViewPort, isTrue);
      expect(s.loadWithOverviewMode, isTrue);
      expect(s.builtInZoomControls, isTrue);
      expect(s.displayZoomControls, isFalse);
      expect(s.javaScriptEnabled, isTrue);
    });

    test('手机模式: UA=空(系统默认), overview=false, 缩放控件关', () {
      final s = desktopModeSettings(false);
      expect(s.userAgent, '');
      expect(s.useWideViewPort, isTrue);
      expect(s.loadWithOverviewMode, isFalse);
      expect(s.builtInZoomControls, isFalse);
      expect(s.javaScriptEnabled, isTrue);
    });
  });
}

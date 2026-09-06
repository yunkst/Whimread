import 'preferences_service.dart';

/// 浏览器设置服务
///
/// 管理浏览器相关用户偏好的持久化（目前仅桌面模式开关）。
/// 单例 + SharedPreferences，范式同 [ReaderSettingsService]。
class BrowserSettingsService {
  // ========== 单例模式 ==========
  static BrowserSettingsService? _instance;
  static BrowserSettingsService get instance {
    _instance ??= BrowserSettingsService._();
    return _instance!;
  }

  BrowserSettingsService._();

  // ========== SharedPreferences 键常量 ==========
  static const String _keyDesktopMode = 'browser_desktop_mode';

  // ========== 默认值常量 ==========
  static const bool _defaultDesktopMode = false;

  // ========== 桌面模式 User-Agent ==========
  /// 桌面模式使用的 User-Agent（Edge 131，模拟桌面 Edge：番茄小说对 Windows
  /// 字样敏感，但对 Edge 也认；若失败可换 Chrome 字串）。
  /// 版本号不必追最新，服务器主要看 Windows + 浏览器关键字。
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 '
      'Edg/131.0.0.0';

  /// 桌面模式注入 JS：把 viewport meta 锁死为桌面宽，让响应式站点走 PC 布局。
  ///
  /// 双层防护（应对站点 HTML/JS 篡改 viewport）：
  /// 1. **立即改写**：forceViewport 立刻执行一次，把 meta content 改成桌面宽；
  ///    找不到 meta 则创建并 prepend 到 head 最前，确保早于站点可能声明的
  ///    viewport meta 生效。
  /// 2. **MutationObserver 锁死**：监听 documentElement 的 childList/subtree/
  ///    attributes(content,name)，站点一旦把宽度改回 device-width（或动态
  ///    新建 viewport meta、SPA 路由切换重建 head），瞬间改回 1200。解决旧版
  ///    只在 DOMContentLoaded 兜底一次、被站点后续 JS 覆盖的问题。
  ///
  /// UA 自适配守卫：仅当 UA 含 `Windows NT`（桌面 UA）时执行；手机 UA（空串=
  /// 系统默认）直接 return。**注**：initialUserScripts 对所有导航无条件注入，
  /// 此守卫是手机/桌面共用同一份脚本的关键——运行时切换桌面/手机会 setSettings
  /// UA + reload，reload 后按新 UA 自适配，无需重建 WebView。
  ///
  /// 配套 settings：useWideViewPort + loadWithOverviewMode（见 desktopModeSettings）
  /// 让 1200px 宽页面等比缩放到手机屏宽显示，无需横向滚动；maximum-scale=3.0
  /// 允许双指放大看小字。
  ///
  /// 背景：Android WebView 的 layout viewport 宽度由 viewport meta 决定。移动端
  /// 站点多用 `width=device-width`，layout viewport ≈ 物理屏宽（约 390px），
  /// 响应式断点命中手机分支。仅靠桌面 UA header 让服务器返回 PC 版 HTML 不够——
  /// 响应式站点的前端 JS/CSS 还会按实际 viewport 宽度二次渲染，必须从 JS 层
  /// 把 viewport 锁宽（并防止被站点改回）。
  static const String desktopViewportOverrideJs = r'''
(function() {
  // UA 自适配：仅桌面 UA 执行；手机 UA（空串=系统默认）直接 return 不破坏手机布局
  if (!/Windows NT/.test(navigator.userAgent)) return;

  const DESKTOP_WIDTH = 'width=1200, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';

  // 改写/创建 viewport meta 为桌面宽；创建时 prepend 到 head 最前，确保最先生效
  function forceViewport() {
    let meta = document.querySelector('meta[name="viewport"]');
    if (meta) {
      if (meta.getAttribute('content') !== DESKTOP_WIDTH) {
        meta.setAttribute('content', DESKTOP_WIDTH);
      }
    } else {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      meta.content = DESKTOP_WIDTH;
      if (document.head) {
        document.head.prepend(meta);
      } else {
        const head = document.createElement('head');
        document.documentElement.prepend(head);
        head.appendChild(meta);
      }
    }
  }

  // 1. 立即改写一次
  forceViewport();

  // 2. MutationObserver 锁死：站点篡改 viewport（含 SPA 路由重建 head）瞬间改回
  const observer = new MutationObserver(function() {
    forceViewport();
  });
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['content', 'name']
  });
})();
''';

  // ========== Preferences 服务实例 ==========
  static final PreferencesService _prefs = PreferencesService();

  // ========== 公开方法 ==========

  /// 是否启用桌面模式（键不存在时返回默认 false）
  Future<bool> isDesktopMode() async {
    return _prefs.getBool(_keyDesktopMode, defaultValue: _defaultDesktopMode);
  }

  /// 设置桌面模式开关
  Future<void> setDesktopMode(bool value) async {
    await _prefs.setBool(_keyDesktopMode, value);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/site_script.dart';
import '../../services/logger_service.dart';
import '../../services/bookmark_service.dart';
import '../../services/browser_settings_service.dart';
import 'database_providers.dart';

/// 构造桌面/手机模式的 InAppWebViewSettings
///
/// 把配置构造抽成纯函数以便单测（InAppWebViewController 是平台类无法 mock）。
/// - 桌面: 桌面 UA + loadWithOverviewMode（1200px 页面等比缩到屏宽）+ 缩放控件
/// - 手机: 空 UA(系统默认) + overview=false + 关闭缩放控件
///
/// 桌面布局的真正落地靠 [BrowserSettingsService.desktopViewportOverrideJs]
/// （锁死 viewport 为 1200 宽 + MutationObserver 防篡改 + innerWidth 劫持），
/// 不再依赖 preferredContentMode——实测该字段在 Android WebView 上对响应式
/// 断点无实质作用，仅影响默认 viewport 行为，已被 JS 层 viewport 锁死覆盖。
/// useWideViewPort 两种模式都 true（允许宽视口，避免挤压）。
/// 缩放相关字段在两种模式都显式设置，避免运行时 setSettings 切换残留。
InAppWebViewSettings desktopModeSettings(bool isDesktop) {
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    userAgent: isDesktop ? BrowserSettingsService.desktopUserAgent : '',
    useWideViewPort: true,
    loadWithOverviewMode: isDesktop,
    // PC 网页在手机屏字小，桌面模式允许手势缩放（双指捏合）。
    // 开启缩放控件机制但隐藏 +/- 按钮，避免遮挡内容。
    supportZoom: true,
    builtInZoomControls: isDesktop,
    displayZoomControls: false,
  );
}

// ============================================================
// 浏览器桌面模式开关
// ============================================================

/// 浏览器桌面模式开关状态
///
/// 初始从 [BrowserSettingsService] 加载持久化值；toggle/setDesktopMode
/// 写盘并刷新 state。screen 用 ref.watch 读值注入 initialSettings，
/// 用 ref.listen 触发运行时切换。
final browserDesktopModeProvider =
    StateNotifierProvider<BrowserSettingsNotifier, AsyncValue<bool>>(
  (ref) => BrowserSettingsNotifier(),
);

/// 浏览器桌面模式状态管理
class BrowserSettingsNotifier extends StateNotifier<AsyncValue<bool>> {
  BrowserSettingsNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  /// 从持久化加载初始值；失败降级为 AsyncError（screen 用 value ?? false 兜底）
  Future<void> _load() async {
    try {
      final v = await BrowserSettingsService.instance.isDesktopMode();
      state = AsyncData(v);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 设置桌面模式并持久化
  Future<void> setDesktopMode(bool value) async {
    await BrowserSettingsService.instance.setDesktopMode(value);
    state = AsyncData(value);
  }

  /// 翻转当前模式
  Future<void> toggle() async {
    final current = state.value ?? false;
    await setDesktopMode(!current);
  }
}

/// 当前显示的 URL（地址栏订阅）
final webviewCurrentUrlProvider = StateProvider<String>(
  (ref) => 'https://so.com',
);

/// 加载进度 0.0~1.0
final webviewLoadingProgressProvider = StateProvider<double>((ref) => 0.0);

/// 是否正在加载
final webviewIsLoadingProvider = StateProvider<bool>((ref) => false);

/// InAppWebViewController 持有者
/// 整个屏幕生命周期内复用同一个 controller 实例
final webviewControllerProvider =
    StateNotifierProvider<WebViewControllerNotifier, InAppWebViewController?>(
  (ref) => WebViewControllerNotifier(ref),
);

/// WebView Controller 状态管理
class WebViewControllerNotifier extends StateNotifier<InAppWebViewController?> {
  final Ref _ref;

  WebViewControllerNotifier(this._ref) : super(null);

  /// 由 InAppWebView 的 onWebViewCreated 回调设置 Controller
  void setController(InAppWebViewController controller) {
    state = controller;
  }

  /// 重置 Controller（页面销毁时调用）
  void resetController() {
    state = null;
  }

  /// 页面开始加载
  void handleLoadStart(WebUri? url) {
    _ref.read(webviewCurrentUrlProvider.notifier).state = url?.toString() ?? '';
    _ref.read(webviewIsLoadingProvider.notifier).state = true;
  }

  /// 页面加载完成
  void handleLoadStop(WebUri? url) {
    _ref.read(webviewCurrentUrlProvider.notifier).state = url?.toString() ?? '';
    _ref.read(webviewIsLoadingProvider.notifier).state = false;
    _ref.read(webviewLoadingProgressProvider.notifier).state = 1.0;
  }

  /// 加载进度变化
  void handleProgress(int progress) {
    _ref.read(webviewLoadingProgressProvider.notifier).state = progress / 100.0;
  }

  /// 资源加载错误
  void handleError(WebResourceError error) {
    LoggerService.instance.e(
      'WebView 资源加载错误: ${error.description} (type: ${error.type})',
      category: LogCategory.network,
      tags: ['webview', 'resource-error'],
    );
  }

  /// 加载指定 URL（自动规范化）
  Future<void> loadUrl(String input) async {
    final url = _normalizeUrl(input);
    await state?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  /// 后退
  Future<void> goBack() async {
    await state?.goBack();
  }

  /// 是否可以后退（有浏览历史）
  Future<bool> canGoBack() async {
    return await state?.canGoBack() ?? false;
  }

  /// 前进
  Future<void> goForward() async {
    await state?.goForward();
  }

  /// 刷新
  Future<void> reload() async {
    await state?.reload();
  }

  /// 应用桌面/移动模式配置并 reload
  ///
  /// controller 未就绪（state == null）时静默 return；
  /// 否则用 [desktopModeSettings] 构造配置调 setSettings，再 reload 让新 UA 生效。
  /// 失败仅记录日志，不阻塞 UI（与 [goBack] 超时保护同一思路）。
  Future<void> applyDesktopMode(bool isDesktop) async {
    final controller = state;
    if (controller == null) return;
    try {
      await controller.setSettings(settings: desktopModeSettings(isDesktop));
      await controller.reload();
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        'applyDesktopMode($isDesktop) 失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.network,
        tags: ['webview', 'desktop-mode', 'error'],
      );
    }
  }

  /// URL 规范化
  /// - baidu.com → https://baidu.com
  /// - 小说（无点号）→ 搜索
  /// - https://flutter.dev → 原样
  /// - 空字符串 → so.com
  String _normalizeUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return 'https://so.com';

    // 已有协议前缀，直接使用
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return s;
    }

    // 看起来像域名（含点号且无空格）
    if (s.contains('.') && !s.contains(' ')) {
      return 'https://$s';
    }

    // 否则视为搜索词，使用 360 搜索
    return 'https://so.com/s?q=${Uri.encodeComponent(s)}';
  }
}

// ============================================================
// 收藏夹相关 Providers
// ============================================================

/// 收藏夹列表 Provider
final bookmarkListProvider =
    StateNotifierProvider<BookmarkListNotifier, AsyncValue<List<Bookmark>>>(
  (ref) => BookmarkListNotifier(),
);

/// 收藏分组列表 Provider
final bookmarkGroupListProvider = StateNotifierProvider<
    BookmarkGroupListNotifier, AsyncValue<List<BookmarkGroup>>>(
  (ref) => BookmarkGroupListNotifier(ref),
);

/// 收藏夹状态管理
class BookmarkListNotifier extends StateNotifier<AsyncValue<List<Bookmark>>> {
  BookmarkListNotifier() : super(const AsyncValue.loading()) {
    _loadBookmarks();
  }

  /// 初始化加载收藏夹
  Future<void> _loadBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      final bookmarks = service.loadBookmarks();
      state = AsyncValue.data(bookmarks);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '初始化加载收藏夹失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'init', 'error'],
      );
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// 同步刷新（供分组管理等外部调用）
  void refresh() => _loadBookmarks();

  /// 添加收藏
  Future<void> addBookmark({
    required String title,
    required String url,
    String? groupId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      final bookmark = Bookmark(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        url: url,
        groupId: groupId,
        createdAt: DateTime.now(),
      );
      await service.addBookmark(bookmark);

      // 刷新列表
      final updated = service.loadBookmarks();
      state = AsyncValue.data(updated);

      LoggerService.instance.i(
        '添加收藏: $title ($url, groupId=$groupId)',
        category: LogCategory.database,
        tags: ['bookmark', 'add'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '添加收藏失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'add', 'error'],
      );
    }
  }

  /// 删除收藏
  Future<void> removeBookmark(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      await service.removeBookmark(id);

      // 刷新列表
      final updated = service.loadBookmarks();
      state = AsyncValue.data(updated);

      LoggerService.instance.i(
        '删除收藏: id=$id',
        category: LogCategory.database,
        tags: ['bookmark', 'remove'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除收藏失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'remove', 'error'],
      );
    }
  }

  /// 重命名收藏
  Future<void> renameBookmark(String id, String title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      await service.renameBookmark(id, title);
      state = AsyncValue.data(service.loadBookmarks());
      LoggerService.instance.i(
        '重命名收藏: id=$id -> $title',
        category: LogCategory.database,
        tags: ['bookmark', 'rename'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '重命名收藏失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'rename', 'error'],
      );
    }
  }

  /// 移动收藏到分组（groupId 为 null = 未分组）
  Future<void> moveBookmark(String id, String? groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      await service.moveBookmark(id, groupId);
      state = AsyncValue.data(service.loadBookmarks());
      LoggerService.instance.i(
        '移动收藏: id=$id -> groupId=$groupId',
        category: LogCategory.database,
        tags: ['bookmark', 'move'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '移动收藏失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'move', 'error'],
      );
    }
  }

  /// 检查 URL 是否已收藏
  bool isBookmarked(String url) {
    return state.value?.any((b) => b.url == url) ?? false;
  }
}

/// 收藏分组状态管理
///
/// 与 `BookmarkListNotifier` 互调刷新：删除分组后必须刷收藏列表
/// （收藏的 `groupId` 会变更）。
class BookmarkGroupListNotifier
    extends StateNotifier<AsyncValue<List<BookmarkGroup>>> {
  final Ref _ref;

  BookmarkGroupListNotifier(this._ref) : super(const AsyncValue.loading()) {
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      state = AsyncValue.data(service.loadGroups());
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '加载收藏分组失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'init', 'error'],
      );
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// 同步刷新（供添加/删除收藏等可能影响分组关联的入口调用）
  void refresh() => _loadGroups();

  /// 新建分组（同名校验在 service 内自动去重）
  /// 返回新建的分组（含服务端纠正后的名称）
  Future<BookmarkGroup?> addGroup(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      final group = await service.addGroup(name);
      state = AsyncValue.data(service.loadGroups());
      LoggerService.instance.i(
        '新建收藏分组: ${group.name}',
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'add'],
      );
      return group;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '新建收藏分组失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'add', 'error'],
      );
      return null;
    }
  }

  /// 重命名分组
  Future<void> renameGroup(String id, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      await service.renameGroup(id, name);
      state = AsyncValue.data(service.loadGroups());
      LoggerService.instance.i(
        '重命名收藏分组: id=$id -> $name',
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'rename'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '重命名收藏分组失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'rename', 'error'],
      );
    }
  }

  /// 删除分组（自动将分组内收藏归入「未分组」）
  /// 删除完成后同时刷新收藏列表
  Future<void> deleteGroup(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final service = BookmarkService(prefs);
      await service.deleteGroup(id);
      state = AsyncValue.data(service.loadGroups());
      // 关键：删除分组后，组内收藏的 groupId 已置 null，需刷新
      _ref.read(bookmarkListProvider.notifier).refresh();
      LoggerService.instance.i(
        '删除收藏分组: id=$id',
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'delete'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除收藏分组失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookmark', 'group', 'delete', 'error'],
      );
    }
  }
}

// ============================================================
// 站点脚本相关 Providers
// ============================================================

/// 脚本列表 Provider
final siteScriptListProvider =
    StateNotifierProvider<SiteScriptListNotifier, AsyncValue<List<SiteScript>>>(
  (ref) => SiteScriptListNotifier(ref),
);

/// 脚本列表状态管理
class SiteScriptListNotifier
    extends StateNotifier<AsyncValue<List<SiteScript>>> {
  final Ref _ref;

  SiteScriptListNotifier(this._ref) : super(const AsyncValue.loading()) {
    _loadScripts();
  }

  /// 初始化加载脚本列表
  Future<void> _loadScripts() async {
    try {
      final repository = _ref.read(siteScriptRepositoryProvider);
      final scripts = await repository.getAll();
      state = AsyncValue.data(scripts);
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '加载脚本列表失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'load', 'error'],
      );
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// 删除脚本
  Future<void> deleteScript(String id) async {
    try {
      final repository = _ref.read(siteScriptRepositoryProvider);
      await repository.delete(id);
      await _loadScripts();
      LoggerService.instance.i(
        '删除脚本: id=$id',
        category: LogCategory.database,
        tags: ['site_script', 'delete'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除脚本失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'delete', 'error'],
      );
    }
  }

  /// 删除域名的所有脚本
  Future<void> deleteScriptByDomain(String domain) async {
    try {
      final repository = _ref.read(siteScriptRepositoryProvider);
      await repository.deleteByDomain(domain);
      await _loadScripts();
      LoggerService.instance.i(
        '删除域名脚本: domain=$domain',
        category: LogCategory.database,
        tags: ['site_script', 'delete', 'domain'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除域名脚本失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'delete', 'domain', 'error'],
      );
    }
  }

  /// 标记脚本已验证
  Future<void> verifyScript(String id) async {
    try {
      final repository = _ref.read(siteScriptRepositoryProvider);
      await repository.setVerified(id, true);
      await repository.markUsed(id);
      await _loadScripts();
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '验证脚本失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['site_script', 'verify', 'error'],
      );
    }
  }

  /// 刷新脚本列表
  void refresh() => _loadScripts();
}

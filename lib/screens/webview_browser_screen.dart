import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../core/providers/webview_providers.dart';
import '../core/theme/app_colors.dart';
import '../services/logger_service.dart';
import '../widgets/webview_address_bar.dart';
import '../widgets/bookmark_panel.dart';
import '../widgets/site_script_panel.dart';
import '../widgets/webview_add_novel_button.dart';

/// 浏览器主屏幕
///
/// 布局：
/// - AppBar: 地址栏 + 右侧前进/后退/刷新/收藏夹按钮
/// - 顶部加载进度条（仅在加载中显示）
/// - 主体：InAppWebView 内容
/// - 系统返回手势：有历史时 WebView 后退，无历史时退出浏览器页面
///
/// [active] 标记当前浏览器是否为可见的 Tab。在 IndexedStack 常驻布局下，
/// 浏览器即使不可见（offstage）仍挂载在树上，其 PopScope 也会参与返回键分发。
/// 因此仅在 active 时拦截系统返回手势，避免在其他 Tab 误触发 WebView 后退。
class WebViewBrowserScreen extends ConsumerStatefulWidget {
  const WebViewBrowserScreen({super.key, this.active = true});

  /// 当前是否为可见的 Tab
  final bool active;

  @override
  ConsumerState<WebViewBrowserScreen> createState() =>
      _WebViewBrowserScreenState();
}

class _WebViewBrowserScreenState extends ConsumerState<WebViewBrowserScreen> {
  bool _addressBarFocused = false;
  final _addressBarKey = GlobalKey<WebViewAddressBarState>();

  // ============================================================
  // InteractiveViewer 桌面模式验证状态
  // ============================================================

  /// InteractiveViewer 的 TransformationController
  final TransformationController _transformController =
      TransformationController();

  /// 桌面模式 WebView 的估计高度。设为屏宽比例对应的高度。
  /// 1200px 宽对应 content，高度随内容自然增长。
  static const double _desktopWebViewWidth = 1200.0;

  /// 在网页 document 上安装 touchstart/mousedown 监听器，
  /// 用户点击网页任何内容时通过 JS handler 通知 Flutter 取消地址栏焦点。
  static const String _installWebViewTapHandlerJs = '''
(function() {
  if (window.__webViewTapInstalled) return;
  window.__webViewTapInstalled = true;

  function notifyWebViewTapped() {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('onWebViewTouched');
    }
  }

  document.addEventListener('touchstart', notifyWebViewTapped, { passive: true });
  document.addEventListener('mousedown', notifyWebViewTapped, { passive: true });
})();
''';

  /// 单拍诊断 JS：输出当前 innerWidth / innerHeight / viewport / UA
  static const String _diagnosticJs = r'''
(function(){
  var m = document.querySelector('meta[name="viewport"]');
  window.__desktopDiag = JSON.stringify({
    ua: navigator.userAgent,
    platform: navigator.platform,
    maxTouch: navigator.maxTouchPoints,
    viewport: m ? m.content : '(none)',
    width: window.innerWidth,
    height: window.innerHeight,
    screenW: screen.width,
    screenH: screen.height,
    url: location.href
  });
  return window.__desktopDiag;
})();
''';

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(webviewIsLoadingProvider);
    final progress = ref.watch(webviewLoadingProgressProvider);
    final notifier = ref.read(webviewControllerProvider.notifier);
    final desktopMode = ref.watch(browserDesktopModeProvider).value ?? false;

    // 桌面模式变化（仅手动 toggle）-> 运行时切换 WebView 设置
    // 跳过首次 loading->data 转换（prev == null），避免启动时不必要的 reload
    ref.listen<AsyncValue<bool>>(browserDesktopModeProvider, (prev, next) {
      if (prev != null && next is AsyncData<bool>) {
        ref
            .read(webviewControllerProvider.notifier)
            .applyDesktopMode(next.value);
      }
    });

    return PopScope(
      // 仅在当前 Tab 可见时拦截系统返回手势；不可见时让返回键正常向上传递。
      canPop: !widget.active,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        bool canBack;
        try {
          canBack = await notifier.canGoBack().timeout(
                const Duration(milliseconds: 500),
              );
        } catch (_) {
          canBack = false;
        }
        if (canBack) {
          try {
            await notifier.goBack().timeout(
                  const Duration(seconds: 3),
                );
          } catch (_) {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: WebViewAddressBar(
              key: _addressBarKey,
              onFocusChanged: (focused) {
                setState(() => _addressBarFocused = focused);
              },
            ),
          ),
          actions: _addressBarFocused
              ? null
              : [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    tooltip: '后退',
                    onPressed: () => notifier.goBack(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    tooltip: '前进',
                    onPressed: () => notifier.goForward(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新',
                    onPressed: () => notifier.reload(),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: '更多',
                    onSelected: (value) async {
                      switch (value) {
                        case 'bookmark':
                          _showBookmarkPanel(context, notifier);
                          break;
                        case 'script':
                          _showScriptPanel(context);
                          break;
                        case 'desktopMode':
                          await ref
                              .read(browserDesktopModeProvider.notifier)
                              .toggle();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem<String>(
                        value: 'bookmark',
                        child: Text('收藏夹'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'script',
                        child: Text('脚本管理'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'desktopMode',
                        child: Row(
                          children: [
                            Icon(
                              ref.watch(browserDesktopModeProvider).value ??
                                      false
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                            ),
                            const SizedBox(width: 8),
                            const Text('桌面模式'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // 加载进度条
                if (isLoading)
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      context.appColors.agentAccent,
                    ),
                    backgroundColor:
                        context.appColors.agentAccent.withValues(alpha: 0.15),
                  ),
                // WebView 主体：桌面模式走 InteractiveViewer 验证分支
                Expanded(
                  child: _buildWebView(desktopMode, notifier),
                ),
              ],
            ),
            // 右下角「添加小说」悬浮按钮
            const Positioned(
              right: 16,
              bottom: 16,
              child: WebViewAddNovelFab(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WebView 构建
  // ============================================================

  /// 根据桌面/手机模式构建 WebView
  ///
  /// 桌面模式（InteractiveViewer 验证分支）：
  /// - WebView 放在 [SizedBox(width: 1200)] 中，物理宽度 = 1200px
  /// - 外层 [InteractiveViewer] 负责双指缩放（panEnabled=false，单指不拦截）
  /// - **验证目的**：确认单指手势能否穿透 InteractiveViewer 到达 WebView
  /// - 不再注入 viewportOverrideJs（不需要了，物理宽度已足够）
  /// - UA 仍设为桌面 UA
  ///
  /// 手机模式：保持原有实现不变。
  ///
  /// **关键**：InAppWebView 本身始终挂载在树中（key 不变），只是外层是否包裹
  /// InteractiveViewer + SizedBox 会随 [desktopMode] 变化。这样切换桌面模式时
  /// Flutter 只重建外层 wrapper 而不销毁 WebView，保持页面状态和浏览历史。
  Widget _buildWebView(bool desktopMode, WebViewControllerNotifier notifier) {
    // InAppWebView 本体：两种模式共用同一个 widget 实例
    final webView = InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://so.com')),
      initialSettings: desktopModeSettings(desktopMode),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _installWebViewTapHandlerJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        notifier.setController(controller);
        controller.addJavaScriptHandler(
          handlerName: 'onWebViewTouched',
          callback: (arguments) {
            _unfocusAddressBar();
            return null;
          },
        );
      },
      onLoadStart: (controller, url) {
        notifier.handleLoadStart(url);
      },
      onLoadStop: (controller, url) {
        notifier.handleLoadStop(url);
        if (desktopMode) {
          controller.evaluateJavascript(source: _diagnosticJs).then((value) {
            LoggerService.instance.d(
              'WebView 桌面化诊断: $value',
              category: LogCategory.network,
              tags: ['webview', 'desktop-mode', 'diag'],
            );
          });
        }
      },
      onProgressChanged: (controller, progress) {
        notifier.handleProgress(progress);
      },
      onReceivedError: (controller, request, error) {
        notifier.handleError(error);
      },
    );

    // 桌面模式：用 InteractiveViewer 包裹，物理宽 1200px
    //
    // InteractiveViewer(constrained: false) 让子组件可以有自己的"世界尺寸"
    // （1200px 宽），再由 Matrix4 初始缩放缩到屏宽。这是方案的核心——
    // WebView 在 Android 上拿到真实的 1200px 物理宽度，CSS 断点命中桌面分支。
    //
    // 已知问题：Platform View（WebView）在 constrained:false 的 InteractiveViewer
    // 中可能渲染不全。这是 Android TextureView/VirtualDisplay 的固有行为——
    // 系统只给 Platform View 分配屏幕可见区域的纹理大小。
    if (desktopMode) {
      final screenWidth = MediaQuery.of(context).size.width;
      final initialScale = screenWidth / _desktopWebViewWidth;

      // 在 Matrix4 中设初始缩放
      _transformController.value =
          Matrix4.diagonal3Values(initialScale, initialScale, 1.0);

      return LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;

          return InteractiveViewer(
            transformationController: _transformController,
            panEnabled: false,
            scaleEnabled: true,
            minScale: 0.5,
            maxScale: 3.0,
            constrained: false,
            child: SizedBox(
              width: _desktopWebViewWidth,
              // 高度按反算：缩放后应填满 availableHeight
              // 世界高度 = availableHeight / initialScale
              height: availableHeight / initialScale,
              child: webView,
            ),
          );
        },
      );
    }

    // 手机模式：直接返回 WebView，不包裹
    return webView;
  }

  /// 取消地址栏焦点（用户在网页内点击时由 JS handler 触发）
  void _unfocusAddressBar() {
    _addressBarKey.currentState?.unfocus();
  }

  /// 弹出收藏夹面板
  void _showBookmarkPanel(
    BuildContext context,
    WebViewControllerNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BookmarkPanel(
        onNavigate: (url) => notifier.loadUrl(url),
      ),
    );
  }

  /// 弹出脚本管理面板
  void _showScriptPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SiteScriptPanel(),
    );
  }
}

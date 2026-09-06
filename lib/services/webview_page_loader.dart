/// 共用的 Headless WebView 页面加载等待工具
///
/// 用 `onLoadStop` 事件驱动替代原来基于 URL 字符串轮询的加载判断。
///
/// ## 设计要点
///
/// `HeadlessInAppWebView` 支持**创建时**（构造参数）注册 `onLoadStop` 等回调，
/// 但不支持创建后动态添加。因此本工具的使用方式是：
///
/// 1. 在 `HeadlessInAppWebView` 构造时把 [onLoadStopCallback] 传入 `onLoadStop`
///    参数（常驻回调）。
/// 2. 每次 [loadPage] 调用前重置内部的 `Completer`，回调触发时完成它。
///
/// 这样既能在创建期注册回调，又能在运行期精确等待"本次"加载完成。
///
/// ## 加载完成的两层保障
///
/// 1. `onLoadStop` —— 浏览器内核触发的"页面及子资源加载完成"信号，
///    比比较 `getUrl()` 字符串可靠（不受重定向/URL 规范化影响）。
/// 2. [defaultDomStabilizeDelay] —— `onLoadStop` 后额外等待，覆盖 AJAX 动态
///    渲染的正文/列表内容。原实现固定 500ms 偏短，此处默认 1500ms。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'headless_webview_errors.dart';
import 'logger_service.dart';

/// 页面加载结果
enum PageLoadOutcome {
  /// 加载成功（onLoadStop 已触发 + DOM 稳定延迟已等待）
  loaded,

  /// 加载超时（onLoadStop 未在时限内触发，未抛异常的降级模式）
  timeout,
}

class WebViewPageLoader {
  /// onLoadStop 后额外等待的 DOM 稳定时间（覆盖 AJAX 动态渲染）。
  ///
  /// 静态常量便于全局调整；调用方也可通过 [loadPage] 的 `domStabilizeDelay`
  /// 参数对单次加载覆盖。
  static const Duration defaultDomStabilizeDelay = Duration(milliseconds: 1500);

  /// onLoadStop 总等待上限。
  static const Duration defaultLoadTimeout = Duration(seconds: 30);

  /// 当前等待中的加载 Completer。每次 [loadPage] 重置，[onLoadStopCallback]
  /// 触发时完成。
  Completer<void>? _loadCompleter;

  /// 供 `HeadlessInAppWebView` 构造时传入的 `onLoadStop` 回调（常驻）。
  ///
  /// 内部通过重置 [_loadCompleter] 实现每次 [loadPage] 的独立等待，
  /// 因此回调可常驻注册而不会误完成上一次的等待。
  void onLoadStopCallback(InAppWebViewController controller, WebUri? uri) {
    notifyLoadStop(uri);
  }

  /// 通知一次页面加载完成（onLoadStop 触发）。
  ///
  /// [onLoadStopCallback] 的内部实现，单独暴露便于在不持有 controller 的
  /// 场景（如单元测试）触发完成信号。
  @visibleForTesting
  void notifyLoadStop(WebUri? uri) {
    LoggerService.instance.d(
      'WebViewPageLoader: onLoadStop uri=$uri',
      category: LogCategory.cache,
      tags: ['headless-webview', 'page-loader', 'onLoadStop'],
    );
    final c = _loadCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  /// 加载页面并等待 `onLoadStop`。
  ///
  /// [controller] Headless WebView 控制器（必须已绑定 [onLoadStopCallback]）。
  /// [url] 目标 URL。
  /// [domStabilizeDelay] `onLoadStop` 后额外等待（默认 [defaultDomStabilizeDelay]）。
  /// [timeout] `onLoadStop` 总等待上限（默认 [defaultLoadTimeout]）。
  /// [throwOnTimeout] 为 true 时超时抛 [PageLoadFailedException]；
  ///   为 false 时返回 [PageLoadOutcome.timeout]（向后兼容"信任 loadUrl 继续"的
  ///   旧调用方，例如章节内容获取的容错路径）。
  /// [triggerLoad] 触发页面加载的回调（默认调用 `controller.loadUrl`）。
  ///   抽出为参数便于单元测试注入（测试环境无法构造真实 controller）。
  Future<PageLoadOutcome> loadPage({
    /// Headless WebView 控制器（必须已绑定 [onLoadStopCallback]）。
    /// 可空：仅当未提供 [triggerLoad] 时（生产路径）才实际使用它来 loadUrl；
    /// 测试路径通过 [triggerLoad] 注入假加载逻辑，可传 null。
    InAppWebViewController? controller,
    required String url,
    Duration domStabilizeDelay = defaultDomStabilizeDelay,
    Duration timeout = defaultLoadTimeout,
    bool throwOnTimeout = true,
    /// 触发页面加载的回调。默认调用 `controller.loadUrl`。
    /// 抽出为参数便于单元测试注入（测试环境无法构造真实 controller）。
    /// 回调参数 [url] 为目标 URL。
    Future<void> Function(String url)? triggerLoad,
  }) async {
    // 关键：每次 loadPage 重置 Completer，避免上一次 onLoadStop 残留完成
    _loadCompleter = Completer<void>();
    final waiter = _loadCompleter!;

    if (triggerLoad != null) {
      await triggerLoad(url);
    } else {
      assert(controller != null,
          'controller 必须非空（未提供 triggerLoad 时用默认 loadUrl 触发）');
      await controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }

    try {
      await waiter.future.timeout(timeout);
    } on TimeoutException {
      LoggerService.instance.w(
        'WebViewPageLoader: onLoadStop 等待超时 url=$url',
        category: LogCategory.cache,
        tags: ['headless-webview', 'page-loader', 'load-timeout'],
      );
      if (throwOnTimeout) {
        throw PageLoadFailedException(url);
      }
      return PageLoadOutcome.timeout;
    } finally {
      _loadCompleter = null;
    }

    // onLoadStop 触发后给 AJAX 动态渲染留时间
    await Future.delayed(domStabilizeDelay);
    return PageLoadOutcome.loaded;
  }

  /// 重置内部状态（取消任何挂起的等待，不抛异常）。
  void reset() {
    _loadCompleter = null;
  }
}

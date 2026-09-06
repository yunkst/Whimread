/// Headless WebView 池管理器
///
/// 通用 Headless WebView 生命周期管理，**当前仅供 AI Agent `WebViewExtractScenario`
/// 使用**。`HeadlessWebViewContentService`（章节内容）和
/// `HeadlessWebViewChapterListService`（章节列表）各自自管独立的 WebView 实例，
/// 不经过本池，以彻底避免并发 loadUrl 互相覆盖 URL 的问题。
///
/// ## 排他锁
///
/// `acquire()`/`release()` 之间形成临界区：同一时刻只有一个调用方持有 controller
/// 的使用权。第二个 `acquire()` 会等待前一个 `release()` 后才返回，从而避免多个
/// 调用方并发操作同一个 WebView（loadUrl / callAsyncJavaScript 互相覆盖）。
///
/// ## 资源管理
///
/// - 单例懒初始化，整个 APP 生命周期内只创建一次
/// - 引用计数（_refCount）允许观察使用情况（当前不强制释放）
/// - 单 flight：`acquire()` 并发初始化会等待同一个初始化过程
///
/// ## 与原有 service 的关系
///
/// 本池与 `HeadlessWebViewContentService` / `HeadlessWebViewChapterListService`
/// 解耦：这两个 service 各自独立持有 WebView；本池专供 Agent 提取场景使用。
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logger_service.dart';
import 'novel_agent/scenarios/network_request_recorder.dart';

/// Headless WebView 池：单例懒初始化，复用同一 WebView 实例
class HeadlessWebViewPool {
  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitializing = false;
  int _refCount = 0;

  // ===== 排他锁 =====

  /// controller 是否正被某个调用方占用
  bool _isInUse = false;

  /// 当前绑定的网络请求观察器（可空）。
  ///
  /// 由 WebViewExtractScenario 在 acquire 前设置、cleanup 时置 null。
  /// 构造时的 shouldInterceptRequest / onLoadStart 回调在调用时读取本字段，
  /// 始终命中当前场景的 recorder（无需重建 webview）。
  NetworkRequestRecorder? networkRecorder;

  /// 等待获取使用权的调用方队列
  final List<Completer<void>> _waitQueue = [];

  /// 排他等待超时：避免某个调用方忘记 release 导致后续调用方永久阻塞。
  static const Duration _acquireWaitTimeout = Duration(seconds: 30);

  /// 是否已就绪
  bool get isReady => _controller != null;

  /// 获取一个 Headless WebView controller（排他占用，直到 [release]）。
  ///
  /// 第一次调用会执行初始化（约 1-3 秒）；后续调用复用同一个 controller。
  /// 并发调用会排队等待前一个 [release] 后才返回（排他锁）。
  ///
  /// 抛异常表示初始化失败或排他等待超时。
  Future<InAppWebViewController> acquire() async {
    _refCount++;
    LoggerService.instance.d(
      'HeadlessWebViewPool.acquire: refCount=$_refCount isInUse=$_isInUse',
      category: LogCategory.cache,
      tags: ['headless-webview-pool', 'acquire'],
    );
    try {
      await _ensureReady();
      // 排他等待：直到上一个持有者 release
      await _waitForUseRight();
      _isInUse = true;
      return _controller!;
    } catch (e, stackTrace) {
      _refCount--;
      LoggerService.instance.w(
        'HeadlessWebViewPool.acquire 失败: $e refCount=$_refCount',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview-pool', 'acquire', 'failed'],
      );
      rethrow;
    }
  }

  /// 等待获取使用权（排他锁的核心）。
  Future<void> _waitForUseRight() async {
    if (!_isInUse) return;

    final waiter = Completer<void>();
    _waitQueue.add(waiter);
    try {
      await waiter.future.timeout(_acquireWaitTimeout, onTimeout: () {
        _waitQueue.remove(waiter);
        throw TimeoutException('HeadlessWebViewPool acquire 排他等待超时');
      });
    } catch (e, stackTrace) {
      _waitQueue.remove(waiter);
      LoggerService.instance.w(
        'HeadlessWebViewPool 排他等待失败: $e waitQueue=${_waitQueue.length}',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview-pool', 'acquire', 'timeout'],
      );
      rethrow;
    }
  }

  /// 释放使用权并唤醒下一个等待者；同时减少引用计数。
  ///
  /// 调用方必须在 `acquire()` 成功后的 finally 中调用本方法，
  /// 否则会阻塞所有后续 acquire。
  void release() {
    _isInUse = false;
    if (_refCount > 0) _refCount--;

    // 唤醒下一个等待者
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      if (!next.isCompleted) {
        next.complete();
      }
    }

    LoggerService.instance.d(
      'HeadlessWebViewPool.release: refCount=$_refCount isInUse=$_isInUse',
      category: LogCategory.cache,
      tags: ['headless-webview-pool', 'release'],
    );
  }

  /// 当前引用计数
  int get refCount => _refCount;

  /// controller 是否正被占用
  bool get isInUse => _isInUse;

  /// 销毁（理论上不需要，由 Riverpod 生命周期管理）
  void dispose() {
    LoggerService.instance.i(
      'HeadlessWebViewPool.dispose: refCount=$_refCount',
      category: LogCategory.cache,
      tags: ['headless-webview-pool', 'dispose'],
    );
    // 唤醒所有等待者，避免悬挂 Completer
    for (final w in _waitQueue) {
      if (!w.isCompleted) w.complete();
    }
    _waitQueue.clear();
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _controller = null;
    _refCount = 0;
    _isInUse = false;
  }

  // ===== 内部 =====

  Future<void> _ensureReady() async {
    if (_controller != null) return;

    if (_isInitializing) {
      // 等待初始化完成（每 500ms 轮询，最多 30s）
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller != null) return;
      }
      LoggerService.instance.w(
        'HeadlessWebViewPool: 初始化超时（30s 轮询）',
        category: LogCategory.cache,
        tags: ['headless-webview-pool', 'init', 'timeout'],
      );
      throw Exception('HeadlessWebViewPool 初始化超时');
    }

    _isInitializing = true;
    try {
      final completer = Completer<InAppWebViewController>();

      _headlessWebView = HeadlessInAppWebView(
        onWebViewCreated: (controller) {
          if (!completer.isCompleted) {
            completer.complete(controller);
          }
        },
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          // 不加载图片，节省流量和时间
          loadsImagesAutomatically: false,
          // 禁用不需要的功能
          mediaPlaybackRequiresUserGesture: true,
          // 启用网络请求观察（Android 专属；iOS 该 setting 为 no-op）
          useShouldInterceptRequest: Platform.isAndroid,
        ),
        // 页面跳转即清空 recorder（仅 Android 有意义）
        onLoadStart: (controller, url) {
          networkRecorder?.clear();
        },
        // 观察所有请求，return null 放行不打断页面
        shouldInterceptRequest: (controller, request) async {
          _recordRequest(request);
          return null;
        },
      );

      await _headlessWebView!.run();
      _controller = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('WebView 创建超时'),
      );

      LoggerService.instance.i(
        'HeadlessWebViewPool: 初始化完成',
        category: LogCategory.cache,
        tags: ['headless-webview-pool', 'init'],
      );
    } catch (e) {
      _isInitializing = false;
      // 初始化失败时清理
      _headlessWebView?.dispose();
      _headlessWebView = null;
      _controller = null;
      LoggerService.instance.e(
        'HeadlessWebViewPool: 初始化失败 $e',
        category: LogCategory.cache,
        tags: ['headless-webview-pool', 'init', 'error'],
      );
      rethrow;
    }
    _isInitializing = false;
  }

  /// 把一条 WebResourceRequest 记入 networkRecorder（观察模式，return null 放行）。
  ///
  /// 异常时丢弃该条 + 打日志，不阻断页面加载（回调仍返回 null）。
  void _recordRequest(WebResourceRequest request) {
    final recorder = networkRecorder;
    if (recorder == null) return;
    try {
      recorder.add(
        url: request.url.toString(),
        method: request.method,
        headers: request.headers,
        isForMainFrame: request.isForMainFrame ?? false,
      );
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        'HeadlessWebViewPool 网络请求记录失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.network,
        tags: ['headless-webview-pool', 'network-record', 'failed'],
      );
    }
  }
}

/// 全局 Headless WebView 池 Provider（keepAlive，APP 级别单例）
final headlessWebViewPoolProvider = Provider<HeadlessWebViewPool>((ref) {
  final pool = HeadlessWebViewPool();
  ref.onDispose(() => pool.dispose());
  return pool;
});

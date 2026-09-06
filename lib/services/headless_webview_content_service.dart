/// Headless WebView 章节内容获取服务
///
/// 当某个域名已有 AI Agent 生成的 `chapter_content_js` 提取脚本时，
/// 本服务使用 HeadlessInAppWebView 直接加载章节页面并执行脚本获取内容，
/// 绕过后端 API → 爬虫链路。
///
/// ## 工作流程
///
/// ```
/// fetchContent(url, priority)
///   → SiteScriptRepository.getByDomain(domain)
///   → 无脚本 → return FetchContentResult.noScript()
///   → 有脚本 → 检查 _isFetching
///              → 忙且可抢占 → 设置 _shouldYield，等待让出
///              → 忙且不可抢占 → return FetchContentResult.busy()
///              → 空闲 → HeadlessInAppWebView.loadUrl(url)
///                       → callAsyncJavaScript(chapter_content_js)
///                       → 解析 JSON {title, content}
///                       → 校验 content.length > 50
///                       → return FetchContentResult.success(...)
/// ```
///
/// ## 优先级抢占
///
/// - 阅读器前台请求使用 [FetchPriority.high]，可抢占预加载的 [FetchPriority.low] 任务
/// - 被抢占的低优先级请求在下一个检查点（页面加载后 / 脚本执行中每 3 秒）退出
/// - 高优先级请求等待低优先级让出，最多 5 秒
///
/// ## 资源管理
///
/// - HeadlessInAppWebView 是单例，懒初始化
/// - 超时：页面加载 30s，脚本执行 60s（3 秒粒度检查抢占信号）
/// - 连续失败 3 次自动标记脚本 `verified = 0`
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chapter_content_result.dart';
import '../repositories/site_script_repository.dart';
import '../services/logger_service.dart';
import '../services/novel_agent/scenarios/webview_js_executor.dart';
import 'headless_webview_errors.dart';
import 'ocr_pua_renderer.dart';
import 'ocr_restore_service.dart';
import 'webview_page_loader.dart';

class HeadlessWebViewContentService {
  final SiteScriptRepository _scriptRepo;
  final Ref? _ref; // 产品路径非 null（读 ocrPredictorProvider），测试可不传

  HeadlessWebViewContentService({
    required SiteScriptRepository scriptRepo,
    Ref? ref,
  })  : _scriptRepo = scriptRepo,
        _ref = ref;

  // ===== Headless WebView 单例 =====

  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitializing = false;
  bool _isFetching = false;

  /// 共用页面加载工具（onLoadStop 事件驱动）
  final WebViewPageLoader _pageLoader = WebViewPageLoader();

  // ===== 优先级抢占 =====

  /// 当前正在执行的请求的优先级
  FetchPriority _currentPriority = FetchPriority.low;

  /// 当前正在执行的请求的 URL（用于日志）
  String? _currentFetchingUrl;

  /// 低优先级请求是否应该让出（被高优先级抢占时设为 true）
  bool _shouldYield = false;

  /// 让出信号：低优先级请求创建并 complete，
  /// 高优先级请求通过 [Completer.future] 等待低优先级让出（替代 500ms 轮询）。
  Completer<void>? _yieldedSignal;

  // ===== 脚本健康度追踪 =====

  /// 脚本连续失败次数（内存，不持久化）
  final Map<String, int> _scriptFailureCount = {};

  /// 连续失败多少次后自动标记 unverified
  static const int _maxConsecutiveFailures = 3;

  // ===== 公开 API =====

  /// 尝试用 Headless WebView 获取章节内容。
  ///
  /// [priority] 请求优先级，默认 [FetchPriority.low]。
  ///   - [FetchPriority.high]：阅读器前台请求，可抢占正在执行的低优先级任务
  ///   - [FetchPriority.low]：预加载、历史上下文等后台任务
  ///
  /// 返回 [FetchContentResult] 明确区分以下情况：
  /// - `isSuccess`：获取成功，通过 `.content` 获取结果
  /// - `isNoScript`：该域名无提取脚本，不可重试
  /// - `isBusy`：WebView 正忙（被互斥拦截），可等待重试
  /// - `isLoadFailed`：页面加载失败（onLoadStop 超时/错误）或非解析类异常，可重试
  /// - `isScriptError`：脚本结果 JSON 解析失败（FormatException），脚本本身有缺陷
  Future<FetchContentResult> fetchContent(
    String chapterUrl, {
    FetchPriority priority = FetchPriority.low,
  }) async {
    // ===== 互斥检查 + 优先级抢占 =====
    if (_isFetching) {
      if (priority == FetchPriority.high &&
          _currentPriority == FetchPriority.low) {
        // 高优先级抢占：通知当前低优先级请求让出
        _shouldYield = true;
        LoggerService.instance.i(
          'HeadlessWebView: 高优先级请求抢占，通知低优先级让出 '
          'newUrl=$chapterUrl currentUrl=$_currentFetchingUrl',
          category: LogCategory.cache,
          tags: ['headless-webview', 'preempt'],
        );
        // 等待低优先级请求退出
        final yielded = await _waitForYield();
        if (!yielded) {
          // 等待超时，返回 busy
          LoggerService.instance.w(
            'HeadlessWebView: 等待让出超时，返回 busy',
            category: LogCategory.cache,
            tags: ['headless-webview', 'yield-timeout'],
          );
          return FetchContentResult.busy();
        }
      } else {
        // 无法抢占（同级或低抢高），返回 busy
        LoggerService.instance.w(
          'HeadlessWebView: WebView 忙碌，无法抢占 '
          'priority=$priority currentPriority=$_currentPriority',
          category: LogCategory.cache,
          tags: ['headless-webview', 'busy'],
        );
        return FetchContentResult.busy();
      }
    }

    // ===== 同步置位互斥锁（避免 await 期间被并发穿过） =====
    _isFetching = true;
    _currentPriority = priority;
    _currentFetchingUrl = chapterUrl;
    _shouldYield = false;
    // 为等待者创建让出信号
    _yieldedSignal = Completer<void>();

    String? scriptId;
    String? logDomain;

    try {
      // 1. 查找该域名的提取脚本
      final domain = _extractDomain(chapterUrl);
      if (domain == null) return FetchContentResult.noScript();
      logDomain = domain;

      final script = await _scriptRepo.getByDomain(domain);
      if (script == null || !script.hasChapterContentJs) {
        return FetchContentResult.noScript();
      }
      scriptId = script.id;

      // 2. 确保 WebView 就绪
      await _ensureWebView();

      LoggerService.instance.i(
        'HeadlessWebView: 开始获取 domain=$domain url=$chapterUrl '
        'priority=$priority',
        category: LogCategory.cache,
        tags: ['headless-webview', 'fetch'],
      );

      // 3. 加载页面
      await _loadPage(chapterUrl);

      // 抢占检查点：页面加载后
      if (_shouldYield) {
        LoggerService.instance.i(
          'HeadlessWebView: 页面加载后被抢占让出 url=$chapterUrl',
          category: LogCategory.cache,
          tags: ['headless-webview', 'yield'],
        );
        return FetchContentResult.busy();
      }

      // 4. 执行提取脚本
      final result = await _executeContentScript(
        script.chapterContentJs,
        chapterUrl,
      );

      // 抢占检查点：脚本执行后
      if (_shouldYield) {
        LoggerService.instance.i(
          'HeadlessWebView: 脚本执行后被抢占让出 url=$chapterUrl',
          category: LogCategory.cache,
          tags: ['headless-webview', 'yield'],
        );
        return FetchContentResult.busy();
      }

      // 5. 校验内容
      if (result == null || result.content.trim().isEmpty) {
        _recordFailure(script.id);
        LoggerService.instance.w(
          'HeadlessWebView: 脚本返回空内容 domain=$domain',
          category: LogCategory.cache,
          tags: ['headless-webview', 'empty-result'],
        );
        return FetchContentResult.noScript();
      }

      if (result.content.trim().length < 50) {
        _recordFailure(script.id);
        LoggerService.instance.w(
          'HeadlessWebView: 内容过短(${result.content.length}字符) domain=$domain',
          category: LogCategory.cache,
          tags: ['headless-webview', 'short-content'],
        );
        return FetchContentResult.noScript();
      }

      // 6. 成功 → 清除失败计数，标记已使用
      _recordSuccess(script.id);

      LoggerService.instance.i(
        'HeadlessWebView: 获取成功 domain=$domain len=${result.content.length}',
        category: LogCategory.cache,
        tags: ['headless-webview', 'success'],
      );

      // 7. OCR 还原（正文脚本标记 chapter_content_ocr 时对 PUA 反爬文本走 PP-OCRv6）
      String finalContent = result.content;
      final fontFamily = result.fontFamily;
      if (script.chapterContentOcr) {
        finalContent = await restoreContentIfNeeded(
          needsOcr: true,
          content: finalContent,
          fontFamily: fontFamily,
          // 产品路径 _ref 非 null；provider 注入保证（见 network_service_providers）
          restoreService: OcrRestoreService(_ref!, _renderPua),
        );
      }

      return FetchContentResult.success(
        ChapterContentResult(
          content: finalContent,
          fontFamily: fontFamily,
          fromCache: false,
        ),
      );
    } on PageLoadFailedException {
      // 页面加载失败（onLoadStop 超时/错误）→ 区分于"真无脚本"，返回 loadFailed
      if (scriptId != null) _recordFailure(scriptId);
      LoggerService.instance.w(
        'HeadlessWebView: 页面加载失败，返回 loadFailed domain=$logDomain url=$chapterUrl',
        category: LogCategory.cache,
        tags: ['headless-webview', 'fetch', 'load-failed'],
      );
      return FetchContentResult.loadFailed();
    } catch (e, stackTrace) {
      if (scriptId != null) _recordFailure(scriptId);
      // 区分 JSON 解析错误（脚本本身有缺陷）与其他失败
      if (e is FormatException) {
        LoggerService.instance.e(
          'HeadlessWebView: 脚本结果 JSON 解析失败（脚本缺陷），返回 scriptError '
          'domain=$logDomain scriptId=$scriptId error=$e',
          stackTrace: stackTrace.toString(),
          category: LogCategory.cache,
          tags: ['headless-webview', 'fetch', 'script_error'],
        );
        return FetchContentResult.scriptError();
      }
      LoggerService.instance.e(
        'HeadlessWebView: 获取失败（catch 返回 loadFailed，区分于"真无脚本"） '
        'domain=$logDomain scriptId=$scriptId error=$e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview', 'fetch', 'failed_load_failed'],
      );
      return FetchContentResult.loadFailed();
    } finally {
      _isFetching = false;
      _currentPriority = FetchPriority.low;
      _currentFetchingUrl = null;
      // 通知等待让出信号的高优先级请求
      final signal = _yieldedSignal;
      _yieldedSignal = null;
      if (signal != null && !signal.isCompleted) {
        signal.complete();
      }
    }
  }

  /// 释放 WebView 资源
  void dispose() {
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _controller = null;
    _pageLoader.reset();
    _scriptFailureCount.clear();
  }

  // ===== OCR 还原编排 =====

  /// OCR 还原编排：[needsOcr] 时调 [restoreService] 还原 PUA，失败降级返回原文。
  ///
  /// 抽成 static `@visibleForTesting` 便于在纯 Dart 环境单测编排逻辑，
  /// 绕开 WebView 平台实现限制（fetchContent 走到 _ensureWebView 会抛异常）。
  /// 产品路径由 [fetchContent] 在 `script.needsOcr` 时调用。
  @visibleForTesting
  static Future<String> restoreContentIfNeeded({
    required bool needsOcr,
    required String content,
    required String? fontFamily,
    required OcrRestoreService restoreService,
  }) async {
    if (!needsOcr) return content;
    // 空字体预检：避免 ctx.font='80px ' 导致所有 PUA 渲染成相同占位框 →
    // ONNX 解码乱码。最常见原因：脚本 DOM 变更 / 字段缺失导致 font_family 丢失。
    // 不加运行时 verifyFontFamily（昂贵，每次 fetch 多 2 次 render）；字体 URL
    // 失效等场景较罕见，save_script 已做验证。后续如有需要再加。
    if (fontFamily == null || fontFamily.isEmpty) {
      LoggerService.instance.w(
        'HeadlessWebView OCR 跳过：fontFamily 为空，降级返回原文'
        '（可能脚本未返回 font_family 或 DOM 变更）',
        category: LogCategory.cache,
        tags: ['headless-webview', 'ocr', 'skip-empty-font'],
      );
      return content;
    }
    try {
      final r = await restoreService.restorePuaInText(content, fontFamily);
      LoggerService.instance.i(
        'HeadlessWebView OCR 还原: decoded=${r.decodedCount}/${r.totalPuaCount}',
        category: LogCategory.cache,
        tags: ['headless-webview', 'ocr', 'restore'],
      );
      return r.text;
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        'HeadlessWebView OCR 还原失败，降级返回原文: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview', 'ocr', 'restore-failed'],
      );
      return content; // 降级
    }
  }

  // ===== 优先级抢占 =====

  /// 等待低优先级请求让出 WebView。
  ///
  /// 通过 [Completer] 等待低优请求退出（由 `finally` 块 `_yieldedSignal?.complete()`
  /// 触发），最长 5 秒。返回 true 表示成功让出，false 表示等待超时。
  Future<bool> _waitForYield() async {
    final signal = _yieldedSignal;
    if (signal == null) {
      // 等待者尚未存在（边界情况：进入方法时低优已退出），直接返回 true
      return true;
    }
    try {
      await signal.future.timeout(const Duration(seconds: 5));
      return true;
    } on TimeoutException {
      LoggerService.instance.d(
        'HeadlessWebView: 等待让出超时（5s Completer）',
        category: LogCategory.cache,
        tags: ['headless-webview', 'wait_yield', 'timeout'],
      );
      return false;
    }
  }

  // ===== 内部实现 =====

  /// 从 URL 提取域名
  String? _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : null;
    } catch (_) {
      return null;
    }
  }

  /// 确保 HeadlessInAppWebView 已初始化
  Future<void> _ensureWebView() async {
    if (_controller != null) return;
    if (_isInitializing) {
      // 等待初始化完成（简单轮询）
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller != null) return;
      }
      LoggerService.instance.w(
        'HeadlessWebView: 初始化超时（30s 轮询）',
        category: LogCategory.cache,
        tags: ['headless-webview', 'init', 'timeout'],
      );
      throw Exception('HeadlessWebView 初始化超时');
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
        // 关键：创建时注册常驻 onLoadStop 回调，供 WebViewPageLoader 协调
        onLoadStop: _pageLoader.onLoadStopCallback,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          // 不加载图片，节省流量和时间
          loadsImagesAutomatically: false,
          // 禁用不需要的功能
          mediaPlaybackRequiresUserGesture: true,
          // 超时由 callAsyncJavaScript 的 timeout 控制
        ),
      );

      await _headlessWebView!.run();
      _controller = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('WebView 创建超时'),
      );

      LoggerService.instance.i(
        'HeadlessWebView: 初始化完成',
        category: LogCategory.cache,
        tags: ['headless-webview', 'init'],
      );
    } catch (e, stackTrace) {
      _isInitializing = false;
      // 初始化失败时清理
      _headlessWebView?.dispose();
      _headlessWebView = null;
      LoggerService.instance.e(
        'HeadlessWebView: 初始化失败 $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview', 'init', 'failed'],
      );
      rethrow;
    }
    _isInitializing = false;
  }

  /// 加载页面并等待 onLoadStop。
  ///
  /// 使用 [WebViewPageLoader]（onLoadStop 事件驱动）替代原 URL 轮询。
  /// 超时（onLoadStop 未在 30s 内触发）时抛 [PageLoadFailedException]，
  /// 由 [fetchContent] 的 catch 块映射为 `FetchContentResult.loadFailed()`。
  Future<void> _loadPage(String url) async {
    await _pageLoader.loadPage(
      controller: _controller!,
      url: url,
      throwOnTimeout: true,
    );
  }

  /// 执行 chapter_content_js 提取脚本
  ///
  /// 使用 3 秒粒度循环检查抢占信号 [_shouldYield]，
  /// 使低优先级请求最多 3 秒就能响应抢占。
  ///
  /// 返回 record `(content, fontFamily)`：fontFamily 可空（脚本未声明时为 null）。
  Future<({String content, String? fontFamily})?> _executeContentScript(
    String scriptTemplate,
    String pageUrl,
  ) async {
    // 校验脚本
    final validationError = WebViewJsExecutor.validateScript(scriptTemplate);
    if (validationError != null) {
      LoggerService.instance.w(
        'HeadlessWebView: 脚本校验失败 $validationError',
        category: LogCategory.cache,
        tags: ['headless-webview', 'validation'],
      );
      return null;
    }

    // 替换 {{URL}} → 实际 URL
    final resolvedScript = scriptTemplate.replaceAll('{{URL}}', pageUrl);

    // 提取 IIFE 函数体
    final functionBody =
        WebViewJsExecutor.extractAsyncFunctionBody(resolvedScript);

    // 执行 — 3 秒粒度检查抢占信号，总超时 120 秒（与 agent execute_js/save_script 对齐）
    final resultFuture = _controller!
        .callAsyncJavaScript(functionBody: functionBody);

    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final result = await resultFuture.timeout(const Duration(seconds: 3));

        // 脚本执行完成，处理结果
        if (result == null) return null;

        if (result.error != null) {
          LoggerService.instance.w(
            'HeadlessWebView: JS执行错误 ${result.error}',
            category: LogCategory.cache,
            tags: ['headless-webview', 'js-error'],
          );
          return null;
        }

        // 解析返回值
        final jsonStr = WebViewJsExecutor.stringifyJsResult(result.value);
        final data = jsonDecode(jsonStr);

        // 兼容两种返回格式：
        // 1. { "title": "...", "content": "...", "font_family": "..." }
        //    （agent 也可能写 camelCase fontFamily，两个都兜底取）
        // 2. 直接字符串内容
        if (data is Map<String, dynamic>) {
          final c = (data['content'] as String?)?.trim();
          final ff = (data['font_family'] as String? ??
                  data['fontFamily'] as String?)
              ?.trim();
          if (c == null) return null;
          return (
            content: c,
            fontFamily: (ff == null || ff.isEmpty) ? null : ff,
          );
        }
        if (data is String) {
          return (content: data.trim(), fontFamily: null);
        }

        return null;
      } on TimeoutException {
        // 3 秒超时，检查抢占信号
        if (_shouldYield) return null;
        continue;
      }
    }

    // 整体 120 秒超时
    LoggerService.instance.w(
      'HeadlessWebView: 脚本执行整体超时（120s） pageUrl=$pageUrl',
      category: LogCategory.cache,
      tags: ['headless-webview', 'execute_script', 'timeout'],
    );
    return null;
  }

  /// 渲染单个 PUA 码点为 base64 PNG（供 [OcrRestoreService] 用）。
  ///
  /// 委托给共享实现 [renderPuaViaController]，消除跨服务重复。
  /// 返回值是 base64 字符串（非 JSON），故不走 stringifyJsResult + jsonDecode。
  Future<String> _renderPua(int codepoint, String fontFamily) async {
    if (_controller == null) {
      throw StateError('WebView 未就绪，无法渲染 PUA');
    }
    return renderPuaViaController(_controller!, codepoint, fontFamily);
  }

  // ===== 脚本健康度 =====

  void _recordFailure(String scriptId) {
    final count = (_scriptFailureCount[scriptId] ?? 0) + 1;
    _scriptFailureCount[scriptId] = count;

    if (count >= _maxConsecutiveFailures) {
      LoggerService.instance.w(
        'HeadlessWebView: 脚本连续失败$count次，自动标记 unverified id=$scriptId',
        category: LogCategory.cache,
        tags: ['headless-webview', 'auto-disable'],
      );
      _scriptRepo.setVerified(scriptId, false);
    }
  }

  void _recordSuccess(String scriptId) {
    _scriptFailureCount.remove(scriptId);
    _scriptRepo.markUsed(scriptId);
  }
}

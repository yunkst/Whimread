/// Headless WebView 网站书架提取服务
///
/// 当某域名有 AI Agent 生成的 `bookshelf_js` 脚本时，本服务使用自管的
/// `HeadlessInAppWebView` 直接加载「我的书架」页面（取自 `SiteScript.sampleUrl`，
/// 否则需要用户输入）并执行脚本获取该网站的书架条目列表，再交给上层合并
/// 到本地书架（BookshelfMutationNotifier.addNovel）。
///
/// 与「添加小说」FAB（WebViewImportBookshelfFab）不同：本服务不依赖用户
/// 当前正停留在该网站的书架页——它会主动 `loadUrl`，适用于「在书架屏
/// 一键刷新某个网站」的批量同步场景。Cookie 由 flutter_inappwebview 的
/// 全局 CookieManager 在 Android/iOS 平台进程级共享，可携带主 WebView
/// 已登录的会话（Web 平台会失败，由上层降级提示）。
///
/// ## 资源隔离
///
/// 自管一个独立 HeadlessInAppWebView，与 HeadlessWebViewChapterListService
/// （章节列表）、HeadlessWebViewContentService（章节内容）各自独立，
/// 避免互相覆盖 URL 导致抓取错乱。
///
/// ## 工作流程
///
///   fetchSiteBookshelf(url)
///     → SiteScriptRepository.getByDomain(domain(url))
///     → 无脚本 → return FetchSiteBookshelfResult.noScript()
///     → _isFetching → return FetchSiteBookshelfResult.busy()
///     → 有脚本 → WebViewPageLoader.loadPage(onLoadStop 等待)
///                → callAsyncJavaScript(bookshelf_js)
///                → 解析 JSON {novels} → SiteBookshelfParser
///                → 校验 novels 非空
///                → return FetchSiteBookshelfResult.success(entries)
///     → 页面加载超时 → return FetchSiteBookshelfResult.loadFailed()
library;

import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../repositories/site_script_repository.dart';
import '../services/logger_service.dart';
import '../services/novel_agent/scenarios/webview_js_executor.dart';
import '../services/site_bookshelf_parser.dart';
import 'headless_webview_errors.dart';
import 'webview_page_loader.dart';

class HeadlessWebViewBookshelfService {
  final SiteScriptRepository _scriptRepo;

  HeadlessWebViewBookshelfService({
    required SiteScriptRepository scriptRepo,
  }) : _scriptRepo = scriptRepo;

  // ===== 自管 Headless WebView 单例 =====

  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitializing = false;
  bool _isFetching = false;

  final WebViewPageLoader _pageLoader = WebViewPageLoader();

  // ===== 脚本健康度追踪 =====

  final Map<String, int> _scriptFailureCount = {};
  static const int _maxConsecutiveFailures = 3;

  // ===== 公开 API =====

  /// 用 Headless WebView 提取指定 URL 所在域名的网站书架
  ///
  /// [url] 必须为完整 http(s) URL；本服务取其 host 查脚本。
  Future<FetchSiteBookshelfResult> fetchSiteBookshelf(String url) async {
    if (_isFetching) {
      LoggerService.instance.d(
        'HeadlessWebViewBookshelf: 互斥命中 busy url=$url',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'mutex'],
      );
      return FetchSiteBookshelfResult.busy();
    }
    _isFetching = true;
    String? scriptId;
    String? logDomain;
    try {
      final domain = _extractDomain(url);
      if (domain == null) return FetchSiteBookshelfResult.noScript();
      logDomain = domain;

      final script = await _scriptRepo.getByDomain(domain);
      if (script == null || !script.hasBookshelfJs) {
        return FetchSiteBookshelfResult.noScript();
      }
      scriptId = script.id;

      LoggerService.instance.i(
        'HeadlessWebViewBookshelf: 开始 domain=$domain url=$url',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'fetch'],
      );

      await _ensureWebView();

      // 等待 onLoadStop（超时抛 PageLoadFailedException）
      await _loadPage(url);

      final result = await _executeBookshelfScript(
        _controller!,
        script.bookshelfJs,
        url,
      );
      if (result == null) {
        _recordFailure(scriptId);
        return FetchSiteBookshelfResult.failed();
      }

      // 非空校验（SiteBookshelfParser 失败或空数组都返回 null）
      if (result.isEmpty) {
        _recordFailure(scriptId);
        LoggerService.instance.w(
          'HeadlessWebViewBookshelf: 脚本返回空 novels domain=$logDomain',
          category: LogCategory.cache,
          tags: ['headless-webview', 'site-bookshelf', 'empty-result'],
        );
        return FetchSiteBookshelfResult.failed();
      }

      _recordSuccess(scriptId);
      LoggerService.instance.i(
        'HeadlessWebViewBookshelf: 获取成功 domain=$logDomain count=${result.length}',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'success'],
      );

      return FetchSiteBookshelfResult.success(result);
    } on PageLoadFailedException {
      if (scriptId != null) _recordFailure(scriptId);
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: 页面加载失败 url=$url domain=$logDomain',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'load-failed'],
      );
      return FetchSiteBookshelfResult.loadFailed();
    } catch (e) {
      if (scriptId != null) _recordFailure(scriptId);
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: 获取失败 domain=$logDomain url=$url error=$e',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'error'],
      );
      rethrow;
    } finally {
      _isFetching = false;
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

  // ===== 内部实现 =====

  String? _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureWebView() async {
    if (_controller != null) return;
    if (_isInitializing) {
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_controller != null) return;
      }
      throw Exception('HeadlessWebViewBookshelfService 初始化超时');
    }
    _isInitializing = true;
    try {
      final completer = Completer<InAppWebViewController>();

      _headlessWebView = HeadlessInAppWebView(
        onWebViewCreated: (controller) {
          if (!completer.isCompleted) completer.complete(controller);
        },
        onLoadStop: _pageLoader.onLoadStopCallback,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          loadsImagesAutomatically: false,
          mediaPlaybackRequiresUserGesture: true,
        ),
      );

      await _headlessWebView!.run();
      _controller = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('WebView 创建超时'),
      );

      LoggerService.instance.i(
        'HeadlessWebViewBookshelf: 初始化完成',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'init'],
      );
    } catch (e, stackTrace) {
      _isInitializing = false;
      _headlessWebView?.dispose();
      _headlessWebView = null;
      LoggerService.instance.e(
        'HeadlessWebViewBookshelf: 初始化失败 $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'init', 'failed'],
      );
      rethrow;
    }
    _isInitializing = false;
  }

  Future<void> _loadPage(String url) async {
    final outcome = await _pageLoader.loadPage(
      controller: _controller!,
      url: url,
      throwOnTimeout: true,
    );
    assert(outcome == PageLoadOutcome.loaded);
  }

  /// 执行 bookshelf_js：解析返回值并返回 entries；任何失败返回 null
  Future<List<SiteBookshelfEntry>?> _executeBookshelfScript(
    InAppWebViewController controller,
    String scriptTemplate,
    String pageUrl,
  ) async {
    final validationError = WebViewJsExecutor.validateScript(scriptTemplate);
    if (validationError != null) {
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: 脚本校验失败 $validationError',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'validation'],
      );
      return null;
    }
    final resolved = scriptTemplate.replaceAll('{{URL}}', pageUrl);
    final functionBody =
        WebViewJsExecutor.extractAsyncFunctionBody(resolved);

    dynamic result;
    try {
      result = await controller
          .callAsyncJavaScript(functionBody: functionBody)
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: 脚本执行超时（120s）pageUrl=$pageUrl',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'execute_timeout'],
      );
      return null;
    }

    if (result == null) return null;
    if (result.error != null) {
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: JS执行错误 ${result.error}',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'js-error'],
      );
      return null;
    }

    final jsonStr = WebViewJsExecutor.stringifyJsResult(result.value);
    return SiteBookshelfParser.parse(jsonStr);
  }

  // ===== 脚本健康度 =====

  void _recordFailure(String scriptId) {
    final count = (_scriptFailureCount[scriptId] ?? 0) + 1;
    _scriptFailureCount[scriptId] = count;
    if (count >= _maxConsecutiveFailures) {
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: 脚本连续失败$count次，自动标记 unverified id=$scriptId',
        category: LogCategory.cache,
        tags: ['headless-webview', 'site-bookshelf', 'auto-disable'],
      );
      _scriptRepo.setVerified(scriptId, false);
    }
  }

  void _recordSuccess(String scriptId) {
    _scriptFailureCount.remove(scriptId);
    _scriptRepo.markUsed(scriptId);
  }
}
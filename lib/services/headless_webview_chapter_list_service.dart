/// Headless WebView 章节列表获取服务
///
/// 当某个域名已有 AI Agent 生成的 `chapter_list_js` 提取脚本时，
/// 本服务使用自管的 `HeadlessInAppWebView` 直接加载章节列表页面并执行脚本
/// 获取章节列表，不再依赖后端 API。
///
/// ## 资源隔离
///
/// 本服务**自管一个独立的 HeadlessInAppWebView 实例**，与
/// `HeadlessWebViewContentService`（章节内容）、`HeadlessWebViewPool`
/// （Agent 提取场景）各自独立，互不干扰。这样可避免章节列表加载过程中
/// URL 被其它场景的 loadUrl 覆盖导致内容错乱。
///
/// ## 工作流程
///
/// ```
/// fetchChapterList(novelUrl)
///   → SiteScriptRepository.getByDomain(domain)
///   → 无脚本 → return FetchChapterListResult.noScript()
///   → _isFetching → return FetchChapterListResult.busy()
///   → 有脚本 → WebViewPageLoader.loadPage(onLoadStop 等待)
///              → callAsyncJavaScript(chapter_list_js)
///              → 解析 JSON {chapters}
///              → 校验 chapters 非空
///              → return FetchChapterListResult.success(...)
///   → 页面加载超时 → return FetchChapterListResult.loadFailed()
/// ```
///
/// ## 复用
///
/// - [WebViewPageLoader] — onLoadStop 事件驱动的页面加载等待
/// - [WebViewJsExecutor] — 脚本校验、IIFE 提取、结果解析
/// - [SiteScriptRepository] — 域名脚本查询
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chapter.dart';
import '../repositories/site_script_repository.dart';
import '../services/logger_service.dart';
import '../services/novel_agent/scenarios/webview_js_executor.dart';
import '../services/ocr_restore_service.dart';
import 'headless_webview_errors.dart';
import 'ocr_pua_renderer.dart';
import 'webview_page_loader.dart';

class HeadlessWebViewChapterListService {
  final SiteScriptRepository _scriptRepo;
  final Ref? _ref; // 产品路径非 null（读 ocrPredictorProvider），测试可不传

  HeadlessWebViewChapterListService({
    required SiteScriptRepository scriptRepo,
    Ref? ref,
  })  : _scriptRepo = scriptRepo,
        _ref = ref;

  // ===== 自管 Headless WebView 单例 =====

  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitializing = false;
  bool _isFetching = false;

  /// 共用页面加载工具（onLoadStop 事件驱动）
  final WebViewPageLoader _pageLoader = WebViewPageLoader();

  // ===== 脚本健康度追踪 =====

  final Map<String, int> _scriptFailureCount = {};
  static const int _maxConsecutiveFailures = 3;

  // ===== 公开 API =====

  /// 尝试用 Headless WebView 获取章节列表。
  ///
  /// 返回 [FetchChapterListResult] 明确区分四种情况：
  /// - `isSuccess`：获取成功，通过 `.chapters` 获取结果
  /// - `isNoScript`：该域名无提取脚本（或脚本返回空），不可重试
  /// - `isBusy`：WebView 正忙（互斥命中），可等待重试
  /// - `isLoadFailed`：页面加载失败，可重试
  Future<FetchChapterListResult> fetchChapterList(String novelUrl) async {
    if (_isFetching) {
      LoggerService.instance.d(
        'HeadlessWebViewChapterList: 互斥命中，返回 busy url=$novelUrl',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'mutex'],
      );
      return FetchChapterListResult.busy();
    }

    // ===== 同步置位互斥锁（避免 await 期间被并发穿过） =====
    _isFetching = true;
    String? scriptId;
    String? logDomain;
    try {
      // 1. 查找该域名的提取脚本
      final domain = _extractDomain(novelUrl);
      if (domain == null) return FetchChapterListResult.noScript();
      logDomain = domain;

      final script = await _scriptRepo.getByDomain(domain);
      if (script == null || !script.hasChapterListJs) {
        return FetchChapterListResult.noScript();
      }

      // 捕获 script.id 用于失败计数与日志，避免 catch 中重复查库
      scriptId = script.id;

      LoggerService.instance.i(
        'HeadlessWebViewChapterList: 开始获取 domain=$domain url=$novelUrl',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'fetch'],
      );

      // 2. 确保 WebView 就绪
      await _ensureWebView();

      // 3. 加载页面（onLoadStop 等待，超时抛 PageLoadFailedException）
      await _loadPage(novelUrl);

      // 4. 执行提取脚本（返回 title + chapters + 可选 fontFamily）
      final result = await _executeChapterListScript(
        _controller!,
        script.chapterListJs,
        novelUrl,
      );
      if (result == null) {
        _recordFailure(scriptId);
        return FetchChapterListResult.noScript();
      }

      String title = result.title;
      String? fontFamily = result.fontFamily;
      List<Chapter> chapters = result.chapters;

      // 5. OCR 还原（目录脚本标记 chapter_list_ocr 时对 PUA 反爬文本走 PP-OCRv6）
      if (script.chapterListOcr) {
        try {
          final restored = await restoreChapterListIfNeeded(
            needsOcr: true,
            title: title,
            chapters: chapters,
            fontFamily: fontFamily,
            // 产品路径 _ref 非 null；provider 注入保证（见 network_service_providers）
            restoreService: OcrRestoreService(_ref!, _renderPua),
          );
          title = restored.title;
          chapters = restored.chapters;
        } catch (e, stackTrace) {
          // restoreChapterListIfNeeded 已 try-catch，此处为防御兜底
          LoggerService.instance.w(
            'HeadlessWebViewChapterList: OCR 还原异常未降级（理论上不可达）',
            stackTrace: stackTrace.toString(),
            category: LogCategory.cache,
            tags: ['headless-webview', 'chapter-list', 'ocr', 'unexpected'],
          );
        }
      }

      // 6. 校验结果
      if (chapters.isEmpty) {
        _recordFailure(scriptId);
        LoggerService.instance.w(
          'HeadlessWebViewChapterList: 脚本返回空章节列表 domain=$logDomain',
          category: LogCategory.cache,
          tags: ['headless-webview', 'chapter-list', 'empty-result'],
        );
        return FetchChapterListResult.noScript();
      }

      // 7. 成功 → 清除失败计数，标记已使用
      _recordSuccess(scriptId);

      LoggerService.instance.i(
        'HeadlessWebViewChapterList: 获取成功 domain=$logDomain count=${chapters.length}',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'success'],
      );

      return FetchChapterListResult.success(chapters);
    } on PageLoadFailedException {
      if (scriptId != null) _recordFailure(scriptId);
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 页面加载失败 url=$novelUrl domain=$logDomain',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'load-failed'],
      );
      return FetchChapterListResult.loadFailed();
    } catch (e) {
      if (scriptId != null) _recordFailure(scriptId);
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 获取失败 domain=$logDomain url=$novelUrl error=$e',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'error'],
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
        'HeadlessWebViewChapterList: 初始化超时（30s 轮询）',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'init', 'timeout'],
      );
      throw Exception('HeadlessWebViewChapterList 初始化超时');
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
        ),
      );

      await _headlessWebView!.run();
      _controller = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('WebView 创建超时'),
      );

      LoggerService.instance.i(
        'HeadlessWebViewChapterList: 初始化完成',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'init'],
      );
    } catch (e, stackTrace) {
      _isInitializing = false;
      // 初始化失败时清理
      _headlessWebView?.dispose();
      _headlessWebView = null;
      LoggerService.instance.e(
        'HeadlessWebViewChapterList: 初始化失败 $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'init', 'failed'],
      );
      rethrow;
    }
    _isInitializing = false;
  }

  /// 加载页面并等待 onLoadStop（超时抛 PageLoadFailedException）
  Future<void> _loadPage(String url) async {
    final outcome = await _pageLoader.loadPage(
      controller: _controller!,
      url: url,
      throwOnTimeout: true,
    );
    // throwOnTimeout=true 时 outcome 只可能是 loaded（timeout 已抛异常）
    assert(outcome == PageLoadOutcome.loaded);
  }

  /// 执行 chapter_list_js 提取脚本
  ///
  /// 返回 record `(title, chapters, fontFamily)`：
  /// - title：脚本返回的顶层标题（可空，缺失时为空串；目前 service 出口不外传，
  ///   仅供 OCR 还原内部使用）
  /// - chapters：章节列表
  /// - fontFamily：脚本可选声明的反爬字体族名（OCR 还原时用），可空
  Future<({String title, List<Chapter> chapters, String? fontFamily})?>
      _executeChapterListScript(
    InAppWebViewController controller,
    String scriptTemplate,
    String pageUrl,
  ) async {
    // 校验脚本
    final validationError = WebViewJsExecutor.validateScript(scriptTemplate);
    if (validationError != null) {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 脚本校验失败 $validationError',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'validation'],
      );
      return null;
    }

    // 替换 {{URL}} → 实际 URL
    final resolvedScript = scriptTemplate.replaceAll('{{URL}}', pageUrl);

    // 提取 IIFE 函数体
    final functionBody =
        WebViewJsExecutor.extractAsyncFunctionBody(resolvedScript);

    // 执行（超时 120s，与 agent execute_js/save_script 对齐）
    dynamic result;
    try {
      result = await controller
          .callAsyncJavaScript(functionBody: functionBody)
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 脚本执行超时（120s） pageUrl=$pageUrl',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'execute_timeout'],
      );
      return null;
    }

    if (result == null) return null;

    if (result.error != null) {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: JS执行错误 ${result.error}',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'js-error'],
      );
      return null;
    }

    // 解析返回值
    final jsonStr = WebViewJsExecutor.stringifyJsResult(result.value);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final chaptersRaw = data['chapters'] as List<dynamic>?;
    if (chaptersRaw == null || chaptersRaw.isEmpty) {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 脚本返回空 chapters pageUrl=$pageUrl',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'empty_result'],
      );
      return null;
    }

    final chapters = <Chapter>[];
    for (int i = 0; i < chaptersRaw.length; i++) {
      final c = chaptersRaw[i];
      if (c is! Map) continue;
      final title = c['title']?.toString().trim();
      final url = c['url']?.toString().trim();
      if (title != null && title.isNotEmpty && url != null && url.isNotEmpty) {
        chapters.add(Chapter(title: title, url: url, chapterIndex: i));
      }
    }

    // 顶层 title（脚本可选返回）
    final title = (data['title']?.toString() ?? '').trim();

    // 可选 fontFamily：snake/camel 兜底
    final ff = (data['font_family'] as String? ?? data['fontFamily'] as String?)
        ?.trim();
    final fontFamily = (ff == null || ff.isEmpty) ? null : ff;

    return (
      title: title,
      chapters: chapters,
      fontFamily: fontFamily,
    );
  }

  // ===== OCR 还原编排 =====

  /// OCR 还原编排：[needsOcr] 时调 [restoreService] 还原 title 与每个
  /// `chapter.title` 中的 PUA 码点，**url 与 chapterIndex 保留**；失败降级
  /// 返回原 record。
  ///
  /// 抽成 static `@visibleForTesting` 便于在纯 Dart 环境单测编排逻辑，
  /// 绕开 WebView 平台实现限制（fetchChapterList 走到 _ensureWebView 会抛异常）。
  /// 产品路径由 [fetchChapterList] 在 `script.needsOcr` 时调用。
  ///
  /// 注：目前 service 出口 [FetchChapterListResult.success] 仅携带 chapters，
  /// title 还原后暂不外传——但本函数完整还原 title 以满足未来扩展（如目录页
  /// 顶层标题展示）和测试断言完整性。
  @visibleForTesting
  static Future<({String title, List<Chapter> chapters})>
      restoreChapterListIfNeeded({
    required bool needsOcr,
    required String title,
    required List<Chapter> chapters,
    required String? fontFamily,
    required OcrRestoreService restoreService,
  }) async {
    if (!needsOcr) return (title: title, chapters: chapters);
    // 空字体预检：避免 ctx.font='80px ' 导致所有 PUA 渲染成相同占位框 →
    // ONNX 解码乱码（与 restoreContentIfNeeded 同理，详见 ContentService 注释）。
    if (fontFamily == null || fontFamily.isEmpty) {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList OCR 跳过：fontFamily 为空，降级返回原文',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'ocr', 'skip-empty-font'],
      );
      return (title: title, chapters: chapters);
    }
    try {
      final newTitle =
          (await restoreService.restorePuaInText(title, fontFamily)).text;
      final newChapters = <Chapter>[];
      for (final c in chapters) {
        final t =
            (await restoreService.restorePuaInText(c.title, fontFamily)).text;
        newChapters.add(Chapter(
          title: t,
          url: c.url, // url 不动
          chapterIndex: c.chapterIndex, // chapterIndex 保留
        ));
      }
      LoggerService.instance.i(
        'HeadlessWebViewChapterList OCR 还原: n=${chapters.length}',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'ocr', 'restore'],
      );
      return (title: newTitle, chapters: newChapters);
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList OCR 还原失败，降级返回原文: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'ocr', 'restore-failed'],
      );
      return (title: title, chapters: chapters); // 降级
    }
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
        'HeadlessWebViewChapterList: 脚本连续失败$count次，自动标记 unverified id=$scriptId',
        category: LogCategory.cache,
        tags: ['headless-webview', 'chapter-list', 'auto-disable'],
      );
      _scriptRepo.setVerified(scriptId, false);
    }
  }

  void _recordSuccess(String scriptId) {
    _scriptFailureCount.remove(scriptId);
    _scriptRepo.markUsed(scriptId);
  }
}

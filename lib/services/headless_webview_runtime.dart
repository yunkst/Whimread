/// Headless WebView 共享运行时（组合式复用层）
///
/// 「自管 HeadlessInAppWebView」的三个服务——章节内容
/// （HeadlessWebViewContentService）、章节列表
/// （HeadlessWebViewChapterListService）、网站书架
/// （HeadlessWebViewBookshelfService）——原先各自复制一份 WebView
/// 初始化 / 页面加载 / 脚本执行 / 脚本健康度实现，任何初始化或脚本
/// 健康度修复都需要多处同步。本类把这些横切逻辑收拢为一个可配置
/// 运行时，各服务以**组合**方式持有一个实例（优先组合而非继承：
/// 服务间没有统一的能力契约，互斥/抢占/结果解析等差异化逻辑仍
/// 留在各服务内）。
///
/// ## 日志差异注入
///
/// 日志前缀与基础 tags 通过 [logPrefix]/[logTags] 注入，与拆分前
/// 一致；个别失败日志的上下文（domain/scriptId 等）通过方法级
/// `logContext` 参数附加（bookshelf 的既有排查习惯：提供时额外
/// 输出等待初始化日志与 domain/scriptId 字段）。
///
/// ## 初始化等待（事件驱动）
///
/// 并发初始化等待用 [Completer] 实现（参照 ContentService
/// `_waitForYield` 的既有模式），替代原「60 次 × 500ms」手写轮询。
/// 产品路径下各服务的 fetch 互斥锁保证不会并发进入初始化，等待
/// 分支仅为兜底；初始化失败时等待者直接收到同一异常（原轮询实现
/// 会空等至 30s 超时）。
///
/// ## 脚本执行超时（统一 120s 上限）
///
/// 原三处实现两套：content 用「3 秒切片 + deadline」循环（支持抢占
/// 中止），chapter_list/bookshelf 用一次性 `.timeout(120s)`。现统一
/// 为一个实现：切片长度取 `min(3s, 距 deadline 剩余时间)`，因此无论
/// 是否提供 [executeScript] 的 `shouldAbort`，总上限都精确为 120 秒
/// （与 agent execute_js/save_script 对齐）；`shouldAbort` 为 null 时
/// 每个切片超时仅继续等待，等价于原一次性 120s 超时。
library;

import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../repositories/site_script_repository.dart';
import 'browser_settings_service.dart';
import 'crawler/browser_mode.dart';
import 'logger_service.dart';
import 'novel_agent/scenarios/webview_js_executor.dart';
import 'ocr_pua_renderer.dart';
import 'webview_page_loader.dart';

/// 可配置的 Headless WebView 共享运行时
///
/// 每个自管 WebView 的服务持有一个独立实例（WebView 单例彼此隔离，
/// 与拆分前一致）；实例内状态（控制器 / 初始化中 / 健康度计数）互不相通。
class HeadlessWebViewRuntime {
  /// 脚本连续失败多少次后自动标记 unverified
  static const int _maxConsecutiveFailures = 3;

  /// 脚本执行超时切片粒度（抢占信号检查间隔）
  static const Duration _abortCheckSlice = Duration(seconds: 3);

  /// 脚本执行总上限（与 agent execute_js/save_script 对齐）
  static const Duration _scriptExecutionCap = Duration(seconds: 120);

  /// WebView 创建后等待 onWebViewCreated 的上限
  static const Duration _webViewCreationTimeout = Duration(seconds: 15);

  /// 并发初始化等待上限（与原 60×500ms 轮询总时长一致）
  static const Duration _initWaitTimeout = Duration(seconds: 30);

  /// 脚本健康度回调的落库通道（setVerified / markUsed）
  final SiteScriptRepository _scriptRepo;

  /// 日志前缀（如 'HeadlessWebView' / 'HeadlessWebViewChapterList'）
  final String logPrefix;

  /// 基础日志 tags（如 ['headless-webview', 'chapter-list']），
  /// 各事件 tag 追加其后
  final List<String> logTags;

  /// 脚本执行超时日志的事件 tags
  ///（content 沿用历史 ['execute_script', 'timeout']，其余默认 ['execute_timeout']）
  final List<String> scriptTimeoutTags;

  /// 初始化超时异常文案中的服务标识
  ///（bookshelf 历史文案为 'HeadlessWebViewBookshelfService'）
  final String initTimeoutLabel;

  // ===== 自管 Headless WebView 单例 =====

  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitializing = false;

  /// 并发初始化等待信号：初始化方创建并 complete，
  /// 等待方通过 [Completer.future] 事件驱动等待（替代手写轮询）。
  Completer<void>? _initCompleter;

  /// 创建当前 WebView 实例时的桌面模式快照；与最新设置不一致时销毁重建，
  /// 使 UA/尺寸跟随用户内置浏览器的展示模式（见 BrowserSettingsService）。
  bool _desktopModeAtCreation = BrowserSettingsService.desktopModeSync;

  /// 共用页面加载工具（onLoadStop 事件驱动）
  final WebViewPageLoader _pageLoader = WebViewPageLoader();

  // ===== 脚本健康度追踪 =====

  /// 脚本连续失败次数（内存，不持久化）
  final Map<String, int> _scriptFailureCount = {};

  HeadlessWebViewRuntime({
    required SiteScriptRepository scriptRepo,
    required this.logPrefix,
    this.logTags = const ['headless-webview'],
    this.scriptTimeoutTags = const ['execute_timeout'],
    String? initTimeoutLabel,
  }) : _scriptRepo = scriptRepo,
       initTimeoutLabel = initTimeoutLabel ?? logPrefix;

  /// 当前 WebView 控制器（未初始化或已释放时为 null）。
  InAppWebViewController? get controller => _controller;

  // ===== WebView 生命周期 =====

  /// 确保 HeadlessInAppWebView 已初始化
  ///
  /// [mode] 是 Resolver 对齐后的目标模式（已是「脚本模式优先 / 全局兜底」结果）。
  /// 实例模式与目标不一致则销毁重建（一次 fetch 内部应自洽，不中途切 UA）。
  ///
  /// [logContext] 为可选的日志上下文串（如 'domain=x scriptId=y'）：
  /// 提供时在等待初始化 / 初始化完成 / 初始化失败日志中附加（bookshelf 习惯）。
  Future<void> ensureWebView({
    required BrowserMode mode,
    String? logContext,
  }) async {
    final targetDesktop = mode == BrowserMode.desktop;
    if (_controller != null) {
      if (_desktopModeAtCreation == targetDesktop) return;
      LoggerService.instance.i(
        '$logPrefix: 模式切换 (${_modeLabelBool(_desktopModeAtCreation)} → '
        '${_modeLabelBool(targetDesktop)})，重建 WebView',
        category: LogCategory.crawler,
        tags: [...logTags, 'recreate', 'mode-change'],
      );
      _headlessWebView?.dispose();
      _headlessWebView = null;
      _controller = null;
    }
    _desktopModeAtCreation = targetDesktop;

    if (_isInitializing) {
      // 事件驱动等待（Completer），替代原「60 次 × 500ms」手写轮询。
      // 各服务的 fetch 互斥锁保证不会并发进入初始化，本分支为兜底。
      if (logContext != null) {
        LoggerService.instance.i(
          '$logPrefix: 等待其他初始化完成 $logContext',
          category: LogCategory.crawler,
          tags: [...logTags, 'init', 'waiting'],
        );
      }
      final signal = _initCompleter;
      if (signal != null) {
        try {
          await signal.future.timeout(_initWaitTimeout);
        } on TimeoutException {
          LoggerService.instance.w(
            '$logPrefix: 初始化等待超时（30s）'
            '${logContext == null ? '' : ' $logContext'}',
            category: LogCategory.crawler,
            tags: [...logTags, 'init', 'timeout'],
          );
          throw Exception('$initTimeoutLabel 初始化超时');
        }
        // 初始化失败时 signal 以同一异常完成，向上传播；
        // 成功时控制器已由初始化方就位。
        return;
      }
    }

    _isInitializing = true;
    final signal = Completer<void>();
    // 预登记 no-op 错误监听：初始化失败且无等待者时避免 unhandled error
    //（有等待者时它们各自的 await 正常收到该错误）。
    signal.future.ignore();
    _initCompleter = signal;
    try {
      final controllerCompleter = Completer<InAppWebViewController>();

      _headlessWebView = HeadlessInAppWebView(
        initialSize: targetDesktop
            ? BrowserSettingsService.headlessDesktopSize
            : const Size(-1, -1),
        onWebViewCreated: (controller) {
          if (!controllerCompleter.isCompleted) {
            controllerCompleter.complete(controller);
          }
        },
        // 关键：创建时注册常驻 onLoadStop 回调，供 WebViewPageLoader 协调
        onLoadStop: _pageLoader.onLoadStopCallback,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          // UA 与已对齐的 target 模式一致（不再读全局，保证「创建即目标模式」）
          userAgent: targetDesktop
              ? BrowserSettingsService.headlessUserAgent
              : '',
          // 不加载图片，节省流量和时间
          loadsImagesAutomatically: false,
          // 禁用不需要的功能
          mediaPlaybackRequiresUserGesture: true,
        ),
      );

      await _headlessWebView!.run();
      _controller = await controllerCompleter.future.timeout(
        _webViewCreationTimeout,
        onTimeout: () => throw Exception('WebView 创建超时'),
      );

      _isInitializing = false;
      _initCompleter = null;
      // 唤醒并发等待者（若有）
      if (!signal.isCompleted) signal.complete();

      LoggerService.instance.i(
        '$logPrefix: 初始化完成${logContext == null ? '' : ' $logContext'}',
        category: LogCategory.crawler,
        tags: [...logTags, 'init'],
      );
    } catch (e, stackTrace) {
      _isInitializing = false;
      _initCompleter = null;
      // 初始化失败时清理；等待者通过 signal 收到同一异常
      _headlessWebView?.dispose();
      _headlessWebView = null;
      if (!signal.isCompleted) signal.completeError(e);
      LoggerService.instance.e(
        '$logPrefix: 初始化失败'
        '${logContext == null ? ' $e' : ' $logContext error=$e'}',
        stackTrace: stackTrace.toString(),
        category: LogCategory.crawler,
        tags: [...logTags, 'init', 'failed'],
      );
      rethrow;
    }
  }

  /// 加载页面并等待 onLoadStop（超时抛 PageLoadFailedException）。
  Future<void> loadPage(String url) async {
    final outcome = await _pageLoader.loadPage(
      controller: _controller!,
      url: url,
      throwOnTimeout: true,
    );
    // throwOnTimeout=true 时 outcome 只可能是 loaded（timeout 已抛异常）
    assert(outcome == PageLoadOutcome.loaded);
  }

  // ===== 提取脚本执行 =====

  /// 校验并执行提取脚本，返回 stringify 后的 JSON 字符串（供各服务自行解析）。
  ///
  /// 流程（三服务原实现完全一致）：校验脚本 → 替换 {{URL}} → 提取
  /// IIFE 函数体 → callAsyncJavaScript → error/null 检查 → stringify。
  ///
  /// [shouldAbort] 为抢占/中止检查（每个超时切片结束时调用），
  /// 返回 true 立即放弃执行（content 的优先级抢占语义）；不传则
  /// 等价于一次性 120s 超时。总上限统一为 120 秒（见文件头注释）。
  ///
  /// [logContext] 为可选的日志上下文串（如 'domain=x scriptId=y'）。
  ///
  /// 返回 null 表示脚本校验失败 / JS 执行错误 / 超时 / 被中止。
  Future<String?> executeScript(
    String scriptTemplate,
    String pageUrl, {
    bool Function()? shouldAbort,
    String? logContext,
  }) async {
    // 校验脚本
    final validationError = WebViewJsExecutor.validateScript(scriptTemplate);
    if (validationError != null) {
      LoggerService.instance.w(
        '$logPrefix: 脚本校验失败'
        '${logContext == null ? '' : ' $logContext'} $validationError',
        category: LogCategory.crawler,
        tags: [...logTags, 'validation'],
      );
      return null;
    }

    // 替换 {{URL}} → 实际 URL
    final resolvedScript =
        WebViewJsExecutor.replaceUrlPlaceholder(scriptTemplate, pageUrl);

    // 提取 IIFE 函数体
    final functionBody =
        WebViewJsExecutor.extractAsyncFunctionBody(resolvedScript);

    // 统一执行策略：3 秒切片等待 + 120 秒总上限。
    // 末尾切片压缩到剩余时间，保证总上限精确 120s
    //（与 agent execute_js/save_script 对齐）。
    final resultFuture = _controller!.callAsyncJavaScript(
      functionBody: functionBody,
    );
    final deadline = DateTime.now().add(_scriptExecutionCap);

    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        LoggerService.instance.w(
          '$logPrefix: 脚本执行超时（120s）'
          '${logContext == null ? '' : ' $logContext'} pageUrl=$pageUrl',
          category: LogCategory.crawler,
          tags: [...logTags, ...scriptTimeoutTags],
        );
        return null;
      }
      try {
        final result = await resultFuture.timeout(
          remaining < _abortCheckSlice ? remaining : _abortCheckSlice,
        );

        if (result == null) return null;

        if (result.error != null) {
          LoggerService.instance.w(
            '$logPrefix: JS执行错误'
            '${logContext == null ? '' : ' $logContext'} ${result.error}',
            category: LogCategory.crawler,
            tags: [...logTags, 'js-error'],
          );
          return null;
        }

        // stringify 后交还调用方解析（各服务返回结构不同）
        return WebViewJsExecutor.stringifyJsResult(result.value);
      } on TimeoutException {
        // 切片超时：检查抢占信号（若有），否则继续等待下一片
        if (shouldAbort != null && shouldAbort()) return null;
        continue;
      }
    }
  }

  // ===== OCR PUA 渲染 =====

  /// 渲染单个 PUA 码点为 base64 PNG（供 [OcrRestoreService] 用）。
  ///
  /// 委托给 [renderPuaViaController]；返回值是 base64 字符串（非 JSON），
  /// 故不走 stringifyJsResult + jsonDecode。
  Future<String> renderPua(int codepoint, String fontFamily) async {
    if (_controller == null) {
      throw StateError('WebView 未就绪，无法渲染 PUA');
    }
    return renderPuaViaController(_controller!, codepoint, fontFamily);
  }

  // ===== 脚本健康度 =====

  /// 记录脚本一次失败；连续失败达 [_maxConsecutiveFailures] 次自动标记
  /// unverified（落库 [SiteScriptRepository.setVerified]）。
  ///
  /// [logContext] 为可选的日志上下文串（如 'domain=x'）。
  void recordFailure(String scriptId, {String? logContext}) {
    final count = (_scriptFailureCount[scriptId] ?? 0) + 1;
    _scriptFailureCount[scriptId] = count;

    if (count >= _maxConsecutiveFailures) {
      LoggerService.instance.w(
        '$logPrefix: 脚本连续失败$count次，自动标记 unverified id=$scriptId'
        '${logContext == null ? '' : ' $logContext'}',
        category: LogCategory.crawler,
        tags: [...logTags, 'auto-disable'],
      );
      _scriptRepo.setVerified(scriptId, false);
    }
  }

  /// 记录脚本成功：清除失败计数并标记已使用
  ///（落库 [SiteScriptRepository.markUsed]）。
  void recordSuccess(String scriptId) {
    _scriptFailureCount.remove(scriptId);
    _scriptRepo.markUsed(scriptId);
  }

  // ===== 资源释放 =====

  /// 释放 WebView 资源与健康度计数（可重复调用，不抛异常）。
  void dispose() {
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _controller = null;
    _initCompleter = null;
    _pageLoader.reset();
    _scriptFailureCount.clear();
  }

  static String _modeLabelBool(bool desktop) => desktop ? 'desktop' : 'mobile';
}

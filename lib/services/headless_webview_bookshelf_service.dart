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
/// 自管一个独立 HeadlessInAppWebView（通过共享运行时
/// [HeadlessWebViewRuntime] 组合持有），与 HeadlessWebViewChapterListService
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

import 'dart:convert' show jsonDecode;

import '../repositories/site_script_repository.dart';
import 'crawler/crawl_request.dart';
import 'crawler/crawl_request_resolver.dart';
import 'headless_webview_errors.dart';
import 'headless_webview_runtime.dart';
import 'logger_service.dart';
import 'site_bookshelf_parser.dart';

class HeadlessWebViewBookshelfService {
  final CrawlRequestResolver _resolver;

  /// 共享 WebView 运行时（初始化/加载/脚本执行/健康度），本服务独占一个实例
  final HeadlessWebViewRuntime _runtime;

  HeadlessWebViewBookshelfService({
    required SiteScriptRepository scriptRepo,
    required CrawlRequestResolver resolver,
  })  : _resolver = resolver,
        _runtime = HeadlessWebViewRuntime(
          scriptRepo: scriptRepo,
          logPrefix: 'HeadlessWebViewBookshelf',
          logTags: const ['headless-webview', 'site-bookshelf'],
          // 历史异常文案标识（原实现为 Service 后缀）
          initTimeoutLabel: 'HeadlessWebViewBookshelfService',
        );

  bool _isFetching = false;

  // ===== 公开 API =====

  /// 用 Headless WebView 提取指定 URL 所在域名的网站书架
  ///
  /// [url] 必须为完整 http(s) URL；本服务取其 host 查脚本。
  Future<FetchSiteBookshelfResult> fetchSiteBookshelf(String url) async {
    if (_isFetching) {
      LoggerService.instance.d(
        'HeadlessWebViewBookshelf: 互斥命中 busy url=$url',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'site-bookshelf', 'mutex'],
      );
      return FetchSiteBookshelfResult.busy();
    }
    _isFetching = true;
    String? scriptId;
    String? logDomain;
    final stopwatch = Stopwatch()..start();
    try {
      // ===== P1: URL×脚本×模式对齐（resolver 是唯一入口） =====
      final inputUri = Uri.tryParse(url);
      final resolution = await _resolver.resolve(inputUri, ScriptSlot.bookshelf);
      if (resolution is! CrawlAligned) {
        final noScript = resolution as CrawlNoScript;
        LoggerService.instance.i(
          'HeadlessWebViewBookshelf: outcome=noScript '
          'reason=${inputUri == null || inputUri.host.isEmpty ? 'invalid_url' : (noScript.siteKey == null ? 'invalid_url' : 'no_bookshelf_js')} '
          'domain=${noScript.siteKey} url=$url durationMs=${stopwatch.elapsedMilliseconds}',
          category: LogCategory.crawler,
          tags: ['headless-webview', 'site-bookshelf', 'no-script'],
        );
        return FetchSiteBookshelfResult.noScript();
      }
      final request = resolution.request;
      scriptId = request.script.id;
      logDomain = request.script.domain;
      final canonicalUrl = request.canonicalUrl;
      final hostRewrite = request.hostRewriteLog;

      LoggerService.instance.i(
        'HeadlessWebViewBookshelf: 开始 domain=${request.script.domain} '
        'scriptId=$scriptId canonicalUrl=$canonicalUrl '
        'mode=${request.mode.logName}'
        '${hostRewrite == null ? '' : ' hostRewrite=$hostRewrite'}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'site-bookshelf', 'fetch'],
      );

      // 确保 WebView 就绪（logContext 供初始化等待/完成/失败日志定位）
      await _runtime.ensureWebView(
        mode: request.mode,
        logContext: 'domain=$logDomain scriptId=$scriptId',
      );

      // 加载对齐后的 URL（host 已与脚本验证环境自洽，理论上不再触发跳转）
      await _runtime.loadPage(canonicalUrl.toString());

      final result = await _executeBookshelfScript(
        request.script.bookshelfJs,
        canonicalUrl.toString(),
        domain: logDomain,
        scriptId: scriptId,
      );
      if (result == null) {
        _runtime.recordFailure(scriptId, logContext: 'domain=$logDomain');
        LoggerService.instance.w(
          'HeadlessWebViewBookshelf: outcome=failed reason=execute_null '
          'domain=$logDomain scriptId=$scriptId durationMs=${stopwatch.elapsedMilliseconds}',
          category: LogCategory.crawler,
          tags: ['headless-webview', 'site-bookshelf', 'failed'],
        );
        return FetchSiteBookshelfResult.failed();
      }

      // 非空校验（SiteBookshelfParser 失败或空数组都返回 null）
      if (result.isEmpty) {
        _runtime.recordFailure(scriptId, logContext: 'domain=$logDomain');
        LoggerService.instance.w(
          'HeadlessWebViewBookshelf: outcome=failed reason=empty_result '
          'domain=$logDomain scriptId=$scriptId durationMs=${stopwatch.elapsedMilliseconds}',
          category: LogCategory.crawler,
          tags: ['headless-webview', 'site-bookshelf', 'empty-result'],
        );
        return FetchSiteBookshelfResult.failed();
      }

      _runtime.recordSuccess(scriptId);
      LoggerService.instance.i(
        'HeadlessWebViewBookshelf: outcome=success '
        'domain=$logDomain scriptId=$scriptId count=${result.length} '
        'mode=${request.mode.logName} '
        'durationMs=${stopwatch.elapsedMilliseconds}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'site-bookshelf', 'success'],
      );

      return FetchSiteBookshelfResult.success(result);
    } on PageLoadFailedException {
      if (scriptId != null) {
        _runtime.recordFailure(scriptId, logContext: 'domain=$logDomain');
      }
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: outcome=loadFailed '
        'domain=$logDomain scriptId=$scriptId url=$url '
        'durationMs=${stopwatch.elapsedMilliseconds}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'site-bookshelf', 'load-failed'],
      );
      return FetchSiteBookshelfResult.loadFailed();
    } catch (e) {
      if (scriptId != null) {
        _runtime.recordFailure(scriptId, logContext: 'domain=$logDomain');
      }
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: outcome=failed reason=exception '
        'domain=$logDomain scriptId=$scriptId url=$url error=$e '
        'durationMs=${stopwatch.elapsedMilliseconds}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'site-bookshelf', 'error'],
      );
      rethrow;
    } finally {
      _isFetching = false;
    }
  }

  /// 释放 WebView 资源
  void dispose() {
    _runtime.dispose();
  }

  // ===== 内部实现 =====

  /// 已对齐的爬取请求由 Resolver 完成；本服务不再做 host 提取或模式推断。

  /// 执行 bookshelf_js：解析返回值并返回 entries；任何失败返回 null
  ///
  /// 脚本校验/执行/超时（120s 上限）统一由 [_runtime.executeScript] 承担，
  /// 本方法只负责 SiteBookshelfParser 解析与形状诊断。
  ///
  /// [domain]/[scriptId] 仅用于日志定位，随每条失败日志输出。
  Future<List<SiteBookshelfEntry>?> _executeBookshelfScript(
    String scriptTemplate,
    String pageUrl, {
    String? domain,
    String? scriptId,
  }) async {
    final jsonStr = await _runtime.executeScript(
      scriptTemplate,
      pageUrl,
      logContext: 'domain=$domain scriptId=$scriptId',
    );
    if (jsonStr == null) return null;

    final parsed = SiteBookshelfParser.parse(jsonStr);
    if (parsed == null) {
      // SiteBookshelfParser 对各类畸形返回都静默返回 null，
      // 这里做一次形状诊断，让"脚本有 bug 但不知道错在哪"可定位。
      LoggerService.instance.w(
        'HeadlessWebViewBookshelf: 解析脚本返回失败 '
        'domain=$domain scriptId=$scriptId reason=${_diagnoseParseFailure(jsonStr)} '
        'jsonLen=${jsonStr.length} preview=${_jsonPreview(jsonStr)}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'site-bookshelf', 'parse-failed'],
      );
    }
    return parsed;
  }

  /// 对脚本返回的 JSON 做形状诊断，返回失败原因（供日志定位）
  String _diagnoseParseFailure(String jsonStr) {
    if (jsonStr.isEmpty) return 'empty_response';
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return 'wrong_top_level';
      final novels = decoded['novels'];
      if (novels is! List) return 'missing_novels';
      if (novels.isEmpty) return 'empty_novels';
      return 'all_entries_invalid';
    } on FormatException {
      return 'json_decode_failed';
    } catch (_) {
      return 'unknown';
    }
  }

  String _jsonPreview(String jsonStr) {
    if (jsonStr.length <= 200) return jsonStr;
    return '${jsonStr.substring(0, 200)}...';
  }
}

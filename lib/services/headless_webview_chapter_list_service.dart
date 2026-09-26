/// Headless WebView 章节列表获取服务
///
/// 当某个域名已有 AI Agent 生成的 `chapter_list_js` 提取脚本时，
/// 本服务使用自管的 `HeadlessInAppWebView` 直接加载章节列表页面并执行脚本
/// 获取章节列表，不再依赖后端 API。
///
/// ## 资源隔离
///
/// 本服务**自管一个独立的 HeadlessInAppWebView 实例**（通过共享运行时
/// [HeadlessWebViewRuntime] 组合持有），与
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
///              → 解析 JSON {chapters, cover_url?}
///              → 校验 chapters 非空
///              → return FetchChapterListResult.success(...)
///   → 页面加载超时 → return FetchChapterListResult.loadFailed()
/// ```
///
/// ## 复用
///
/// - [HeadlessWebViewRuntime] — WebView 初始化 / 页面加载 / 脚本执行
///   （统一 120s 超时）/ 脚本健康度的共享实现
/// - [SiteScriptRepository] — 域名脚本查询（经运行时用于健康度落库）
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chapter.dart';
import '../repositories/site_script_repository.dart';
import '../services/crawler/crawl_request.dart';
import '../services/crawler/crawl_request_resolver.dart';
import '../services/logger_service.dart';
import '../services/ocr_restore_service.dart';
import 'headless_webview_errors.dart';
import 'headless_webview_runtime.dart';

class HeadlessWebViewChapterListService {
  final CrawlRequestResolver _resolver;
  final Ref? _ref;

  /// 共享 WebView 运行时（初始化/加载/脚本执行/健康度），本服务独占一个实例
  final HeadlessWebViewRuntime _runtime;

  HeadlessWebViewChapterListService({
    required SiteScriptRepository scriptRepo,
    required CrawlRequestResolver resolver,
    Ref? ref,
  })  : _resolver = resolver,
        _ref = ref,
        _runtime = HeadlessWebViewRuntime(
          scriptRepo: scriptRepo,
          logPrefix: 'HeadlessWebViewChapterList',
          logTags: const ['headless-webview', 'chapter-list'],
        );

  bool _isFetching = false;

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
        category: LogCategory.crawler,
        tags: ['headless-webview', 'chapter-list', 'mutex'],
      );
      return FetchChapterListResult.busy();
    }

    // ===== 同步置位互斥锁（避免 await 期间被并发穿过） =====
    _isFetching = true;
    String? scriptId;
    String? logDomain;
    try {
      // ===== P1: URL×脚本×模式对齐（resolver 是唯一入口） =====
      final inputUri = Uri.tryParse(novelUrl);
      final resolution =
          await _resolver.resolve(inputUri, ScriptSlot.chapterList);
      if (resolution is! CrawlAligned) {
        return FetchChapterListResult.noScript();
      }
      final request = resolution.request;
      final script = request.script;

      // 捕获 script.id 用于失败计数与日志，避免 catch 中重复查库
      scriptId = script.id;
      logDomain = script.domain;
      final canonicalUrl = request.canonicalUrl;
      final hostRewrite = request.hostRewriteLog;

      LoggerService.instance.i(
        'HeadlessWebViewChapterList: 开始获取 domain=${script.domain} '
        'scriptId=$scriptId canonicalUrl=$canonicalUrl '
        'mode=${request.mode.logName}'
        '${hostRewrite == null ? '' : ' hostRewrite=$hostRewrite'}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'chapter-list', 'fetch'],
      );

      // 2. 确保 WebView 就绪（模式已由 resolver 对齐）
      await _runtime.ensureWebView(mode: request.mode);

      // 3. 加载对齐后的 URL
      await _runtime.loadPage(canonicalUrl.toString());

      // 4. 执行提取脚本（返回 title + coverUrl + chapters + 可选 fontFamily）
      final result = await _executeChapterListScript(
        script.chapterListJs,
        canonicalUrl.toString(),
      );
      if (result == null) {
        _runtime.recordFailure(scriptId);
        return FetchChapterListResult.noScript();
      }

      String title = result.title;
      String? fontFamily = result.fontFamily;
      List<Chapter> chapters = result.chapters;
      final coverUrl = result.coverUrl;

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
            category: LogCategory.crawler,
            tags: ['headless-webview', 'chapter-list', 'ocr', 'unexpected'],
          );
        }
      }

      // 6. 校验结果
      if (chapters.isEmpty) {
        _runtime.recordFailure(scriptId);
        LoggerService.instance.w(
          'HeadlessWebViewChapterList: 脚本返回空章节列表 domain=$logDomain',
          category: LogCategory.crawler,
          tags: ['headless-webview', 'chapter-list', 'empty-result'],
        );
        return FetchChapterListResult.noScript();
      }

      // 7. 成功 → 清除失败计数，标记已使用
      _runtime.recordSuccess(scriptId);

      LoggerService.instance.i(
        'HeadlessWebViewChapterList: 获取成功 domain=$logDomain scriptId=$scriptId '
        'count=${chapters.length} coverUrl=$coverUrl mode=${request.mode.logName}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'chapter-list', 'success'],
      );

      return FetchChapterListResult.success(chapters, coverUrl: coverUrl);
    } on PageLoadFailedException {
      if (scriptId != null) _runtime.recordFailure(scriptId);
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 页面加载失败 url=$novelUrl domain=$logDomain',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'chapter-list', 'load-failed'],
      );
      return FetchChapterListResult.loadFailed();
    } catch (e) {
      if (scriptId != null) _runtime.recordFailure(scriptId);
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 获取失败 domain=$logDomain url=$novelUrl error=$e',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'chapter-list', 'error'],
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

  /// 执行 chapter_list_js 提取脚本
  ///
  /// 脚本校验/执行/超时（120s 上限）统一由 [_runtime.executeScript] 承担，
  /// 本方法只负责章节列表结果的解析。
  ///
  /// 返回 record `(title, chapters, fontFamily, coverUrl)`：
  /// - title：脚本返回的顶层标题（可空，缺失时为空串；目前 service 出口不外传，
  ///   仅供 OCR 还原内部使用）
  /// - chapters：章节列表
  /// - fontFamily：脚本可选声明的反爬字体族名（OCR 还原时用），可空
  /// - coverUrl：脚本可选返回的封面图 URL（cover_url / coverUrl 兜底），可空
  Future<
          ({
            String title,
            List<Chapter> chapters,
            String? fontFamily,
            String? coverUrl
          })?>
      _executeChapterListScript(
    String scriptTemplate,
    String pageUrl,
  ) async {
    final jsonStr = await _runtime.executeScript(scriptTemplate, pageUrl);
    if (jsonStr == null) return null;

    // 解析返回值
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final chaptersRaw = data['chapters'] as List<dynamic>?;
    if (chaptersRaw == null || chaptersRaw.isEmpty) {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList: 脚本返回空 chapters pageUrl=$pageUrl',
        category: LogCategory.crawler,
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

    // 可选 coverUrl：snake/camel 兜底。空串视为未声明（脚本在拿不到封面时返回 ''）
    final coverRaw =
        data['cover_url'] as String? ?? data['coverUrl'] as String?;
    final coverUrl = (coverRaw == null || coverRaw.trim().isEmpty)
        ? null
        : coverRaw.trim();

    return (
      title: title,
      chapters: chapters,
      fontFamily: fontFamily,
      coverUrl: coverUrl,
    );
  }

  // ===== OCR 还原编排 =====

  /// OCR 还原编排：[needsOcr] 时调 [restoreService] 还原 title 与每个
  /// `chapter.title` 中的 PUA 码点，**url 与 chapterIndex 保留**；失败降级
  /// 返回原 record。
  ///
  /// 抽成 static `@visibleForTesting` 便于在纯 Dart 环境单测编排逻辑，
  /// 绕开 WebView 平台实现限制（fetchChapterList 走到 WebView 初始化会抛异常）。
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
        category: LogCategory.crawler,
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
        category: LogCategory.crawler,
        tags: ['headless-webview', 'chapter-list', 'ocr', 'restore'],
      );
      return (title: newTitle, chapters: newChapters);
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        'HeadlessWebViewChapterList OCR 还原失败，降级返回原文: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.crawler,
        tags: ['headless-webview', 'chapter-list', 'ocr', 'restore-failed'],
      );
      return (title: title, chapters: chapters); // 降级
    }
  }

  /// 渲染单个 PUA 码点为 base64 PNG（供 [OcrRestoreService] 用）。
  ///
  /// 委托给共享运行时 [_runtime.renderPua]。
  Future<String> _renderPua(int codepoint, String fontFamily) =>
      _runtime.renderPua(codepoint, fontFamily);
}

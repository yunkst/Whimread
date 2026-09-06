/// WebView「添加小说」悬浮按钮
///
/// 右下角 FloatingActionButton，仅在当前域名存在 `chapter_list_js` 脚本时显示。
///
/// ## 交互流程
///
///   1. 点击 → 执行 `chapter_list_js` → 提取 JSON {title, chapters}
///   2. 弹出 [AddNovelPreviewSheet] 预览
///   3. 确认后：
///     - 小说不在书架 → 插入 bookshelf 表
///     - 小说已在书架 → **静默更新章节**（不额外提示）
///     - 章节写入 novel_chapters 表
///     - 跳转到 [ChapterListScreenRiverpod]
///
/// ## 复用
///
///   - JS 执行 → [WebViewJsExecutor]（校验 + IIFE 提取 + callAsyncJavaScript）
///   - 数据库 → `novelRepositoryProvider` / `chapterRepositoryProvider`
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/agent_launcher_providers.dart';
import '../core/providers/bookshelf_mutation_provider.dart';
import '../core/providers/chapter_mutation_provider.dart';
import '../core/providers/webview_add_novel_providers.dart';
import '../core/providers/webview_providers.dart';
import '../core/providers/database_providers.dart';
import '../core/theme/app_colors.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/site_script.dart';
import '../services/logger_service.dart';
import '../services/novel_agent/scenarios/webview_js_executor.dart';
import '../screens/chapter_list_screen_riverpod.dart';
import '../utils/toast_utils.dart';
import 'add_novel_preview_sheet.dart';
import 'agent_chat/fab_launch_request_builder.dart';

class WebViewAddNovelFab extends ConsumerStatefulWidget {
  const WebViewAddNovelFab({super.key});

  @override
  ConsumerState<WebViewAddNovelFab> createState() =>
      _WebViewAddNovelFabState();
}

class _WebViewAddNovelFabState extends ConsumerState<WebViewAddNovelFab> {
  bool _isExtracting = false;

  @override
  Widget build(BuildContext context) {
    final showButton = ref.watch(webviewHasAddNovelButtonProvider);
    if (!showButton) return const SizedBox.shrink();

    return FloatingActionButton.small(
      heroTag: 'add_novel_fab',
      onPressed: _isExtracting ? null : () => _handleAddNovel(context),
      tooltip: '添加小说',
      backgroundColor: context.appColors.agentAccent,
      foregroundColor: context.appColors.agentOnBrand,
      elevation: 4,
      child: _isExtracting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.library_add),
    );
  }

  // ===================================================================
  // 核心流程
  // ===================================================================

  Future<void> _handleAddNovel(BuildContext context) async {
    // 1. 取当前 URL 与域名
    final currentUrl = ref.read(webviewCurrentUrlProvider);
    if (currentUrl.isEmpty) {
      _toast('无法获取当前页面链接', isError: true);
      return;
    }
    final domain = ref.read(webviewCurrentDomainProvider);
    if (domain == null) {
      _toast('当前页面不是 http(s) 页面', isError: true);
      return;
    }

    // 2. 取脚本（await future 等 DB 查询完成，避免同步 valueOrNull
    //    在 Future 未预热时返回 null 导致误判"无脚本"→ 必然降级 agent；
    //    即使脚本已在 site_scripts 表里缓存。修"首次添加必然走 agent"bug）
    SiteScript? script;
    try {
      script = await ref.read(webviewCurrentSiteScriptProvider.future);
    } catch (e) {
      LoggerService.instance.w(
        'FAB添加小说: 脚本查询异常, 降级 agent domain=$domain error=$e',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-add-novel', 'script-query-error'],
      );
      script = null;
    }

    // 3. 取 WebView 控制器
    final controller = ref.read(webviewControllerProvider);
    if (controller == null) {
      _toast('浏览器未就绪', isError: true);
      return;
    }

    // 4. 无脚本分支 -> 降级 agent
    if (script == null) {
      await _launchAgent(context, currentUrl, domain, null,
          FabFailureReason.noScript);
      return;
    }

    setState(() => _isExtracting = true);

    try {
      // 5. 有脚本分支：校验 -> 执行 -> 解析（保留原 :150-269 逻辑）

      // 校验脚本（确保含 {{URL}} 占位符）
      final validationError =
          WebViewJsExecutor.validateScript(script.chapterListJs);
      if (validationError != null) {
        LoggerService.instance.w(
          'FAB添加小说: 脚本校验失败 domain=${script.domain} error=$validationError',
          category: LogCategory.ai,
          tags: ['headless-webview', 'fab-add-novel', 'validation'],
        );
        // 校验失败 -> 降级修复
        await _launchAgent(context, currentUrl, domain, script.chapterListJs,
            FabFailureReason.scriptError,
            errorMessage: validationError);
        return;
      }

      // 替换 {{URL}} → 当前 URL
      final resolvedScript =
          script.chapterListJs.replaceAll('{{URL}}', currentUrl);

      // 提取 IIFE 函数体（适配 callAsyncJavaScript）
      final functionBody =
          WebViewJsExecutor.extractAsyncFunctionBody(resolvedScript);

      // 执行脚本（超时 120s，与 agent execute_js/save_script 对齐）
      final jsResult = await controller
          .callAsyncJavaScript(functionBody: functionBody)
          .timeout(const Duration(seconds: 120));

      // 解析返回值
      if (jsResult == null) {
        LoggerService.instance.w(
          'FAB添加小说: 脚本返回空值 domain=${script.domain} url=$currentUrl',
          category: LogCategory.ai,
          tags: ['headless-webview', 'fab-add-novel', 'null_result'],
        );
        // 空结果 -> 降级修复
        await _launchAgent(context, currentUrl, domain, script.chapterListJs,
            FabFailureReason.emptyResult);
        return;
      }
      if (jsResult.error != null) {
        LoggerService.instance.w(
          'FAB添加小说: JS执行错误 domain=${script.domain} error=${jsResult.error}',
          category: LogCategory.ai,
          tags: ['headless-webview', 'fab-add-novel', 'js-error'],
        );
        // JS 错误 -> 降级修复
        await _launchAgent(context, currentUrl, domain, script.chapterListJs,
            FabFailureReason.scriptError,
            errorMessage: jsResult.error);
        return;
      }

      final resultStr = WebViewJsExecutor.stringifyJsResult(jsResult.value);
      final data = jsonDecode(resultStr) as Map<String, dynamic>;

      final extractedTitle =
          (data['title'] as String?)?.trim() ?? '';
      final chaptersRaw = data['chapters'] as List<dynamic>?;

      if (extractedTitle.isEmpty || chaptersRaw == null || chaptersRaw.isEmpty) {
        LoggerService.instance.w(
          'FAB添加小说: 提取结果为空 domain=${script.domain} title=$extractedTitle chaptersCount=${chaptersRaw?.length ?? 0}',
          category: LogCategory.ai,
          tags: ['headless-webview', 'fab-add-novel', 'empty_result'],
        );
        // 提取结果为空 -> 降级修复
        await _launchAgent(context, currentUrl, domain, script.chapterListJs,
            FabFailureReason.emptyResult);
        return;
      }

      // 转换为类型化数据
      final chapters = <Map<String, String>>[];
      for (final c in chaptersRaw) {
        if (c is! Map) continue;
        final title = c['title']?.toString().trim();
        final url = c['url']?.toString().trim();
        if (title != null && title.isNotEmpty && url != null && url.isNotEmpty) {
          chapters.add({'title': title, 'url': url});
        }
      }

      if (chapters.isEmpty) {
        LoggerService.instance.w(
          'FAB添加小说: 章节数据解析失败 domain=${script.domain}',
          category: LogCategory.ai,
          tags: ['headless-webview', 'fab-add-novel', 'parse_failed'],
        );
        // 章节解析失败 -> 降级修复（按 emptyResult 处理）
        await _launchAgent(context, currentUrl, domain, script.chapterListJs,
            FabFailureReason.emptyResult);
        return;
      }

      // 6. 检查是否已在书架
      final novelRepo = ref.read(novelRepositoryProvider);
      final alreadyInBookshelf = await novelRepo.isInBookshelf(currentUrl);

      if (alreadyInBookshelf) {
        // 已存在：静默更新章节后直接跳转
        await _saveChapters(currentUrl, chapters);
        _markScriptUsed(script.id);
        _toast('章节已更新');
        if (mounted) {
          // ignore: use_build_context_synchronously
          _navigateToChapterList(context, Novel(
            title: extractedTitle,
            author: '',
            url: currentUrl,
          ));
        }
        return;
      }

      // 7. 显示预览弹窗
      if (!mounted) return;
      final previewResult = await showModalBottomSheet<Map<String, dynamic>>(
        // ignore: use_build_context_synchronously
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => AddNovelPreviewSheet(
          title: extractedTitle,
          chapters: chapters,
          sourceUrl: currentUrl,
        ),
      );

      if (previewResult == null || previewResult['confirmed'] != true) return;

      final finalTitle = (previewResult['title'] as String?) ?? extractedTitle;

      // 8. 写入数据库
      // 走 Notifier 收口：写库 + invalidate(bookshelfNovelsProvider)，
      // 浏览器添加小说后书架 UI 立即刷新（修这一类"写了但没刷干净"的根因）。
      await ref.read(bookshelfMutationProvider.notifier).addNovel(Novel(
        title: finalTitle,
        author: '',
        url: currentUrl,
      ));
      await _saveChapters(currentUrl, chapters);
      _markScriptUsed(script.id);

      LoggerService.instance.i(
        'FAB添加小说: 成功 domain=${script.domain} title=$finalTitle chapters=${chapters.length}',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-add-novel', 'success'],
      );
      _toast('已添加到书架');

      // 9. 导航到章节列表
      if (mounted) {
        // ignore: use_build_context_synchronously
        _navigateToChapterList(context, Novel(
          title: finalTitle,
          author: '',
          url: currentUrl,
        ));
      }
    } on TimeoutException {
      LoggerService.instance.w(
        'FAB添加小说: 提取超时(>120s) domain=${script.domain} url=$currentUrl',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-add-novel', 'timeout'],
      );
      // 超时 -> 降级修复
      await _launchAgent(context, currentUrl, domain, script.chapterListJs,
          FabFailureReason.scriptError,
          errorMessage: '提取超时(>120s)');
    } catch (e) {
      LoggerService.instance.e(
        'FAB添加小说: 提取异常 domain=${script.domain} error=$e',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-add-novel', 'error'],
      );
      // 异常 -> 降级修复
      await _launchAgent(context, currentUrl, domain, script.chapterListJs,
          FabFailureReason.scriptError,
          errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  /// 降级触发 agent（无脚本/脚本失败/空结果）
  ///
  /// [oldScript] 仅在 has-script 失败分支提供（用于 agent 读取旧脚本修复）；
  /// noScript 分支为 null。
  /// [errorMessage] 仅 reason==scriptError 时提供（JS 错误信息）。
  Future<void> _launchAgent(
    BuildContext context,
    String currentUrl,
    String domain,
    String? oldScript,
    FabFailureReason reason, {
    String? errorMessage,
  }) async {
    final launcher = ref.read(contextualAgentLauncherProvider);
    final request = FabLaunchRequestBuilder.build(
      currentUrl: currentUrl,
      domain: domain,
      oldScript: oldScript,
      reason: reason,
      errorMessage: errorMessage,
    );
    await launcher.launch(context, request);
  }

  // ===================================================================
  // 辅助方法
  // ===================================================================

  /// 将章节列表持久化到 novel_chapters 表
  ///
  /// 走 ChapterMutationNotifier 收口：写库 + bump signal 触发章节列表软刷新。
  Future<void> _saveChapters(
    String novelUrl,
    List<Map<String, String>> chaptersData,
  ) async {
    final chapters = chaptersData.asMap().entries.map((e) {
      return Chapter(
        title: e.value['title']!,
        url: e.value['url']!,
        chapterIndex: e.key,
      );
    }).toList();
    await ref.read(chapterMutationProvider.notifier).cacheNovelChapters(
          novelUrl,
          chapters,
        );
  }

  /// 标记脚本已使用（use_count + 1）
  void _markScriptUsed(String scriptId) {
    ref.read(siteScriptRepositoryProvider).markUsed(scriptId);
  }

  /// 导航到章节列表页
  void _navigateToChapterList(BuildContext context, Novel novel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChapterListScreenRiverpod(novel: novel),
      ),
    );
  }

  /// 显示 Toast 提示
  void _toast(String message, {bool isError = false}) {
    if (isError) {
      ToastUtils.showError(message);
      return;
    }
    ToastUtils.showSuccess(message);
  }
}

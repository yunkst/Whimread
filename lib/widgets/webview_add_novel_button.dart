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
import '../core/providers/remote_script_providers.dart';
import '../core/providers/script_presence_provider.dart';
import '../core/providers/webview_add_novel_providers.dart';
import '../core/providers/webview_providers.dart';
import '../core/providers/database_providers.dart';
import '../core/providers/services/network_service_providers.dart';
import '../core/theme/app_colors.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/remote_script.dart';
import '../models/site_script.dart';
import '../services/logger_service.dart';
import '../services/novel_agent/scenarios/webview_js_executor.dart';
import '../services/remote/remote_script_service.dart';
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

  /// 有缓存 chapter_list_js 脚本时的高亮金色（快速提取可用）
  static const Color _cachedScriptGold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final showButton = ref.watch(webviewHasAddNovelButtonProvider);
    if (!showButton) return const SizedBox.shrink();

    // 金色 = 当前域名已有缓存 chapter_list_js 脚本，点击即可本地快速提取；
    // 默认色 = 无脚本，点击降级 Agent 现场生成。
    final hasCachedScript =
        ref.watch(webviewHasCachedChapterListScriptProvider);

    return FloatingActionButton.small(
      heroTag: 'add_novel_fab',
      onPressed: _isExtracting ? null : () => _handleAddNovel(context),
      tooltip: hasCachedScript ? '添加小说（快速提取）' : '添加小说',
      backgroundColor: hasCachedScript
          ? _cachedScriptGold
          : context.appColors.agentAccent,
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

  Future<void> _handleAddNovel(
    BuildContext context, {
    bool isRemoteRetry = false,
  }) async {
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

    // 4. 无脚本分支：先查云端仓库（v47 起脚本共享），命中且用户确认下载后
    //    重走本流程（isRemoteRetry=true 直接执行本地提取）；未命中 / 用户
    //    选择 AI 写脚本 / 云端不可达 → 降级 agent
    if (script == null) {
      if (isRemoteRetry) {
        // 防御：远程下载流程内重入仍无脚本 → 直接 AI 写脚本，不再查远程
        await _launchAgent(context, currentUrl, domain, null,
            FabFailureReason.noScript);
        return;
      }
      final remoteHandled =
          await _tryRemoteScriptDownload(context, currentUrl, domain);
      if (!mounted) return;
      if (remoteHandled) {
        // 下载已落库：失效 presence 缓存并重走主流程
        ref.read(scriptPresenceByDomainProvider.notifier).invalidateDomain(
              domain,
            );
        await _handleAddNovel(context, isRemoteRetry: true);
        return;
      }
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
          WebViewJsExecutor.replaceUrlPlaceholder(script.chapterListJs, currentUrl);

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
      // 封面图 URL（cover_url / coverUrl 兜底），可空
      final extractedCoverUrl =
          ((data['cover_url'] as String? ?? data['coverUrl'] as String?) ?? '')
              .trim();
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

      // 6. 检查是否已在书架（归一化宽松匹配；命中则沿用已存原始 URL 作为
      //    后续写键——章节缓存/进度都以它为键，避免变体 URL 写散、书架重复）
      final novelRepo = ref.read(novelRepositoryProvider);
      final storedUrl = await novelRepo.findExistingBookshelfUrl(currentUrl);

      if (storedUrl != null) {
        // 已存在：静默更新章节 + 封面回填后直接跳转
        await _saveChapters(storedUrl, chapters);
        await _backfillCoverUrl(storedUrl, extractedCoverUrl);
        _markScriptUsed(script.id);
        _toast('章节已更新');
        if (mounted) {
          // ignore: use_build_context_synchronously
          _navigateToChapterList(context, Novel(
            title: extractedTitle,
            author: '',
            url: storedUrl,
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
          coverUrl:
              extractedCoverUrl.isEmpty ? null : extractedCoverUrl,
        ),
      );

      if (previewResult == null || previewResult['confirmed'] != true) return;

      final finalTitle = (previewResult['title'] as String?) ?? extractedTitle;

      // 8. 写入数据库（封面 URL 一并落 bookshelf.coverUrl，书架封面直接展示）
      // 走 Notifier 收口：写库 + invalidate(bookshelfNovelsProvider)，
      // 浏览器添加小说后书架 UI 立即刷新（修这一类"写了但没刷干净"的根因）。
      await ref.read(bookshelfMutationProvider.notifier).addNovel(Novel(
        title: finalTitle,
        author: '',
        url: currentUrl,
        coverUrl: extractedCoverUrl.isEmpty ? null : extractedCoverUrl,
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

  /// 已在书架时回填封面图 URL（本地此前未抓到封面 / 老版本脚本无封面时）
  ///
  /// 走 BookshelfMutationNotifier 收口（写库 + invalidate 书架列表）。
  /// coverUrl 为空时 no-op。
  Future<void> _backfillCoverUrl(String novelUrl, String coverUrl) async {
    try {
      await ref
          .read(bookshelfMutationProvider.notifier)
          .backfillCoverUrl(novelUrl, coverUrl);
    } catch (e) {
      // 封面回填失败不阻塞添加主流程
      LoggerService.instance.w(
        'FAB添加小说: 封面回填失败 url=$novelUrl error=$e',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-add-novel', 'cover-backfill-failed'],
      );
    }
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

  // ===================================================================
  // 远程脚本下载（v47 起）
  // ===================================================================

  /// FAB 无脚本分支：尝试从云端脚本仓库下载管理员已审核通过的脚本。
  ///
  /// 流程：
  /// 1. 查 [RemoteScriptService.findApprovedCandidate]；无候选或网络失败 → 返回 false（调用方降级 AI）；
  /// 2. 弹确认对话框展示元信息（域名 / 版本 / 下载数 / sha256 / 提交设备 / 含书架脚本）；
  ///    用户选择「下载并启用」 → 调 `downloadAndPersist`；选择「仍让 AI 写」或关闭 → 返回 false。
  /// 3. 下载落库失败 → toast 错误并返回 false。
  ///
  /// 返回 true 表示云端脚本已成功写入本地 [SiteScriptRepository]，调用方应
  /// 失效 `webviewHasCachedChapterListScriptProvider` 并重走主流程。
  Future<bool> _tryRemoteScriptDownload(
    BuildContext context,
    String currentUrl,
    String domain,
  ) async {
    // 未启用托管后端 / 鉴权未注入（测试与离线场景）：直接返回 false 走
    // AI 写脚本路径，避免对未初始化的 ApiServiceWrapper 发请求。
    final api = ref.read(apiServiceWrapperProvider);
    if (!api.isInitialized || api.authHeaderProvider == null) {
      return false;
    }
    final service = ref.read(remoteScriptServiceProvider);
    RemoteScriptMeta? candidate;
    try {
      candidate = await service.findApprovedCandidate(domain);
    } catch (e) {
      LoggerService.instance.w(
        'FAB: 云端脚本搜索失败 domain=$domain - $e, 降级 AI 写脚本',
        category: LogCategory.crawler,
        tags: ['fab-add-novel', 'remote_search', 'failed'],
      );
      return false;
    }
    if (candidate == null) {
      LoggerService.instance.d(
        'FAB: 云端无 host=$domain 的已审核脚本, 降级 AI 写脚本',
        category: LogCategory.crawler,
        tags: ['fab-add-novel', 'remote_search', 'empty'],
      );
      return false;
    }

    if (!mounted) return false;
    final choice = await _showRemoteScriptDialog(context, candidate);
    if (choice != _RemoteScriptChoice.download) {
      LoggerService.instance.i(
        'FAB: 用户拒绝下载云端脚本 domain=$domain choice=$choice, 走 AI 写脚本',
        category: LogCategory.crawler,
        tags: ['fab-add-novel', 'remote_search', 'rejected'],
      );
      return false;
    }

    try {
      final result = await service.downloadAndPersist(candidate);
      _toast(
        result.isInsert
            ? '已下载云端脚本并启用'
            : '已更新本地脚本为云端最新版',
      );
      return true;
    } on LocalScriptConflictException catch (e) {
      // 同 domain 已有本地自建脚本：弹「替换 / 保留 / 另存」对话框
      if (!mounted) return false;
      final conflictChoice =
          await _showLocalConflictDialog(context, e.existingLocal, e.meta);
      if (conflictChoice == _LocalConflictChoice.replace) {
        await service.forceReplaceLocalWithRemote(e.existingLocal, e.meta);
        _toast('已用云端脚本覆盖本地版本');
        return true;
      } else if (conflictChoice == _LocalConflictChoice.saveAsNew) {
        await service.insertAsNewScript(e.meta);
        _toast('已另存为新脚本（仍保留本地原版）');
        // 另存分支：当前 FAB 流程继续用本地原版，但本地原版已存在于 site_scripts。
        // 这里直接返回 false，让 FAB 走主流程的二次执行（此时会命中本地原版）。
        return false;
      }
      return false;
    } catch (e) {
      LoggerService.instance.w(
        'FAB: 下载云端脚本失败 domain=$domain - $e',
        category: LogCategory.crawler,
        tags: ['fab-add-novel', 'remote_download', 'failed'],
      );
      _toast('下载云端脚本失败', isError: true);
      return false;
    }
  }

  /// 「从云端下载脚本」确认对话框
  Future<_RemoteScriptChoice> _showRemoteScriptDialog(
    BuildContext context,
    RemoteScriptMeta meta,
  ) async {
    final choice = await showDialog<_RemoteScriptChoice>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('云端脚本可用'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('域名：${meta.domain}',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text('版本：v${meta.version}'),
                Text('已通过 ${meta.downloadCount} 位用户下载使用'),
                if (meta.displayName.isNotEmpty)
                  Text('站点名：${meta.displayName}'),
                if (meta.hasBookshelfJs) const Text('含：网站书架脚本'),
                const SizedBox(height: 8),
                Text(
                  '指纹：${meta.sha256.substring(0, 16)}…',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '提交设备：${meta.authorDisplayId}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                const Text(
                  '该脚本由其他用户提交并经管理员审核通过。下载后会在当前页面运行，与本地自建脚本权限一致。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                _RemoteScriptChoice.letAiWrite,
              ),
              child: const Text('让 AI 写'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _RemoteScriptChoice.cancel),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, _RemoteScriptChoice.download),
              child: const Text('下载并启用'),
            ),
          ],
        );
      },
    );
    return choice ?? _RemoteScriptChoice.cancel;
  }

  /// 「同 domain 已有本地脚本」冲突对话框
  Future<_LocalConflictChoice> _showLocalConflictDialog(
    BuildContext context,
    SiteScript existing,
    RemoteScriptMeta meta,
  ) async {
    final choice = await showDialog<_LocalConflictChoice>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('该域名已有本地脚本'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('本地：${existing.domain}（已使用 ${existing.useCount} 次）'),
                Text('云端：v${meta.version}（${meta.downloadCount} 次下载）'),
                const SizedBox(height: 10),
                const Text(
                  '请选择：覆盖本地版本、保留本地、或者另存为新脚本（云端脚本 domain 会加 +remote 后缀以共存）。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                _LocalConflictChoice.cancel,
              ),
              child: const Text('保留本地'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                _LocalConflictChoice.saveAsNew,
              ),
              child: const Text('另存为新脚本'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _LocalConflictChoice.replace,
              ),
              child: const Text('覆盖本地'),
            ),
          ],
        );
      },
    );
    return choice ?? _LocalConflictChoice.cancel;
  }
}

enum _RemoteScriptChoice { download, letAiWrite, cancel }

enum _LocalConflictChoice { replace, saveAsNew, cancel }

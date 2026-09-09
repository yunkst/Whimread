/// WebView「导入网站书架」悬浮按钮 + 列表弹窗
///
/// 当当前域名有 AI Agent 生成的 `bookshelf_js` 脚本时显示。
/// 仅在用户位于「我的书架/收藏」页时点击才有意义——按钮不做导航拦截，
/// 由用户自行确保当前页已是书架页（页面已渲染 = 提取脚本能拿到 DOM）。
///
/// ## 交互流程
///
///   1. 点击 → 在当前主 WebView 执行 `bookshelf_js` → 解析 `{novels: [...]}` →
///      弹出 [SiteBookshelfSheet] 列表
///   2. 列表项支持：
///     - 「在浏览器中打开」→ 主 WebView 导航到该小说 URL
///     - 多选 + 「导入选中」→ 批量走 chapter_list_js 链路把选中小说加入书架
///
/// ## 复用
///
/// - JS 执行 → [WebViewJsExecutor]（校验 + IIFE 提取 + callAsyncJavaScript）
/// - 解析 → [SiteBookshelfParser]（纯函数，单测覆盖）
/// - 批量导入章节列表 → [HeadlessWebViewChapterListService] + BookshelfMutationNotifier
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/bookshelf_mutation_provider.dart';
import '../core/providers/chapter_mutation_provider.dart';
import '../core/providers/database_providers.dart';
import '../core/providers/services/network_service_providers.dart';
import '../core/providers/webview_add_novel_providers.dart';
import '../core/providers/webview_providers.dart';
import '../core/theme/app_colors.dart';
import '../models/novel.dart';
import '../models/site_bookshelf_entry.dart';
import '../services/headless_webview_chapter_list_service.dart';
import '../services/headless_webview_errors.dart';
import '../services/logger_service.dart';
import '../services/site_bookshelf_parser.dart';
import '../services/novel_agent/scenarios/webview_js_executor.dart';
import '../utils/toast_utils.dart';

class WebViewImportBookshelfFab extends ConsumerStatefulWidget {
  const WebViewImportBookshelfFab({super.key});

  @override
  ConsumerState<WebViewImportBookshelfFab> createState() =>
      _WebViewImportBookshelfFabState();
}

class _WebViewImportBookshelfFabState
    extends ConsumerState<WebViewImportBookshelfFab> {
  bool _isExtracting = false;

  @override
  Widget build(BuildContext context) {
    // 与 WebViewAddNovelFab 保持一致：仅看 domain（同步 Provider）决定可见性，
    // 实际脚本存在与否在点击时再查库校验；避免 ref.watch FutureProvider
    // 在 widget 树销毁后留下 pending Timer（测试环境会触发
    // "A Timer is still pending" 失败）。
    final showButton = ref.watch(webviewHasAddNovelButtonProvider);
    if (!showButton) return const SizedBox.shrink();

    return FloatingActionButton.small(
      heroTag: 'import_bookshelf_fab',
      tooltip: '导入我的书架',
      backgroundColor: context.appColors.agentAccent,
      foregroundColor: context.appColors.agentOnBrand,
      elevation: 4,
      onPressed: _isExtracting ? null : _onTap,
      child: _isExtracting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.collections_bookmark),
    );
  }

  Future<void> _onTap() async {
    final currentUrl = ref.read(webviewCurrentUrlProvider);
    if (currentUrl.isEmpty) {
      _toast('无法获取当前页面链接', isError: true);
      return;
    }
    final controller = ref.read(webviewControllerProvider);
    if (controller == null) {
      _toast('浏览器未就绪', isError: true);
      return;
    }
    final domain = ref.read(webviewCurrentDomainProvider);
    if (domain == null) {
      _toast('当前页面不是 http(s) 页面', isError: true);
      return;
    }
    // 直接查库，避免触发 FutureProvider 的异步加载链
    final script =
        await ref.read(siteScriptRepositoryProvider).getByDomain(domain);
    if (script == null || !script.hasBookshelfJs) {
      _toast('当前域名无书架脚本', isError: true);
      return;
    }

    setState(() => _isExtracting = true);

    List<SiteBookshelfEntry>? entries;
    String? errorLabel;
    try {
      entries = await _runBookshelfJs(controller, script.bookshelfJs, currentUrl);
      if (entries == null) {
        errorLabel = '脚本执行失败或结果为空';
      }
    } on TimeoutException {
      errorLabel = '提取超时(>120s)';
    } catch (e) {
      errorLabel = '提取异常: $e';
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }

    if (!mounted) return;
    if (entries == null) {
      LoggerService.instance.w(
        'FAB导入书架: $errorLabel url=$currentUrl',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-import-bookshelf', 'failed'],
      );
      _toast(errorLabel ?? '提取失败', isError: true);
      return;
    }

    // 标记脚本已使用
    try {
      ref.read(siteScriptRepositoryProvider).markUsed(script.id);
    } catch (_) {/* 非主流程，吞掉 */}

    LoggerService.instance.i(
      'FAB导入书架: 成功 domain=${script.domain} count=${entries.length}',
      category: LogCategory.ai,
      tags: ['headless-webview', 'fab-import-bookshelf', 'success'],
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      // ignore: use_build_context_synchronously
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SiteBookshelfSheet(entries: entries!),
    );
  }

  /// 在主 WebView 上跑 bookshelf_js 并解析
  Future<List<SiteBookshelfEntry>?> _runBookshelfJs(
    dynamic controller,
    String scriptTemplate,
    String pageUrl,
  ) async {
    final validationError = WebViewJsExecutor.validateScript(scriptTemplate);
    if (validationError != null) {
      LoggerService.instance.w(
        'FAB导入书架: 脚本校验失败 $validationError',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-import-bookshelf', 'validation'],
      );
      return null;
    }
    final resolved = scriptTemplate.replaceAll('{{URL}}', pageUrl);
    final functionBody = WebViewJsExecutor.extractAsyncFunctionBody(resolved);

    final jsResult = await controller
        .callAsyncJavaScript(functionBody: functionBody)
        .timeout(const Duration(seconds: 120));
    if (jsResult == null || jsResult.error != null) {
      LoggerService.instance.w(
        'FAB导入书架: JS执行错误 ${jsResult?.error}',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-import-bookshelf', 'js-error'],
      );
      return null;
    }
    final jsonStr = WebViewJsExecutor.stringifyJsResult(jsResult.value);
    return SiteBookshelfParser.parse(jsonStr);
  }

  void _toast(String message, {bool isError = false}) {
    if (isError) {
      ToastUtils.showError(message);
      return;
    }
    ToastUtils.showSuccess(message);
  }
}

/// 网站书架列表底部弹窗
///
/// - 单条目「打开」按钮：主 WebView 导航到该小说 URL（用户后续可点「添加小说」FAB）
/// - 多选 + 顶部「导入选中」按钮：批量走 chapter_list_js 链路把选中小说加入书架
class SiteBookshelfSheet extends ConsumerStatefulWidget {
  const SiteBookshelfSheet({super.key, required this.entries});

  final List<SiteBookshelfEntry> entries;

  @override
  ConsumerState<SiteBookshelfSheet> createState() =>
      _SiteBookshelfSheetState();
}

class _SiteBookshelfSheetState extends ConsumerState<SiteBookshelfSheet> {
  final Set<int> _selected = {};
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.entries;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏 + 全选/批量操作
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.collections_bookmark,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '网站书架（共 ${entries.length} 本）',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _importing ? null : () => _selected.clear(),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('清空选择'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text(
                  '已选 ${_selected.length} 本',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _importing || _selected.isEmpty
                      ? null
                      : _importSelected,
                  icon: _importing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.library_add, size: 16),
                  label: Text(_importing ? '导入中' : '导入选中'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 列表
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final selected = _selected.contains(index);
                return CheckboxListTile(
                  value: selected,
                  onChanged: _importing
                      ? null
                      : (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(index);
                            } else {
                              _selected.remove(index);
                            }
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    entry.url,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: IconButton(
                    tooltip: '在浏览器中打开',
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    onPressed: _importing
                        ? null
                        : () => _openInBrowser(entry.url),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 在主 WebView 中打开该小说 URL（用户可继续走「添加小说」FAB）
  Future<void> _openInBrowser(String url) async {
    final controller = ref.read(webviewControllerProvider);
    if (controller == null) {
      _toast('浏览器未就绪', isError: true);
      return;
    }
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('已打开');
    } catch (e) {
      LoggerService.instance.w(
        'FAB导入书架: 浏览器打开失败 url=$url error=$e',
        category: LogCategory.ai,
        tags: ['headless-webview', 'fab-import-bookshelf', 'open-failed'],
      );
      _toast('打开失败: $e', isError: true);
    }
  }

  /// 批量导入选中小说：每本 → chapter_list_js 链路（取目录 + 落 Novel + 缓存章节）
  Future<void> _importSelected() async {
    if (_selected.isEmpty || _importing) return;
    setState(() => _importing = true);

    final chapterListService =
        ref.read(headlessWebViewChapterListServiceProvider);
    final novelRepo = ref.read(novelRepositoryProvider);
    final bookshelfMut = ref.read(bookshelfMutationProvider.notifier);
    final chapterMut = ref.read(chapterMutationProvider.notifier);

    var success = 0;
    var updated = 0;
    var failed = 0;
    final selectedEntries =
        _selected.toList().map((i) => widget.entries[i]).toList();
    _selected.clear();

    for (final entry in selectedEntries) {
      if (!mounted) break;
      try {
        final result =
            await chapterListService.fetchChapterList(entry.url);
        if (!result.isSuccess) {
          failed++;
          LoggerService.instance.w(
            '批量导入: 获取目录失败 title=${entry.title} reason=${result.isNoScript ? 'noScript' : result.isBusy ? 'busy' : result.isLoadFailed ? 'loadFailed' : 'unknown'}',
            category: LogCategory.ai,
            tags: ['import', 'batch', 'failed'],
          );
          continue;
        }
        final chapters = result.chapters;
        final coverUrl = result.coverUrl;
        // chapters 已按 chapterIndex 排序（service 内保证）
        if (await novelRepo.isInBookshelf(entry.url)) {
          // 已存在 → 仅刷章节 + 回填封面
          await chapterMut.cacheNovelChapters(entry.url, chapters);
          await bookshelfMut.backfillCoverUrl(entry.url, coverUrl);
          updated++;
        } else {
          await bookshelfMut.addNovel(Novel(
            title: entry.title,
            author: '',
            url: entry.url,
            coverUrl: coverUrl,
          ));
          await chapterMut.cacheNovelChapters(entry.url, chapters);
          success++;
        }
      } catch (e) {
        failed++;
        LoggerService.instance.w(
          '批量导入: 异常 title=${entry.title} error=$e',
          category: LogCategory.ai,
          tags: ['import', 'batch', 'exception'],
        );
      }
    }

    if (!mounted) return;
    setState(() => _importing = false);

    final parts = <String>[];
    if (success > 0) parts.add('新增 $success');
    if (updated > 0) parts.add('更新 $updated');
    if (failed > 0) parts.add('失败 $failed');
    final summary = parts.isEmpty ? '完成' : parts.join('，');
    _toast(summary, isError: failed > 0 && success == 0 && updated == 0);
    if (failed == 0) {
      Navigator.of(context).pop();
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (isError) {
      ToastUtils.showError(message);
      return;
    }
    ToastUtils.showSuccess(message);
  }
}
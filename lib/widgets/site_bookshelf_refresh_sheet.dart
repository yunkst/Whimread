/// 书架屏「刷新网站书架」底部弹窗
///
/// 列出所有有 `bookshelf_js` 缓存脚本的域名。点击某条 → 弹 URL 确认/输入框
/// （脚本自带 sampleUrl 则预填；旧版脚本无 URL 时让用户手动粘贴该站书架页
/// URL）→ 调 HeadlessWebViewBookshelfService 拉取网站最新书架 →
/// SiteBookshelfSyncer 合并到本地。
library;

import 'package:flutter/material.dart';

import 'common/text_prompt_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/bookshelf_mutation_provider.dart';
import '../core/providers/database_providers.dart';
import '../core/providers/services/network_service_providers.dart';
import '../models/site_script.dart';
import '../services/logger_service.dart';
import '../services/site_bookshelf_syncer.dart';
import '../utils/toast_utils.dart';

class SiteBookshelfRefreshSheet extends ConsumerStatefulWidget {
  const SiteBookshelfRefreshSheet({super.key, required this.scripts});

  /// 有 bookshelf_js 缓存脚本的 SiteScript 列表
  final List<SiteScript> scripts;

  @override
  ConsumerState<SiteBookshelfRefreshSheet> createState() =>
      _SiteBookshelfRefreshSheetState();
}

class _SiteBookshelfRefreshSheetState
    extends ConsumerState<SiteBookshelfRefreshSheet> {
  /// 当前正在同步的脚本 id（用于展示进度）
  String? _syncingId;
  int _processed = 0;
  int _total = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(Icons.cloud_sync_outlined, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '刷新网站书架',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_syncingId != null)
                  TextButton(
                    onPressed: null,
                    child: Text('正在同步 $_processed / $_total'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '选择一个站点，从其网站上的「我的书架」拉取最新收藏并合入本地。',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: widget.scripts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final script = widget.scripts[index];
                final isSyncing = _syncingId == script.id;
                final isOtherSyncing = _syncingId != null && !isSyncing;
                return ListTile(
                  enabled: !isOtherSyncing,
                  leading: const Icon(Icons.public),
                  title: Text(script.domain),
                  subtitle: Text(
                    script.sampleUrl.isEmpty
                        ? '未配置 sampleUrl，点击输入书架页 URL'
                        : script.sampleUrl,
                    style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSyncing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: _total > 0 ? _processed / _total : null,
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => _onPickScript(script),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _onPickScript(SiteScript script) async {
    // 1. 确定 fetch URL：脚本自带 sampleUrl 则预填；否则弹输入框让用户填
    String? url;
    if (script.sampleUrl.isNotEmpty) {
      url = script.sampleUrl;
    } else {
      url = await _askUrlForLegacyScript(script);
      if (url == null || url.isEmpty) return;
    }

    // 2. 执行 fetch + merge
    await _runSync(script, url);
  }

  /// 旧版脚本无 sampleUrl 时，让用户输入书架页 URL（预填 https://domain/）
  Future<String?> _askUrlForLegacyScript(SiteScript script) async {
    // TextPromptDialog: 空输入返回 null,与原"空 URL toast"路径等价
    final result = await TextPromptDialog.show(
      context,
      title: '输入 ${script.domain} 的「我的书架」URL',
      label: '书架页 URL',
      initialValue: 'https://${script.domain}/',
      confirmText: '开始同步',
    );
    if (result == null) return null;
    return result;
  }

  Future<void> _runSync(SiteScript script, String url) async {
    setState(() {
      _syncingId = script.id;
      _processed = 0;
      _total = 0;
    });

    try {
      final service =
          ref.read(headlessWebViewBookshelfServiceProvider);
      final result = await service.fetchSiteBookshelf(url);

      if (!result.isSuccess) {
        String msg;
        if (result.isNoScript) {
          msg = '脚本已不可用';
        } else if (result.isBusy) {
          msg = '正在同步中，请稍候';
        } else if (result.isLoadFailed) {
          msg = '页面加载失败';
        } else {
          msg = '脚本执行失败';
        }
        if (!mounted) return;
        _toast(msg, isError: true);
        return;
      }

      final entries = result.entries;
      // 把用户输入的 URL 也写回 sample_url（旧版脚本回填，下次自动用）
      if (script.sampleUrl.isEmpty) {
        try {
          await ref.read(siteScriptRepositoryProvider)
              .updateScriptPart(
                domain: script.domain,
                scriptType: 'bookshelf',
                scriptJs: script.bookshelfJs,
                ocr: false,
                testUrl: url,
              );
        } catch (_) {/* 非主流程，吞掉 */}
      }

      final novelRepo = ref.read(novelRepositoryProvider);
      final bookshelfMut = ref.read(bookshelfMutationProvider.notifier);
      final summary = await SiteBookshelfSyncer.sync(
        entries: entries,
        isInBookshelf: novelRepo.isInBookshelf,
        addNovel: bookshelfMut.addNovel,
        progress: (p) {
          if (!mounted) return;
          setState(() {
            _processed = p.processed;
            _total = p.total;
          });
        },
      );

      if (!mounted) return;
      LoggerService.instance.i(
        '刷新网站书架: domain=${script.domain} added=${summary.added} existing=${summary.alreadyExists} total=${summary.totalFromSite}',
        category: LogCategory.database,
        tags: ['site_bookshelf', 'sync', 'success'],
      );
      _toast('${script.domain}：${summary.summary}');
      // 同步完成后关闭弹窗，让用户继续浏览书架
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      LoggerService.instance.w(
        '刷新网站书架: domain=${script.domain} 异常 error=$e',
        category: LogCategory.database,
        tags: ['site_bookshelf', 'sync', 'failed'],
      );
      if (mounted) _toast('同步异常: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _syncingId = null;
        });
      }
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

/// 弹出「刷新网站书架」选择 sheet（如果没有任何 bookshelf_js 脚本则不调用）
Future<void> showSiteBookshelfRefreshSheet(
  BuildContext context,
  List<SiteScript> scripts,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SiteBookshelfRefreshSheet(scripts: scripts),
  );
}
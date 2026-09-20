/// 站点脚本管理面板
///
/// 以 BottomSheet 形式展示所有已保存的提取脚本，
/// 支持查看详情、验证和删除操作。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../core/providers/remote_script_providers.dart';
import '../core/providers/webview_providers.dart';
import '../core/providers/ocr_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../models/remote_script.dart';
import '../models/site_script.dart';
import '../services/logger_service.dart';
import '../services/novel_agent/scenarios/webview_js_executor.dart';
import '../services/ocr_pua_renderer.dart';
import '../services/ocr_restore_service.dart';
import '../services/remote/remote_script_service.dart';
import 'common/bottom_sheet_header.dart';
import 'empty_states/empty_state_view.dart';

/// 脚本管理面板（通过 showModalBottomSheet 弹出）
class SiteScriptPanel extends ConsumerWidget {
  const SiteScriptPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scriptsAsync = ref.watch(siteScriptListProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(
            icon: Icons.code,
            title: '脚本管理',
            titleStyle: AppTypography.novelTitle.copyWith(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${scriptsAsync.valueOrNull?.length ?? 0} 个站点',
                  style: AppTypography.metaItalic.copyWith(
                    color: context.appColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '从云端下载脚本',
                  icon: const Icon(Icons.cloud_download_outlined, size: 20),
                  onPressed: () => _showRemoteDownloadDialog(context, ref),
                ),
              ],
            ),
          ),
          // 列表区域
          Flexible(
            child: scriptsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 40, color: context.appColors.error),
                    const SizedBox(height: 8),
                    Text('加载失败: $error'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.read(siteScriptListProvider.notifier).refresh(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (scripts) {
                if (scripts.isEmpty) {
                  return _buildEmptyState(context);
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: scripts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _ScriptCard(script: scripts[index]);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.code_off,
      title: '暂无提取脚本',
      subtitle: 'AI 生成脚本后会自动出现在这里',
    );
  }

  /// 「从云端下载脚本」入口：输入域名 → 搜索云端已审核脚本 → 选择下载
  Future<void> _showRemoteDownloadDialog(
      BuildContext context, WidgetRef ref) async {
    final domainController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端下载脚本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入站点域名（如 www.example.com）：'),
            const SizedBox(height: 10),
            TextField(
              controller: domainController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'www.example.com',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            const Text(
              '仅搜索管理员审核通过的脚本。',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('搜索'),
          ),
        ],
      ),
    ).whenComplete(domainController.dispose);
    if (confirmed != true || !context.mounted) return;

    final domain = domainController.text.trim();
    if (domain.isEmpty) return;

    // 搜索并展示候选
    final service = ref.read(remoteScriptServiceProvider);
    RemoteScriptMeta? candidate;
    try {
      candidate = await service.findApprovedCandidate(domain);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('云端搜索失败，请稍后重试')),
        );
      }
      return;
    }
    if (candidate == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('云端没有 $domain 的已审核脚本')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final doDownload = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('找到云端脚本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('域名：${candidate!.domain}'),
            Text('版本：v${candidate.version}'),
            Text('已通过 ${candidate.downloadCount} 位用户下载使用'),
            if (candidate.hasBookshelfJs) const Text('含：网站书架脚本'),
            const SizedBox(height: 6),
            Text(
              '指纹：${candidate.sha256.substring(0, 16)}…',
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('下载并启用'),
          ),
        ],
      ),
    );
    if (doDownload != true || !context.mounted) return;

    try {
      final result = await ref
          .read(siteScriptListProvider.notifier)
          .downloadRemoteScript(candidate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isInsert ? '已下载并启用' : '已更新为云端最新版'),
        ),
      );
    } on LocalScriptConflictException catch (e) {
      if (!context.mounted) return;
      final choice = await _showLocalConflictDialog(context, e);
      if (choice == _LocalConflictChoice.replace) {
        await ref
            .read(siteScriptListProvider.notifier)
            .forceReplaceLocalWithRemote(e.existingLocal, e.meta);
      } else if (choice == _LocalConflictChoice.saveAsNew) {
        await ref
            .read(siteScriptListProvider.notifier)
            .saveRemoteAsNewScript(e.meta);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败，请稍后重试')),
        );
      }
    }
  }

  /// 「同 domain 已有本地脚本」冲突对话框（脚本面板版本）
  static Future<_LocalConflictChoice> _showLocalConflictDialog(
    BuildContext context,
    LocalScriptConflictException e,
  ) {
    return showDialog<_LocalConflictChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('该域名已有本地脚本'),
        content: Text(
          '本地：${e.existingLocal.domain}（已使用 ${e.existingLocal.useCount} 次）\n'
          '云端：v${e.meta.version}（${e.meta.downloadCount} 次下载）\n\n'
          '选择覆盖则丢弃本地版本；选择另存则云端脚本以 +remote 后缀共存。',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LocalConflictChoice.cancel),
            child: const Text('保留本地'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _LocalConflictChoice.saveAsNew),
            child: const Text('另存为新脚本'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _LocalConflictChoice.replace),
            child: const Text('覆盖本地'),
          ),
        ],
      ),
    ).then((v) => v ?? _LocalConflictChoice.cancel);
  }
}

enum _LocalConflictChoice { replace, saveAsNew, cancel }

/// 单个脚本卡片
class _ScriptCard extends ConsumerWidget {
  final SiteScript script;

  const _ScriptCard({required this.script});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 域名行
          Row(
            children: [
              Icon(Icons.language, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  script.displayName.isNotEmpty
                      ? script.displayName
                      : script.domain,
                  style: AppTypography.novelTitle.copyWith(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (script.isVerified)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: appColors.successContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '已验证',
                    style: TextStyle(
                      fontSize: 12,
                      color: appColors.onSuccessContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 显示名（与域名不同时展示，便于了解书架 Tab 名称来源）
          if (script.displayName.isNotEmpty && script.displayName != script.domain)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '站点：${script.domain}',
                style: AppTypography.metaItalic.copyWith(
                  fontSize: 11,
                  color: context.appColors.inkSoft,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // 脚本槽位状态 + 来源标签
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildScriptChip(
                context,
                '目录脚本',
                script.hasChapterListJs,
              ),
              _buildScriptChip(
                context,
                '内容脚本',
                script.hasChapterContentJs,
              ),
              if (script.isRemote)
                _buildScriptChip(
                  context,
                  '云端 v${script.remoteVersion}',
                  true,
                  color: colorScheme.tertiary,
                )
              else
                _buildScriptChip(context, '本地', true,
                    color: context.appColors.inkSoft),
              if (script.isShared)
                _buildScriptChip(context, '已共享', true,
                    color: context.appColors.success),
              if (!script.isEnabled)
                _buildScriptChip(context, '已停用', false,
                    color: context.appColors.error),
            ],
          ),
      const SizedBox(height: 4),
      // 使用统计
      Text(
        '使用 ${script.useCount} 次 · ${_formatDate(script.createdAtDateTime)}',
        style: AppTypography.metaItalic.copyWith(
          fontSize: 11,
          color: context.appColors.inkSoft,
        ),
      ),
      const SizedBox(height: 8),
      // 操作按钮
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 4,
        runSpacing: 4,
        children: [
          _buildActionButton(
            context,
            icon: Icons.visibility_outlined,
            label: '查看',
            onTap: () => _showViewDialog(context, script),
          ),
          _buildActionButton(
            context,
            icon: Icons.edit_outlined,
            label: '改名',
            onTap: () => _showRenameDialog(context, ref, script),
          ),
          _buildActionButton(
            context,
            icon: Icons.check_circle_outline,
            label: '验证',
            onTap: () => _showVerifyConfirm(context, ref, script),
          ),
          _buildActionButton(
            context,
            icon: script.isEnabled
                ? Icons.toggle_on_outlined
                : Icons.toggle_off_outlined,
            label: script.isEnabled ? '停用' : '启用',
            onTap: () async {
              await ref
                  .read(siteScriptListProvider.notifier)
                  .setScriptEnabled(script.id, !script.isEnabled);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(script.isEnabled ? '已停用脚本' : '已启用脚本'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          if (script.isRemote)
            _buildActionButton(
              context,
              icon: Icons.cloud_sync_outlined,
              label: '检查更新',
              onTap: () => _onCheckUpdate(context, ref, script),
            )
          else if (!script.isShared)
            _buildActionButton(
              context,
              icon: Icons.cloud_upload_outlined,
              label: '共享到云端',
              onTap: () => _onShareScript(context, ref, script),
            )
          else
            _buildActionButton(
              context,
              icon: Icons.cloud_off_outlined,
              label: '取消共享',
              onTap: () => _onUnshareScript(context, ref, script),
            ),
          _buildActionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            color: appColors.error,
            onTap: () => _showDeleteConfirm(context, ref, script),
          ),
        ],
      ),
    ],
  ),
);
}

  Widget _buildScriptChip(
      BuildContext context, String label, bool hasScript,
      {Color? color}) {
    final appColors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ??
        (hasScript ? appColors.success : colorScheme.outline);
    final effectiveContainer = color != null
        ? color.withValues(alpha: 0.12)
        : hasScript
            ? appColors.successContainer
            : colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: effectiveContainer,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: effectiveColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            color != null
                ? Icons.circle
                : (hasScript ? Icons.check : Icons.close),
            size: color != null ? 6 : 12,
            color: effectiveColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color != null
                  ? effectiveColor
                  : hasScript
                      ? appColors.onSuccessContainer
                      : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: effectiveColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: effectiveColor),
            ),
          ],
        ),
      ),
    );
  }

  /// 查看脚本详情对话框
  // ------------------------------------------------------------------
  // 云端共享操作（v47 起）
  // ------------------------------------------------------------------

  /// 「共享到云端」：本地脚本上传（提交后进入管理员审核，成功提示等待审核）
  Future<void> _onShareScript(
      BuildContext context, WidgetRef ref, SiteScript script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('共享到云端'),
        content: Text(
          '将 ${script.domain} 的提取脚本上传到云端脚本仓库，供其他用户下载使用。\n\n'
          '上传后需经管理员安全审核，审核通过后其他用户才可见。',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('上传'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref
          .read(siteScriptListProvider.notifier)
          .shareScript(script.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.deduplicated ? '该脚本已提交过，正在审核中' : '已提交，等待管理员审核',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('共享失败，请稍后重试')),
      );
    }
  }

  /// 「取消共享」：从云端撤下（需为作者本人）
  Future<void> _onUnshareScript(
      BuildContext context, WidgetRef ref, SiteScript script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消共享'),
        content: Text(
          '从云端脚本仓库撤下 ${script.domain} 的脚本？\n\n'
          '已下载的用户不受影响，但新用户将无法再搜到。',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('撤下'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(siteScriptListProvider.notifier)
          .unshareScript(script.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从云端撤下')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('取消共享失败，请稍后重试')),
      );
    }
  }

  /// 「检查更新」：云端脚本是否有新版本，有则直接应用
  Future<void> _onCheckUpdate(
      BuildContext context, WidgetRef ref, SiteScript script) async {
    try {
      final newVersion = await ref
          .read(siteScriptListProvider.notifier)
          .checkAndApplyUpdate(script.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVersion == null
                ? '已是最新版本（v${script.remoteVersion}）'
                : '已升级到 v$newVersion',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('检查更新失败，请稍后重试')),
      );
    }
  }

  void _showViewDialog(BuildContext context, SiteScript script) {
    showDialog(
      context: context,
      builder: (ctx) => _ScriptDetailDialog(script: script),
    );
  }

  /// 改名对话框：编辑站点显示名（书架 Tab 优先展示；清空则回退域名）
  void _showRenameDialog(
      BuildContext context, WidgetRef ref, SiteScript script) {
    final controller = TextEditingController(text: script.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名站点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '域名: ${script.domain}',
              style: AppTypography.novelTitle.copyWith(
                fontSize: 14,
                color: context.appColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '站点显示名',
                hintText: '书架 Tab 显示的名字',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              '留空则显示域名。此名字也会显示在书架的站点 Tab 上。',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(siteScriptListProvider.notifier)
                  .renameScript(script.id, controller.text.trim());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  /// 验证：弹出 URL 输入框
  void _showVerifyConfirm(
      BuildContext context, WidgetRef ref, SiteScript script) {
    final currentUrl = ref.read(webviewCurrentUrlProvider);
    final defaultUrl = currentUrl.isNotEmpty && currentUrl != 'https://so.com'
        ? currentUrl
        : script.sampleUrl;
    final urlController = TextEditingController(text: defaultUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('验证脚本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '域名: ${script.domain}',
              style: AppTypography.novelTitle.copyWith(
                fontSize: 14,
                color: context.appColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '输入要验证的页面 URL（脚本中的 {{URL}} 将被替换为该 URL）:',
              style: AppTypography.bodyProse.copyWith(
                fontSize: 12,
                color: context.appColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'https://example.com/book/123',
                hintStyle: TextStyle(fontSize: 12),
              ),
              style: const TextStyle(fontSize: 14),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              '提示：目录脚本填章节列表页 URL；内容脚本填章节内容页 URL。',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('URL 不能为空')),
                );
                return;
              }
              Navigator.pop(ctx);
              await _runVerification(context, ref, script, url);
            },
            child: const Text('运行'),
          ),
        ],
      ),
    ).whenComplete(urlController.dispose);
  }

  /// 执行验证：注入 URL → 在 WebView 中执行脚本 → 展示结果
  Future<void> _runVerification(
    BuildContext context,
    WidgetRef ref,
    SiteScript script,
    String testUrl,
  ) async {
    // 读取 WebView controller
    final controller = ref.read(webviewControllerProvider);

    // 弹出加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在执行脚本...'),
            ],
          ),
        ),
      ),
    );

    if (controller == null) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WebView 尚未初始化')),
        );
      }
      return;
    }

    // 让用户选择要验证哪种脚本
    final scriptType = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要验证的脚本'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'chapter_list_js'),
            child: const Text('目录提取脚本'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'chapter_content_js'),
            child: const Text('内容提取脚本'),
          ),
        ],
      ),
    );

    if (scriptType == null) {
      if (context.mounted) Navigator.pop(context);
      return;
    }

    final scriptCode = scriptType == 'chapter_list_js'
        ? script.chapterListJs
        : script.chapterContentJs;

    if (scriptCode.isEmpty) {
      if (context.mounted) Navigator.pop(context); // 关闭加载框
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该脚本为空')),
        );
      }
      return;
    }

    // 校验脚本规范（与正式提取路径一致：必须含 {{URL}} 占位符等）
    final validationError = WebViewJsExecutor.validateScript(scriptCode);
    if (validationError != null) {
      if (context.mounted) Navigator.pop(context); // 关闭加载框
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('脚本校验失败: $validationError')),
        );
      }
      return;
    }

    // 替换 {{URL}} 为测试 URL
    final resolvedScript = WebViewJsExecutor.replaceUrlPlaceholder(scriptCode, testUrl);

    // 提取 IIFE 函数体（Agent 生成的脚本是 async IIFE，
    // 需拆出函数体供 callAsyncJavaScript 执行）
    final functionBody =
        WebViewJsExecutor.extractAsyncFunctionBody(resolvedScript);

    // 执行脚本（与正式提取路径一致：callAsyncJavaScript 完美支持 async/await；
    // evaluateJavascript 在 WebView2 上不等待 Promise，async 脚本拿不到结果）
    String? resultStr;
    String? errorMsg;
    try {
      final result = await controller
          .callAsyncJavaScript(functionBody: functionBody)
          .timeout(const Duration(seconds: 120));

      if (result == null) {
        resultStr = WebViewJsExecutor.stringifyJsResult(null);
      } else if (result.error != null) {
        // JS Promise reject
        errorMsg = result.error.toString();
      } else {
        resultStr = WebViewJsExecutor.stringifyJsResult(result.value);
      }
    } on TimeoutException {
      errorMsg = '脚本执行超时（>120秒）';
    } catch (e) {
      errorMsg = e.toString();
    }

    // 记录执行日志（供 AI 通过 get_script_logs 查询，定位脚本面板试运行的失败）
    if (errorMsg != null) {
      LoggerService.instance.w(
        '脚本面板验证失败: domain=${script.domain} scriptType=$scriptType url=$testUrl error=$errorMsg',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'script-panel-verify', 'failed'],
      );
    } else {
      LoggerService.instance.i(
        '脚本面板验证成功: domain=${script.domain} scriptType=$scriptType url=$testUrl resultLen=${resultStr?.length ?? 0}',
        category: LogCategory.crawler,
        tags: ['headless-webview', 'script-panel-verify', 'success'],
      );
    }

    if (context.mounted) Navigator.pop(context); // 关闭加载框

    if (!context.mounted) return;

    // OCR 判断与还原（与正式提取路径一致）
    final needsOcr = scriptType == 'chapter_list_js'
        ? script.chapterListOcr
        : script.chapterContentOcr;
    String? ocrRestoredText;
    double? readableRatio;
    double? decodedRatio;
    String? ocrError;

    if (needsOcr && resultStr != null && errorMsg == null) {
      try {
        final jsResult = jsonDecode(resultStr);
        final fontFamily = _extractFontFamily(jsResult);
        if (fontFamily.isEmpty) {
          ocrError = '脚本标记为 OCR，但返回结果中缺少 font_family 字段';
        } else {
          final restoreService = OcrRestoreService.forTesting(
            renderPua: (cp, ff) =>
                _renderPuaViaController(controller, cp, ff),
            recognizeImageFn: (b64) async {
              final predictor = await ref.read(ocrPredictorProvider.future);
              return predictor.recognizeImage(b64);
            },
          );
          // 验证字体有效性
          final fontValid = await restoreService.verifyFontFamily(fontFamily);
          if (!fontValid) {
            ocrError = '字体家族 "$fontFamily" 验证失败（PUA 渲染无差异）';
          } else {
            // 提取目标文本并还原
            final targetText = _extractOcrTargetText(jsResult, scriptType);
            final restored = await restoreService.restorePuaInText(
              targetText,
              fontFamily,
            );
            ocrRestoredText = restored.text;
            readableRatio = restoreService.readableRatio(restored.text);
            decodedRatio = restored.decodedRatio;
            if (restored.totalPuaCount == 0) {
              ocrError = '脚本标记为 OCR，但返回文本中未检测到 PUA 码点';
            }
          }
        }
      } on TimeoutException {
        ocrError = 'OCR 验证超时（>30秒）';
      } catch (e) {
        ocrError = 'OCR 处理异常: $e';
      }
    }

    // 展示结果
    _showVerifyResultDialog(
      context,
      ref,
      script,
      scriptType,
      testUrl,
      resultStr,
      errorMsg,
      needsOcr: needsOcr,
      ocrRestoredText: ocrRestoredText,
      readableRatio: readableRatio,
      decodedRatio: decodedRatio,
      ocrError: ocrError,
    );
  }

  /// 展示验证结果
  void _showVerifyResultDialog(
    BuildContext context,
    WidgetRef ref,
    SiteScript script,
    String scriptType,
    String testUrl,
    String? resultStr,
    String? errorMsg, {
    bool needsOcr = false,
    String? ocrRestoredText,
    double? readableRatio,
    double? decodedRatio,
    String? ocrError,
  }) {
    final success = errorMsg == null && resultStr != null;
    // OCR 整体成功：标记 OCR 的脚本，还原文本非空且无 OCR 错误
    final ocrSuccess = needsOcr && ocrRestoredText != null && ocrError == null;

    if (success) {
      ref.read(siteScriptListProvider.notifier).verifyScript(script.id);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success
                  ? context.appColors.success
                  : context.appColors.error,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(success ? '执行成功' : '执行失败'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildResultRow(context, '脚本类型',
                  scriptType == 'chapter_list_js' ? '目录脚本' : '内容脚本'),
              _buildResultRow(context, '测试 URL', testUrl),
              if (needsOcr)
                _buildResultRow(context, 'OCR 标识', '是（字体反爬）'),
              if (errorMsg != null)
                _buildResultRow(context, '错误信息', errorMsg,
                    color: context.appColors.error),
              if (ocrError != null)
                _buildResultRow(context, 'OCR 警告', ocrError,
                    color: context.appColors.warning),
              if (ocrSuccess) ...[
                const SizedBox(height: 4),
                Text(
                  'OCR 还原结果:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: context.appColors.success.withValues(alpha: 0.5),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      ocrRestoredText,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可读性: ${(readableRatio! * 100).toStringAsFixed(1)}%  |  '
                  'PUA 解码率: ${(decodedRatio! * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: readableRatio >= 0.75
                        ? context.appColors.success
                        : context.appColors.warning,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (resultStr != null) ...[
                const SizedBox(height: 4),
                Text(
                  '原始返回:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _formatResult(resultStr),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: resultStr ?? errorMsg ?? ''));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制到剪贴板'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('复制结果'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(BuildContext context, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// 格式化结果：尝试解析为 JSON 后美化
  String _formatResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  /// 删除确认对话框
  void _showDeleteConfirm(
      BuildContext context, WidgetRef ref, SiteScript script) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除脚本'),
        content: Text(
          '确定要删除 ${script.domain} 的提取脚本吗？\n\n'
          '此操作不可撤销。',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: context.appColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(siteScriptListProvider.notifier)
                  .deleteScript(script.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // ===== OCR 辅助方法（与正式提取路径 webview_extract_scenario.dart 一致）=====

  /// 从 jsResult 中取 font_family（snake/camel 兜底）。
  static String _extractFontFamily(dynamic data) {
    if (data is! Map) return '';
    final v = data['font_family'] ?? data['fontFamily'];
    if (v is! String) return '';
    return v.trim();
  }

  /// 从 jsResult 提取 OCR 目标文本。
  /// - chapter_content: 直接取 content
  /// - chapter_list: 拼接 title + 所有 chapters[].title
  static String _extractOcrTargetText(dynamic jsResult, String scriptType) {
    if (jsResult is! Map) return '';
    if (scriptType == 'chapter_content_js') {
      return ((jsResult['content'] as String?) ?? '');
    }
    final title = (jsResult['title'] as String?) ?? '';
    final chapters = jsResult['chapters'];
    final chapterTitles = chapters is List
        ? chapters
            .whereType<Map>()
            .map((c) => (c['title'] as String?) ?? '')
            .join(' ')
        : '';
    return '$title $chapterTitles';
  }

  /// 在当前浏览器 WebView 中渲染单个 PUA 码点 → 返回 base64 PNG。
  /// 委托给共享实现 [renderPuaViaController]，消除跨模块重复。
  static Future<String> _renderPuaViaController(
    dynamic controller,
    int codepoint,
    String fontFamily,
  ) async {
    return renderPuaViaController(controller as InAppWebViewController, codepoint, fontFamily);
  }
}

/// 脚本详情查看对话框
class _ScriptDetailDialog extends StatefulWidget {
  final SiteScript script;

  const _ScriptDetailDialog({required this.script});

  @override
  State<_ScriptDetailDialog> createState() => _ScriptDetailDialogState();
}

class _ScriptDetailDialogState extends State<_ScriptDetailDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final script = widget.script;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      script.domain,
                      style: AppTypography.novelTitle.copyWith(
                        fontSize: 16,
                        color: context.appColors.ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Tab 切换
            TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(fontSize: 14),
              tabs: const [
                Tab(text: '目录脚本'),
                Tab(text: '内容脚本'),
              ],
            ),
            // 代码区域
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCodeView(script.chapterListJs, '目录脚本'),
                  _buildCodeView(script.chapterContentJs, '内容脚本'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeView(String code, String type) {
    if (code.isEmpty) {
      return Center(
        child: Text(
          '$type 为空',
          style: AppTypography.metaItalic.copyWith(
            fontSize: 14,
            color: context.appColors.inkSoft,
          ),
        ),
      );
    }
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: IconButton.filled(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制到剪贴板'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            style: IconButton.styleFrom(
              minimumSize: const Size(36, 36),
            ),
          ),
        ),
      ],
    );
  }
}

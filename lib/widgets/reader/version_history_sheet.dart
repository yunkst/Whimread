import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/chapter_mutation_provider.dart';
import '../../core/providers/database_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/chapter_version.dart';
import '../../utils/toast_utils.dart';
import '../common/bottom_sheet_header.dart';
import '../empty_states/empty_state_view.dart';

/// 版本历史底部面板
///
/// 以 BottomSheet 形式展示当前章节的所有历史版本，
/// 支持预览、还原和删除操作。
class VersionHistorySheet extends ConsumerStatefulWidget {
  final String chapterUrl;
  final String chapterTitle;
  final String novelUrl; // 章节所属小说 URL（还原走 ChapterMutationNotifier 收口）
  final VoidCallback onRestored; // 还原后刷新阅读器的回调

  const VersionHistorySheet({
    super.key,
    required this.chapterUrl,
    required this.chapterTitle,
    required this.novelUrl,
    required this.onRestored,
  });

  /// 弹出 BottomSheet 的静态方法
  static Future<void> show(
    BuildContext context, {
    required String chapterUrl,
    required String chapterTitle,
    required String novelUrl,
    required VoidCallback onRestored,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => VersionHistorySheet(
        chapterUrl: chapterUrl,
        chapterTitle: chapterTitle,
        novelUrl: novelUrl,
        onRestored: onRestored,
      ),
    );
  }

  @override
  ConsumerState<VersionHistorySheet> createState() =>
      _VersionHistorySheetState();
}

class _VersionHistorySheetState extends ConsumerState<VersionHistorySheet> {
  List<ChapterVersion> _versions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    try {
      final repo = ref.read(chapterVersionRepositoryProvider);
      final versions = await repo.getVersions(widget.chapterUrl);
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(
            icon: Icons.history,
            title: '版本历史',
            titleStyle: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    widget.chapterTitle,
                    style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_versions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_versions.length}个版本',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 版本列表
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _versions.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _versions.length,
                        itemBuilder: (context, index) {
                          final version = _versions[index];
                          return _buildVersionTile(version);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const EmptyStateView(
      icon: Icons.history_toggle_off,
      title: '暂无历史版本',
      subtitle: '编辑或AI改写章节时，旧内容会自动保存为历史版本',
    );
  }

  Widget _buildVersionTile(ChapterVersion version) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(version.sourceIcon, size: 20,
          color: _sourceColor(version.source)),
      title: Row(
        children: [
          Text(version.sourceLabel,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text(version.formattedLength,
              style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7))),
        ],
      ),
      subtitle: Text(version.formattedTime,
          style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.7))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 预览
          IconButton(
            icon: const Icon(Icons.visibility_outlined, size: 18),
            tooltip: '预览',
            onPressed: () => _previewVersion(version),
          ),
          // 还原
          IconButton(
            icon: const Icon(Icons.restore, size: 18),
            tooltip: '还原',
            onPressed: () => _restoreVersion(version),
          ),
          // 删除
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18,
                color: colorScheme.error),
            tooltip: '删除',
            onPressed: () => _deleteVersion(version),
          ),
        ],
      ),
    );
  }

  Color? _sourceColor(String source) {
    final appColors = context.appColors;
    switch (source) {
      case 'edit':
        return appColors.info;
      case 'ai_rewrite':
        return appColors.agentAccent;
      case 'manual_snapshot':
        return appColors.success;
      case 'restore':
        return appColors.warning;
      default:
        return Theme.of(context).colorScheme.outlineVariant;
    }
  }

  /// 预览版本内容
  void _previewVersion(ChapterVersion version) {
    final previewText = version.content.length > 2000
        ? '${version.content.substring(0, 2000)}\n\n... (共${version.contentLength}字)'
        : version.content;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(version.sourceIcon, size: 20,
                color: _sourceColor(version.source)),
            const SizedBox(width: 8),
            Text('${version.sourceLabel} · ${version.formattedTime}'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(previewText, style: const TextStyle(fontSize: 14, height: 1.6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _restoreVersion(version);
            },
            child: const Text('还原此版本'),
          ),
        ],
      ),
    );
  }

  /// 还原到指定版本
  Future<void> _restoreVersion(ChapterVersion version) async {
    // 先关闭 BottomSheet
    Navigator.of(context).pop();

    // 二次确认
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.restore, color: ctx.appColors.warning),
          const SizedBox(width: 8),
          const Text('还原到历史版本'),
        ]),
        content: Text(
          '将当前内容替换为「${version.sourceLabel}」'
          '（${version.formattedTime}，${version.formattedLength}）的版本？\n\n'
          '当前内容将自动保存为历史版本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('还原'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // 走 ChapterMutationNotifier 收口：写库 + bump signal 触发章节列表软刷新。
      await ref.read(chapterMutationProvider.notifier).updateChapterContent(
        widget.chapterUrl,
        version.content,
        source: 'restore',
        novelUrl: widget.novelUrl,
      );

      if (mounted) {
        ToastUtils.showSuccess('已还原到历史版本', context: context);
      }

      // 通知阅读器刷新
      widget.onRestored();
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('还原失败: $e', context: context);
      }
    }
  }

  /// 删除指定版本
  Future<void> _deleteVersion(ChapterVersion version) async {
    // 先关闭 BottomSheet
    Navigator.of(context).pop();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除版本'),
        content: Text(
          '确定删除「${version.sourceLabel}」'
          '（${version.formattedTime}）的版本？此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final versionRepo = ref.read(chapterVersionRepositoryProvider);
      await versionRepo.deleteVersion(version.id!);

      if (mounted) {
        ToastUtils.showSuccess('版本已删除', context: context);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('删除失败: $e', context: context);
      }
    }
  }
}

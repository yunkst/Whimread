/// 媒体缓存管理页
///
/// 列出 media_items 全部媒体（AI 生成图/视频 + 用户上传），支持：
/// - 查看总占用、按 kind 筛选（全部/图片/视频）
/// - 单项删除（删本地文件 + 元数据）
///
/// localOnly（用户上传）项标注"本地唯一副本，删除不可恢复"。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/media/media_proxy.dart';
import '../../services/media/media_store.dart';
import '../../services/media/media_types.dart';
import '../../utils/format_utils.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/media/media_view.dart';
import 'media_preview_screen.dart';

class MediaCacheScreen extends ConsumerStatefulWidget {
  const MediaCacheScreen({super.key});

  @override
  ConsumerState<MediaCacheScreen> createState() => _MediaCacheScreenState();
}

class _MediaCacheScreenState extends ConsumerState<MediaCacheScreen> {
  List<MediaItem> _all = const [];
  int _usedSpace = 0;
  bool _loading = true;
  MediaKind? _filter; // null=全部

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final proxy = ref.read(mediaProxyProvider);
      final items = await proxy.listAll();
      final space = await MediaStore.instance.usedSpace();
      if (mounted) {
        setState(() {
          _all = items;
          _usedSpace = space;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MediaItem> get _filtered =>
      _filter == null ? _all : _all.where((i) => i.kind == _filter).toList();

  Future<void> _deleteItem(MediaItem item) async {
    final localOnlyWarn =
        item.localOnly ? '\n\n该媒体是本地唯一副本，删除后不可恢复。' : '';
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除媒体',
      message: '确定删除该图片？$localOnlyWarn',
      confirmText: '删除',
      isDangerous: true,
    );
    if (confirmed != true) return;
    await ref.read(mediaProxyProvider).delete(item.mediaId);
    _refresh();
  }

  String _sourceLabel(MediaSource s) {
    switch (s) {
      case MediaSource.localUpload:
        return '用户上传';
      case MediaSource.aiGenerated:
        return 'AI 生成';
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '清空媒体',
      message: '将删除全部媒体（含本地唯一副本，删除后不可恢复）。是否继续？',
      confirmText: '清空',
      isDangerous: true,
    );
    if (confirmed != true || !mounted) return;
    for (final item in _all) {
      await ref.read(mediaProxyProvider).delete(item.mediaId);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '媒体缓存',
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '总占用：${FormatUtils.formatFileSize(_usedSpace)}',
                              style: AppTypography.novelTitle.copyWith(
                                fontSize: 14,
                                color: context.appColors.ink,
                              ),
                            ),
                            Text(
                              '${_all.length} 项媒体',
                              style: AppTypography.metaItalic.copyWith(
                                color: context.appColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _all.isEmpty ? null : _clearAll,
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 18),
                        label: const Text('清空全部'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      _chip('全部', null),
                      _chip('图片', MediaKind.image),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            '暂无媒体',
                            style: AppTypography.bodyProse.copyWith(
                              fontSize: 15,
                              color: context.appColors.inkSoft,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final item = _filtered[i];
                            return _MediaTile(
                              item: item,
                              sourceLabel: _sourceLabel,
                              onDelete: () => _deleteItem(item),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _chip(String label, MediaKind? kind) {
    final selected = _filter == kind;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = selected ? null : kind),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final MediaItem item;
  final String Function(MediaSource) sourceLabel;
  final VoidCallback onDelete;

  const _MediaTile({
    required this.item,
    required this.sourceLabel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: _thumb(context),
      title: Text(
        item.mediaId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
      subtitle: Text(
        [
          sourceLabel(item.source),
          '图片',
          FormatUtils.formatFileSize(item.localBytes),
          if (item.localOnly) '本地唯一副本',
        ].join(' · '),
        style: AppTypography.metaItalic.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
      ),
    );
  }

  Widget _thumb(BuildContext context) {
    final heroTag = 'media_cache_image_${item.mediaId}';
    return GestureDetector(
      onTap: () => _openImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          // Hero 与 MediaPreviewScreen 初项同 tag，点开播转场。
          // 2026-10 审查：缩略图曾绕开 MediaView 直查 MediaStore——解析路径
          // 归一后统一走 MediaView（加载/miss 占位、状态持有都在它那里）
          child: Hero(
            tag: heroTag,
            child: MediaView(mediaId: item.mediaId, boxFit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  void _openImage(BuildContext context) {
    MediaPreviewScreen.open(
      context,
      item.mediaId,
      heroTag: 'media_cache_image_${item.mediaId}',
    );
  }
}

/// 媒体画廊卡片 — 渲染 create_images / create_image_to_video 工具结果
///
/// 替代旧 image_gallery_card.dart。区别：
/// - 工具结果统一用 mediaId（不再有 imageId+taskId 双字段）
/// - 单张渲染交给 MediaView（状态机/轮询/全屏缩放都在那里），本卡片只负责
///   "解析 + 排版（单条直出 / 多条 PageView + 页码）"
/// - 同时认 images 数组（图，create_images）和 videos 数组（视频，create_image_to_video）
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/media/media_types.dart';
import '../media/media_view.dart';

class MediaGalleryItem {
  final String mediaId;
  final MediaKind kind;
  final String prompt;

  const MediaGalleryItem({
    required this.mediaId,
    required this.kind,
    required this.prompt,
  });
}

class MediaGalleryData {
  final List<MediaGalleryItem> items;
  const MediaGalleryData({required this.items});
}

/// 解析工具结果 JSON。
/// - create_images 返回 images 数组（每项含 mediaId；兼容旧格式的 taskId 字段）
/// - create_image_to_video 返回 videos 数组（每项含 mediaId）
/// 成功且至少一项有效时返回 MediaGalleryData，否则 null。
MediaGalleryData? parseMediaGallery(String? toolResultJson) {
  if (toolResultJson == null) return null;
  try {
    final json = jsonDecode(toolResultJson) as Map<String, dynamic>;
    if (json['success'] != true) return null;
    final items = <MediaGalleryItem>[];

    final rawImages = json['images'];
    if (rawImages is List) {
      for (final m in rawImages) {
        if (m is! Map) continue;
        // mediaId 优先；回退 taskId 兼容历史会话 hydrate 的旧结果
        final mediaId = (m['mediaId'] ?? m['taskId']) as String?;
        if (mediaId == null) continue;
        items.add(MediaGalleryItem(
          mediaId: mediaId,
          kind: MediaKind.image,
          prompt: (m['prompt'] as String?) ?? '',
        ));
      }
    }

    final rawVideos = json['videos'];
    if (rawVideos is List) {
      for (final m in rawVideos) {
        if (m is! Map) continue;
        final mediaId = m['mediaId'] as String?;
        if (mediaId == null) continue;
        items.add(MediaGalleryItem(
          mediaId: mediaId,
          kind: MediaKind.video,
          prompt: (m['prompt'] as String?) ?? '',
        ));
      }
    }

    if (items.isEmpty) return null;
    return MediaGalleryData(items: items);
  } catch (_) {
    return null;
  }
}

class MediaGalleryCard extends StatelessWidget {
  final MediaGalleryData data;
  const MediaGalleryCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final items = data.items;
    if (items.length == 1) {
      return _GallerySlot(item: items.first, allItems: items, index: 0);
    }
    return _MultiGallery(items: items);
  }
}

class _MultiGallery extends StatefulWidget {
  final List<MediaGalleryItem> items;
  const _MultiGallery({required this.items});
  @override
  State<_MultiGallery> createState() => _MultiGalleryState();
}

class _MultiGalleryState extends State<_MultiGallery> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 320,
            child: PageView.builder(
              itemCount: total,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _GallerySlot(
                item: widget.items[i],
                allItems: widget.items,
                index: i,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_index + 1} / $total',
          style: AppTypography.metaItalic.copyWith(
            color: context.appColors.inkSoft,
          ),
        ),
      ],
    );
  }
}

/// 单个媒体槽位：MediaView + 点击全屏（全屏可滑动看 allItems 全部）。
///
/// 重要：[MediaView] 非全屏分支内部用了 `Stack(fit: StackFit.expand)`（见
/// media_view.dart），该 Stack 在父约束纵轴 unbounded（如本卡片嵌在
/// ListView.builder 的 item 的 Column 中时）会触发
/// `BoxConstraints forces an infinite height` 异常，导致 ListView item
/// 高度塌缩、滚动手势失灵。
///
/// 因此本槽位必须为 [MediaView] 提供 **bounded 父约束**：1:1 方形适合
/// AI 生成的小说插图（ComfyUI 默认方形输出）。如未来需要其他比例，
/// 把 [AspectRatio] 换成 [ConstrainedBox(maxHeight: ...)] 即可。
class _GallerySlot extends StatelessWidget {
  final MediaGalleryItem item;
  final List<MediaGalleryItem> allItems;
  final int index;

  const _GallerySlot({
    required this.item,
    required this.allItems,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: MediaView(
        mediaId: item.mediaId,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _FullScreenGallery(
              items: allItems,
              initialIndex: index,
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenGallery extends StatefulWidget {
  final List<MediaGalleryItem> items;
  final int initialIndex;
  const _FullScreenGallery({required this.items, required this.initialIndex});
  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final isVideo = widget.items[_index].kind == MediaKind.video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        foregroundColor: Colors.white,
        title: Text(
          total > 1 ? '${_index + 1} / $total' : (isVideo ? '视频' : '图片'),
          style: AppTypography.metaItalic.copyWith(
            fontSize: 14,
            color: context.appColors.galleryOnDark,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: total,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => MediaView(
          mediaId: widget.items[i].mediaId,
          fullscreen: true,
        ),
      ),
    );
  }
}

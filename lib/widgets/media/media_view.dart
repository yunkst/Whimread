/// 媒体展示 widget — 渲染图片
///
/// 只认一个 `mediaId`（通过 mediaProxyProvider 解析）：本地命中→显示；
/// miss→**终态占位**（"图片不可用" + 手动重新加载按钮）。
///
/// miss 语义：云端回源端点已下线（v51 起存量记录已归一），解析不出就是
/// 真的没有——不会自愈，所以不做任何自动轮询/重试（原实现的"可见时 10s
/// 轮询"是回源时代的遗物，只会让死 id 在前台空转），交给手动刷新。
/// 无效 id 的入口侧防护见 ToolExecutorHelpers.mediaNotFoundError。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';

import '../../services/logger_service.dart';
import '../../services/media/media_proxy.dart';
import '../../services/media/media_types.dart';

/// 单个媒体展示。mediaId 由调用方提供（AI 生成 / 用户上传 local_xxx）。
class MediaView extends ConsumerStatefulWidget {
  final String mediaId;
  final VoidCallback? onTap;
  final bool fullscreen;

  /// 渲染模式：null=默认（图片 contain + 全屏角标）；非 null=嵌入渲染
  ///（用指定 fit，如头像的 BoxFit.cover，无角标）。
  final BoxFit? boxFit;

  const MediaView({
    super.key,
    required this.mediaId,
    this.onTap,
    this.fullscreen = false,
    this.boxFit,
  });

  @override
  ConsumerState<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends ConsumerState<MediaView> {
  File? _file;
  MediaKind? _kind;
  bool _loading = false;

  /// miss 终态：解析不出 → 展示明确占位（不再转圈）
  bool _missed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    if (mounted) setState(() => _missed = false);
    try {
      final proxy = ref.read(mediaProxyProvider);
      final result = await proxy.resolve(widget.mediaId);
      if (!mounted) return;
      if (result.status == MediaStatus.loaded) {
        final path = result.localPathHint;
        if (path != null) {
          setState(() {
            _file = File(path);
            _kind = result.kind;
          });
        }
      } else {
        setState(() => _missed = true);
      }
    } catch (e) {
      LoggerService.instance.d(
        'MediaView 加载失败: mediaId=${widget.mediaId}, $e',
        category: LogCategory.ai,
        tags: ['media_view', 'load_failed'],
      );
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = _file;
    final kind = _kind;

    if (file != null && kind != null) {
      return _ImageContent(
        file: file,
        fullscreen: widget.fullscreen,
        onTap: widget.onTap,
        boxFit: widget.boxFit,
      );
    }

    final refreshButton = IconButton(
      icon: const Icon(Icons.refresh, size: 18),
      tooltip: '重新加载',
      onPressed: _loading ? null : _load,
      style: IconButton.styleFrom(
        backgroundColor: widget.fullscreen
            ? Colors.white.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHigh,
        foregroundColor: widget.fullscreen ? Colors.white : theme.colorScheme.primary,
        minimumSize: const Size(32, 32),
      ),
    );

    // miss 终态：明确告知不可用（转圈会让人以为还在加载——它不会自愈）
    if (_missed) {
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 20, color: theme.colorScheme.outline),
          const SizedBox(height: 6),
          Text('图片不可用',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 4),
          refreshButton,
        ],
      );
      if (widget.fullscreen) {
        return Container(color: Colors.black, alignment: Alignment.center, child: content);
      }
      return Container(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: content,
      );
    }

    // 加载中
    final loading = Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: theme.colorScheme.primary),
      ),
    );
    if (widget.fullscreen) {
      return Container(color: Colors.black, alignment: Alignment.center, child: loading);
    }
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      alignment: Alignment.center,
      child: loading,
    );
  }
}

/// 图片内容：非全屏 Image.file + 点击全屏角标；全屏 PhotoView 缩放。
class _ImageContent extends StatelessWidget {
  final File file;
  final bool fullscreen;
  final VoidCallback? onTap;
  final BoxFit? boxFit;

  const _ImageContent({
    required this.file,
    required this.fullscreen,
    this.onTap,
    this.boxFit,
  });

  @override
  Widget build(BuildContext context) {
    if (fullscreen) {
      return PhotoView(
        imageProvider: FileImage(file),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        loadingBuilder: (_, __) => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // 嵌入模式（boxFit 非 null，如头像）：无全屏角标
    if (boxFit != null) {
      final image = Image.file(file, fit: boxFit);
      return onTap == null
          ? image
          : GestureDetector(onTap: onTap, child: image);
    }
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(file, fit: BoxFit.contain),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.fullscreen, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

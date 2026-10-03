/// 媒体展示 widget — 渲染图片
///
/// 只认一个 `mediaId`（通过 mediaProxyProvider 解析）：本地命中→显示；
/// miss→保持占位（前台可见时低频重试）。图片走 Image.file / PhotoView
/// （全屏缩放）。
///
/// 轮询条件：组件可见（visibleFraction > 0）且 app 前台（resumed）；
/// fullscreen 模式恒可见。loaded 后停轮询。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../services/logger_service.dart';
import '../../services/media/media_proxy.dart';
import '../../services/media/media_types.dart';

/// 单个媒体展示。mediaId 由调用方提供（AI 生成=task_id，用户上传=local_xxx）。
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

/// 可见性迟滞阈值：超过 [_kPlayThreshold] 视为可见，低于 [_kPauseThreshold]
/// 视为不可见，区间内保持上一态（防抖，避免边缘 fling 抖动）。
const double _kPlayThreshold = 0.5;
const double _kPauseThreshold = 0.1;

/// 可见性双阈值迟滞（公开以便单元测试）。
///
/// 当前可见时，fraction 掉到 [kPauseThreshold] 以下才转不可见；
/// 当前不可见时，fraction 升到 [kPlayThreshold] 以上才转可见。
/// 0.1~0.5 区间保持上一态，避免在屏幕边缘反复触发重载。
@visibleForTesting
bool mediaPlayHysteresis({
  required bool current,
  required double fraction,
  double playThreshold = _kPlayThreshold,
  double pauseThreshold = _kPauseThreshold,
}) {
  if (current) {
    return fraction > pauseThreshold;
  } else {
    return fraction > playThreshold;
  }
}

class _MediaViewState extends ConsumerState<MediaView>
    with WidgetsBindingObserver {
  File? _file;
  MediaKind? _kind;
  bool _loading = false;
  bool _visible = false;
  bool _appActive = true;
  Timer? _timer;

  /// 可见性判定（双阈值，避免边缘抖动）。
  /// 视频/进度轮询共用此决策；将来扩展"中心优先"等全局策略时只需改这里。
  bool get _shouldPoll =>
      _file == null && _appActive && (widget.fullscreen || _visible);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visible = widget.fullscreen;
    _load();
    _evaluateTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive != active) {
      _appActive = active;
      if (active && _file == null) _load();
      _evaluateTimer();
    }
  }

  /// 双阈值迟滞：只在跨越阈值时才翻转状态，0.1~0.5 区间保持上一态。
  void _onVisibilityChanged(VisibilityInfo info) {
    final next = mediaPlayHysteresis(
      current: _visible,
      fraction: info.visibleFraction,
    );
    if (_visible != next) {
      setState(() {
        _visible = next;
        if (next && _file == null) _load();
      });
      _evaluateTimer();
    }
  }

  void _evaluateTimer() {
    if (_shouldPoll) {
      if (_timer == null || !_timer!.isActive) {
        _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    if (mounted) setState(() {});
    try {
      final proxy = ref.read(mediaProxyProvider);
      final result = await proxy.resolve(widget.mediaId);
      if (!mounted) return;
      switch (result.status) {
        case MediaStatus.loaded:
          final path = result.localPathHint;
          if (path != null) {
            setState(() {
              _file = File(path);
              _kind = result.kind;
            });
          }
          break;
        case MediaStatus.miss:
          // 保持 loading 态（附手动刷新按钮）
          break;
      }
      _evaluateTimer();
    } catch (e) {
      LoggerService.instance.d(
        'MediaView 加载失败: mediaId=${widget.mediaId}, $e',
        category: LogCategory.ai,
        tags: ['media_view', 'load_failed'],
      );
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = _file;
    final kind = _kind;

    if (file != null && kind != null) {
      final content = _ImageContent(
              file: file,
              fullscreen: widget.fullscreen,
              onTap: widget.onTap,
              boxFit: widget.boxFit,
            );
      if (widget.fullscreen) {
        // 全屏恒可见，无需 VisibilityDetector
        return content;
      }
      // 非全屏：包 VisibilityDetector，使滚动出屏时 _visible 更新（可见性迟滞）。
      return VisibilityDetector(
        key: ValueKey('media_view_${widget.mediaId}'),
        onVisibilityChanged: _onVisibilityChanged,
        child: content,
      );
    }

    // loading 态（含 failed/miss）
    final loadingWidget = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 8),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
          style: IconButton.styleFrom(
            backgroundColor: widget.fullscreen
                ? Colors.white.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHigh,
            foregroundColor:
                widget.fullscreen ? Colors.white : theme.colorScheme.primary,
            minimumSize: const Size(32, 32),
          ),
        ),
      ],
    );

    if (widget.fullscreen) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: loadingWidget,
      );
    }

    return VisibilityDetector(
      key: ValueKey('media_view_${widget.mediaId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Container(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: loadingWidget,
      ),
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

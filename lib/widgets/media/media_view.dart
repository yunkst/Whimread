/// 媒体展示 widget — 统一渲染图片/视频
///
/// 替代旧 image_gallery_card.dart 的 _GalleryImage。区别：
/// - 只认一个 `mediaId`（不再要 imageId+taskId 双字段），通过 mediaProxyProvider
///   解析：本地命中→显示；miss→按 source 回源；pending→轮询；failed→刷新按钮。
/// - 图片走 Image.file / PhotoView（全屏缩放），视频走 video_player（首次激活，
///   原 video_player 死依赖转为真实使用）。
///
/// 轮询条件（与旧 _GalleryImage 一致）：组件可见（visibleFraction > 0）且
/// app 前台（resumed）；fullscreen 模式恒可见。loaded 后停轮询。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
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

/// 视频播放指令（[mediaVideoPlayCommand] 的返回值）。
@visibleForTesting
enum VideoPlayCommand { play, pause, none }

/// 双阈值迟滞决策（公开以便单元测试）。
///
/// 当前可见时，fraction 掉到 [kPauseThreshold] 以下才转不可见；
/// 当前不可见时，fraction 升到 [kPlayThreshold] 以上才转可见。
/// 0.1~0.5 区间保持上一态，避免在屏幕边缘反复触发 play/pause。
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

/// 决定 controller 下一步动作（公开以便单元测试）。
///
/// - shouldPlay=true 且当前未在播放 → play
/// - shouldPlay=false 且当前在播放 → pause
/// - 其余（状态已一致）→ none，避免重复调用造成抖动
///
/// 抽成纯函数是为了把"防重复 play/pause"这一关键契约从依赖真实
/// VideoPlayerController 的 widget test 中剥离，做成零依赖单测。
@visibleForTesting
VideoPlayCommand mediaVideoPlayCommand({
  required bool shouldPlay,
  required bool isPlaying,
}) {
  if (shouldPlay && !isPlaying) return VideoPlayCommand.play;
  if (!shouldPlay && isPlaying) return VideoPlayCommand.pause;
  return VideoPlayCommand.none;
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

  /// 是否允许播放视频（视口中心 + app 前台）。非视频项忽略。
  bool get _shouldPlay =>
      _appActive && (widget.fullscreen || _visible);

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
        case MediaStatus.pending:
        case MediaStatus.failed:
        case MediaStatus.miss:
          // 保持 loading 态（附刷新按钮）；pending 继续轮询，failed/miss 靠手动刷新
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
      final content = kind == MediaKind.video
          ? _VideoContent(
              file: file,
              shouldPlay: _shouldPlay,
              boxFit: widget.boxFit,
            )
          : _ImageContent(
              file: file,
              fullscreen: widget.fullscreen,
              onTap: widget.onTap,
              boxFit: widget.boxFit,
            );
      if (widget.fullscreen) {
        // 全屏恒可见，无需 VisibilityDetector
        return content;
      }
      // 非全屏：包 VisibilityDetector，使滚动出屏时 _visible 更新 → 视频离屏 pause。
      // loaded 态也必须包，否则视频加载完成后滚动出屏不会 pause，持续解码。
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

/// 视频内容：VideoPlayer 循环自动播放，无任何控制 UI（类似 gif 动图）。
/// 不响应点击，无播放/暂停指示，无进度条。
///
/// 播放控制由父级 [MediaView] 经 `shouldPlay` 下传：
/// - 可见（visibleFraction > 0.5）且 app 前台 → play
/// - 滚出视野（< 0.1）或 app 后台 → pause（不 dispose，保留纹理便于回滚丝滑）
/// initState 不主动 play，统一由 didUpdateWidget 接管，避免组件未挂上可见性
/// 回调就先解码一帧的浪费。
class _VideoContent extends StatefulWidget {
  final File file;
  final bool shouldPlay;
  final BoxFit? boxFit;
  const _VideoContent({
    required this.file,
    required this.shouldPlay,
    this.boxFit,
  });

  @override
  State<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<_VideoContent> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _VideoContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shouldPlay != widget.shouldPlay) {
      _applyPlayState();
    }
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(widget.file);
    try {
      await c.initialize();
      c.setLooping(true);
      c.setVolume(0); // 静音：动图效果
      if (mounted) {
        setState(() {
          _controller = c;
          _initialized = true;
        });
        _applyPlayState(); // 用父级当前决策，而非无脑 play
      }
    } catch (e) {
      LoggerService.instance.d(
        'VideoContent 初始化失败: $e',
        category: LogCategory.ai,
        tags: ['media_view', 'video', 'init_failed'],
      );
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 按 widget.shouldPlay 切换 play/pause。controller 未就绪时忽略
  ///（_init 完成后会再调一次）。
  void _applyPlayState() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    switch (mediaVideoPlayCommand(
      shouldPlay: widget.shouldPlay,
      isPlaying: c.value.isPlaying,
    )) {
      case VideoPlayCommand.play:
        c.play();
        break;
      case VideoPlayCommand.pause:
        c.pause();
        break;
      case VideoPlayCommand.none:
        break;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Icon(Icons.error_outline, color: Colors.red, size: 32),
      );
    }
    if (!_initialized || _controller == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final c = _controller!;
    // cover 模式：FittedBox(cover) 按视频原生尺寸裁剪填满（头像场景）
    if (widget.boxFit == BoxFit.cover) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }
}

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'logger_service.dart';

/// 高性能自动滚动控制器
///
/// 使用 SchedulerBinding.scheduleFrameCallback 实现基于帧回调的滚动，
/// 自动适应设备刷新率（60fps/90fps/120fps），性能远优于 Timer.periodic
///
/// 使用示例：
/// ```dart
/// final controller = HighPerformanceAutoScrollController(
///   scrollController: myScrollController,
/// );
///
/// // 启动滚动（速度：100 像素/秒）
/// controller.startAutoScroll(100);
///
/// // 停止滚动
/// controller.stopAutoScroll();
///
/// // 使用完毕后释放资源
/// controller.dispose();
/// ```
class HighPerformanceAutoScrollController {
  static const LogCategory _category = LogCategory.ui;
  static const List<String> _tags = ['auto-scroll'];
  /// 关联的滚动控制器
  final ScrollController scrollController;

  /// 是否已请求帧回调（用于防止重复请求）
  bool _hasScheduledFrame = false;

  /// 滚动速度（像素/秒）
  double _pixelsPerSecond;

  /// 上一帧的时间戳
  DateTime? _lastFrameTime;

  /// 滚动完成回调
  VoidCallback? _onScrollComplete;

  /// 暂停标志
  bool _isPaused = false;

  /// 构造函数
  HighPerformanceAutoScrollController({
    required this.scrollController,
  }) : _pixelsPerSecond = 0;

  /// 是否正在滚动
  bool get isScrolling => _pixelsPerSecond > 0 && !_isPaused;

  /// 是否已暂停
  bool get isPaused => _isPaused;

  /// 启动自动滚动
  ///
  /// [pixelsPerSecond] 滚动速度，单位：像素/秒
  /// [onScrollComplete] 滚动到底部时的回调（可选）
  void startAutoScroll(
    double pixelsPerSecond, {
    VoidCallback? onScrollComplete,
  }) {
    // 如果已经在滚动，先停止
    if (isScrolling) {
      LoggerService.instance.w('[startAutoScroll] 已在滚动中，先停止当前滚动', category: _category, tags: _tags);
      stopAutoScroll();
    }

    _pixelsPerSecond = pixelsPerSecond;
    _onScrollComplete = onScrollComplete;
    _lastFrameTime = DateTime.now();

    LoggerService.instance.i('[startAutoScroll] 设置完成，速度=$pixelsPerSecond px/s', category: _category, tags: _tags);
    _requestFrame();
  }

  /// 暂停自动滚动（不重置内部状态）
  void pauseAutoScroll() {
    _isPaused = true;
    LoggerService.instance.i('[pauseAutoScroll] 自动滚动已暂停', category: _category, tags: _tags);
  }

  /// 恢复自动滚动
  void resumeAutoScroll() {
    _isPaused = false;
    _lastFrameTime = DateTime.now(); // 重置时间戳避免跳跃
    _requestFrame();
    LoggerService.instance.i('[resumeAutoScroll] 自动滚动已恢复', category: _category, tags: _tags);
  }

  /// 停止自动滚动
  void stopAutoScroll() {
    LoggerService.instance.d('[HighPerformanceAutoScrollController.stopAutoScroll] 被调用', category: _category, tags: _tags);

    _pixelsPerSecond = 0;
    _hasScheduledFrame = false;
    _lastFrameTime = null;
    _onScrollComplete = null;
    _isPaused = false; // 重置暂停状态

    LoggerService.instance.i('[stopAutoScroll] 已重置所有状态', category: _category, tags: _tags);
    // 注意：Flutter 的 SchedulerBinding 不提供 cancelFrameCallback 方法
    // 我们通过 _pixelsPerSecond 和 _hasScheduledFrame 标志来控制回调是否继续执行
  }

  /// 请求下一帧回调
  void _requestFrame() {
    if (!_hasScheduledFrame) {
      _hasScheduledFrame = true;
      SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
      // 🔔 已移除：每帧打印太频繁
    }
  }

  /// 帧回调处理函数
  ///
  /// 每一帧都会被调用，计算时间差并滚动相应距离
  void _onFrame(Duration timestamp) {
    // 重置标志，允许下一次请求
    _hasScheduledFrame = false;

    // 检查暂停状态
    if (_isPaused) {
      return; // 暂停时不执行滚动，但也不重置状态
    }

    // 检查速度
    if (_pixelsPerSecond == 0) {
      return;
    }

    final now = DateTime.now();
    if (_lastFrameTime == null) {
      _lastFrameTime = now;
      _requestFrame();
      return;
    }

    // 计算时间差（秒）
    final deltaTime = now.difference(_lastFrameTime!).inMicroseconds / 1000000;
    _lastFrameTime = now;

    // 检查滚动控制器状态
    if (!scrollController.hasClients) {
      LoggerService.instance.w('[_onFrame] scrollController.hasClients == false，无法滚动', category: _category, tags: _tags);
      stopAutoScroll();
      return;
    }

    // 获取当前位置和最大位置
    final currentPosition = scrollController.offset;
    final maxPosition = scrollController.position.maxScrollExtent;

    // 计算滚动距离
    final delta = _pixelsPerSecond * deltaTime;

    // 计算新位置并限制在有效范围内
    final newPosition = (currentPosition + delta).clamp(0.0, maxPosition);

    // 判断是否到底部
    if (newPosition >= maxPosition) {
      LoggerService.instance.i('[_onFrame] 已滚动到底部，停止滚动', category: _category, tags: _tags);
      scrollController.jumpTo(newPosition);
      stopAutoScroll();
      _onScrollComplete?.call();
      return;
    }

    // 执行滚动（已移除每帧日志）
    scrollController.jumpTo(newPosition);

    // 如果还没到底部，继续请求下一帧
    _requestFrame();
  }

  /// 释放资源
  void dispose() {
    stopAutoScroll();
  }
}

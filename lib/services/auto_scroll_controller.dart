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

  /// 单帧最大推进时长（秒）。
  ///
  /// 帧回调链被长时间中断后（典型：App 退到后台再回来——引擎停帧期间
  /// 回调不执行，恢复后的第一帧墙钟时间差包含整个后台时长），若不设上
  /// 限会把这段时长一次性补滚，位置直接被顶到章节底部。钳制后恢复时
  /// 从原位置附近继续滚动。
  static const double _maxDeltaSeconds = 0.25;

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

  /// 时间源；默认系统墙钟，测试可注入固定时钟以确定性推进。
  final DateTime Function() _clock;

  /// 构造函数
  HighPerformanceAutoScrollController({
    required this.scrollController,
    DateTime Function()? clock,
  })  : _pixelsPerSecond = 0,
        _clock = clock ?? DateTime.now;

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
    _isPaused = false; // 显式启动需清除暂停态，否则暂停中的帧链不会推进
    _lastFrameTime = _clock();

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
    _lastFrameTime = _clock(); // 重置时间戳避免跳跃
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

    final now = _clock();
    if (_lastFrameTime == null) {
      _lastFrameTime = now;
      _requestFrame();
      return;
    }

    // 计算时间差（秒），钳制到 [0, _maxDeltaSeconds]：
    // 下限防御系统时钟回拨，上限防止长中断后一次性补滚（见 _maxDeltaSeconds）
    final deltaTime = (now.difference(_lastFrameTime!).inMicroseconds / 1000000)
        .clamp(0.0, _maxDeltaSeconds)
        .toDouble();
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
      // 先取出回调再停止:stopAutoScroll 会清空 _onScrollComplete,
      // 直接链式调用会让「触底回调」永远不触发(手动停止才应丢弃回调)
      final callback = _onScrollComplete;
      stopAutoScroll();
      callback?.call();
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

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/auto_scroll_controller.dart';
import '../../services/logger_service.dart';

/// 自动滚动功能 Mixin
///
/// 职责：
/// - 管理自动滚动状态（开始/停止）
/// - 处理用户触摸检测（触摸停止、松手恢复）
///
/// 使用方式：
/// ```dart
/// class _MyScreenState extends State<MyScreen> with AutoScrollMixin {
///   @override
///   void initState() {
///     super.initState();
///     initAutoScroll(scrollController: _scrollController);
///   }
///
///   // 在 UI 中使用 GestureDetector 包裹内容
///   GestureDetector(
///     onTapDown: (_) => handleTouch(),
///     child: ListView.builder(...),
///   )
/// }
/// ```
///
/// 需要子类提供的字段和方法：
/// - `ScrollController get scrollController` - 滚动控制器
/// - `double get scrollSpeed` - 滚动速度倍数（1.0-3.0）
/// - `void setState(VoidCallback fn)` - 状态更新方法
mixin AutoScrollMixin<T extends StatefulWidget> on State<T> {
  // ========== 字段 ==========

  late HighPerformanceAutoScrollController _autoScrollController;
  bool _shouldAutoScroll = false; // 是否应该恢复（区分暂停vs停止）
  Timer? _resumeTimer; // 恢复计时器

  // 常量配置
  static const Duration _resumeDelay = Duration(seconds: 1); // 恢复延迟：1秒
  static const double _baseScrollSpeed = 50.0; // 基础滚动速度（像素/秒）

  // ========== 抽象访问器（子类必须实现）==========

  /// 滚动控制器（子类提供）
  ScrollController get scrollController;

  /// 滚动速度倍数（子类提供，1.0为默认速度）
  double get scrollSpeed;

  // ========== 公开方法 ==========

  /// 初始化自动滚动控制器
  ///
  /// 必须在 initState 中调用
  void initAutoScroll({required ScrollController scrollController}) {
    _autoScrollController = HighPerformanceAutoScrollController(
      scrollController: scrollController,
    );
  }

  /// 开始自动滚动
  void startAutoScroll() {
    LoggerService.instance.d(
      'startAutoScroll 被调用',
      category: LogCategory.ui,
      tags: ['auto-scroll'],
    );

    if (_shouldAutoScroll && _autoScrollController.isScrolling) {
      return;
    }

    final pixelsPerSecond = _baseScrollSpeed * scrollSpeed;
    _autoScrollController.startAutoScroll(
      pixelsPerSecond,
      onScrollComplete: () {
        // 保持 _shouldAutoScroll 不变，以便章节切换时恢复滚动
      },
    );

    setState(() {
      _shouldAutoScroll = true;
    });
  }

  /// 暂停并设置恢复计时器（用于触摸检测）
  void handleTouch() {
    if (!_shouldAutoScroll) return;

    _pauseAndScheduleResume();
  }

  /// 暂停自动滚动并设置恢复计时器
  void _pauseAndScheduleResume() {
    _resumeTimer?.cancel();
    _autoScrollController.pauseAutoScroll();

    // 1秒后自动恢复
    _resumeTimer = Timer(_resumeDelay, () {
      if (_shouldAutoScroll) {
        _resumeAutoScroll();
      }
    });

    setState(() {}); // 触发 UI 更新以反映控制器状态变化
  }

  /// 内部恢复方法（不检查 _isAutoScrolling，避免递归）
  void _resumeAutoScroll() {
    _resumeTimer?.cancel();
    _autoScrollController.resumeAutoScroll();

    setState(() {}); // 触发 UI 更新
  }

  /// 停止自动滚动（完全停止，清除意图）
  void stopAutoScroll() {
    _resumeTimer?.cancel();
    _autoScrollController.stopAutoScroll();
    setState(() {
      _shouldAutoScroll = false;
    });
  }

  /// 切换自动滚动状态
  void toggleAutoScroll() {
    if (_shouldAutoScroll && _autoScrollController.isScrolling) {
      stopAutoScroll();
    } else {
      startAutoScroll();
    }
  }

  /// 处理滚动通知（保留以兼容现有代码，但已简化）
  ///
  /// 返回 false 表示不阻止通知继续传递
  bool handleScrollNotification(ScrollNotification notification) {
    // 不再处理 UserScrollNotification，改用 GestureDetector
    return false;
  }

  // ========== Getter 方法 ==========

  /// 是否正在自动滚动
  bool get isAutoScrolling => _autoScrollController.isScrolling;

  /// 是否已暂停（用于UI区分暂停vs停止）
  bool get isAutoScrollPaused => _autoScrollController.isPaused;

  /// 是否正在滚动（非暂停状态）
  bool get isAutoScrollActive => _autoScrollController.isScrolling;

  /// 是否应该自动滚动（意图标记）
  bool get shouldAutoScroll => _shouldAutoScroll;

  // ========== 生命周期管理 ==========

  /// 清理资源（在子类的 dispose 中调用）
  void disposeAutoScroll() {
    _resumeTimer?.cancel();
    _autoScrollController.dispose();
  }
}

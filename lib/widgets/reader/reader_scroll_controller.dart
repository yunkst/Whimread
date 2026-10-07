import 'package:flutter/material.dart';

/// 阅读器专用 ScrollController：支持同帧像素平移（顶部拼接/回收补偿）。
///
/// 顶部插入或回收章节块后，须把滚动位置等量平移才能保持视野不动。
/// 旧实现的 postFrame + jumpTo 有两个问题：补偿前的插入帧先以旧
/// offset 绘制一帧错误画面（闪烁）；jumpTo 会 beginActivity(Idle) 把
/// 进行中的惯性滚动（ballistic）掐死。
///
/// [shiftBy] 走 [ScrollPosition.correctPixels]——protected API，子类
/// 内部调用正是其设计用途（与 Viewport 处理 sliver scrollOffsetCorrection
/// 同一机制）——同帧生效、不发通知、不切换 activity，fling 无感。
class ReaderScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _ReaderScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }

  /// 同帧把滚动位置平移 [delta] 像素（正 = 向内容尾部）。
  ///
  /// 必须在触发重建的 setState 之前（或同帧）调用：本帧布局直接以
  /// 平移后的 offset 进行，不存在中间错误画面。无挂载位置时为 no-op。
  void shiftBy(double delta) {
    if (positions.isEmpty) return;
    (positions.first as _ReaderScrollPosition).shiftBy(delta);
  }
}

class _ReaderScrollPosition extends ScrollPositionWithSingleContext {
  _ReaderScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  void shiftBy(double delta) => correctPixels(pixels + delta);
}

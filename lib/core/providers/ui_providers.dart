/// Riverpod UI Providers
///
/// 此文件提供UI状态管理相关的 Providers。
///
/// **功能域**:
/// - [ToastNotifier] - Toast消息状态管理
/// - [DialogServiceProvider] - 对话框服务Provider
///
/// **架构原则**:
/// - UI层只触发事件（调用Notifier方法）
/// - Notifier处理业务逻辑和更新状态
/// - UI通过ref.listen监听状态变化并显示Toast
///
/// **使用示例**:
/// ```dart
/// // 在Widget中监听Toast
/// ref.listen(toastNotifier, (previous, next) {
///   if (next.message != null && mounted) {
///     ToastUtils.showSuccess(next.message!, context: context);
///     ref.read(toastNotifier.notifier).clear();
///   }
/// });
///
/// // 在业务逻辑中触发Toast
/// ref.read(toastNotifier.notifier).showSuccess('操作成功');
/// ```
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_providers.g.dart';

// ==================== Toast State Management ====================

/// Toast类型枚举
enum ToastType {
  /// 成功提示（绿色）
  success,

  /// 错误提示（红色）
  error,

  /// 警告提示（橙色）
  warning,

  /// 信息提示（蓝色）
  info,
}

/// Toast状态数据类
///
/// 封装Toast消息和类型，便于UI层根据类型选择显示样式
class ToastState {
  /// 消息内容
  final String? message;

  /// Toast类型
  final ToastType? type;

  /// 持续时间（可选）
  final Duration? duration;

  const ToastState({
    this.message,
    this.type,
    this.duration,
  });

  /// 创建空状态
  const ToastState.empty()
      : message = null,
        type = null,
        duration = null;

  /// 判断是否有消息
  bool get hasMessage => message != null && message!.isNotEmpty;
}

/// Toast状态管理器
///
/// **职责**:
/// - 管理Toast消息状态
/// - 提供显示各类Toast的接口
/// - 自动触发状态更新通知UI层
///
/// **架构原则**:
/// - Notifier只管理状态，不直接显示Toast
/// - UI层通过ref.listen监听状态变化并显示
/// - 显示后立即清除状态，避免重复显示
@riverpod
class ToastNotifier extends _$ToastNotifier {
  @override
  ToastState build() {
    return const ToastState.empty();
  }

  /// 显示成功提示（绿色）
  ///
  /// [message] 消息内容
  /// [duration] 持续时间（可选，默认使用ToastUtils默认值）
  void showSuccess(String message, {Duration? duration}) {
    state = ToastState(
      message: message,
      type: ToastType.success,
      duration: duration,
    );
  }

  /// 显示错误提示（红色）
  ///
  /// [message] 消息内容
  /// [duration] 持续时间（可选）
  void showError(String message, {Duration? duration}) {
    state = ToastState(
      message: message,
      type: ToastType.error,
      duration: duration,
    );
  }

  /// 显示警告提示（橙色）
  ///
  /// [message] 消息内容
  /// [duration] 持续时间（可选）
  void showWarning(String message, {Duration? duration}) {
    state = ToastState(
      message: message,
      type: ToastType.warning,
      duration: duration,
    );
  }

  /// 显示信息提示（蓝色）
  ///
  /// [message] 消息内容
  /// [duration] 持续时间（可选）
  void showInfo(String message, {Duration? duration}) {
    state = ToastState(
      message: message,
      type: ToastType.info,
      duration: duration,
    );
  }

  /// 清除Toast消息
  ///
  /// 通常在UI层显示Toast后调用，避免重复显示
  void clear() {
    state = const ToastState.empty();
  }
}

// ==================== Home Tab Switcher ====================

/// 底部导航 Tab 索引常量
///
/// 集中管理 HomePage IndexedStack 的 Tab 索引，方便跨页面引用。
class HomeTabIndex {
  const HomeTabIndex._();

  /// 书架
  static const int bookshelf = 0;

  /// 生图调试
  static const int illustration = 1;

  /// 浏览器
  static const int browser = 2;

  /// 设置
  static const int settings = 3;
}

/// 当前选中的底部导航 Tab
///
/// HomePage 监听此 Provider 切换 Tab；其他页面（如书架空状态引导）
/// 可通过 ref.read(homeTabIndexNotifierProvider.notifier).state = ... 切换 Tab。
@riverpod
class HomeTabIndexNotifier extends _$HomeTabIndexNotifier {
  @override
  int build() {
    return HomeTabIndex.bookshelf;
  }

  /// 跳转到指定 Tab
  void switchTo(int index) {
    if (state != index) {
      state = index;
    }
  }
}

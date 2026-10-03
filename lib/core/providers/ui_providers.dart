/// Riverpod UI Providers
///
/// 此文件提供UI状态管理相关的 Providers。
///
/// **功能域**:
/// - [HomeTabNotifier] - 底部导航 Tab 状态管理
///
/// **架构原则**:
/// - UI层只触发事件（调用Notifier方法）
/// - Notifier处理业务逻辑和更新状态
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../navigation/home_tab.dart';

part 'ui_providers.g.dart';

// ==================== Home Tab Switcher ====================

/// 当前选中的底部导航 Tab
///
/// 状态是 [HomeTab] 枚举而非裸 int：Tab 的顺序/文案/图标定义在枚举里，
/// 页面栈与导航栏都由它派生，任何地方不再出现魔法索引。
/// HomePage 监听此 Provider 切换 Tab；其他页面可通过
/// `ref.read(homeTabNotifierProvider.notifier).state = ...` 切换 Tab。
@riverpod
class HomeTabNotifier extends _$HomeTabNotifier {
  @override
  HomeTab build() {
    return HomeTab.bookshelf;
  }

  /// 跳转到指定 Tab
  void switchTo(HomeTab tab) {
    if (state != tab) {
      state = tab;
    }
  }
}

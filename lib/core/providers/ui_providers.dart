/// Riverpod UI Providers
///
/// 此文件提供UI状态管理相关的 Providers。
///
/// **功能域**:
/// - [HomeTabIndex] / [HomeTabIndexNotifier] - 底部导航 Tab 状态管理
///
/// **架构原则**:
/// - UI层只触发事件（调用Notifier方法）
/// - Notifier处理业务逻辑和更新状态
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_providers.g.dart';

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

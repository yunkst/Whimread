/// 底部导航各 Tab 的页面构建表
///
/// 与 [HomeTab] 枚举一一对应：枚举管身份/顺序/文案/图标，本表管页面。
/// [buildHomeTabPages] 与 [buildHomeTabDestinations] 都按
/// [HomeTab.values] 顺序迭代，页面栈与导航栏顺序天然一致。
library;

import 'package:flutter/material.dart';

import '../core/navigation/home_tab.dart';
import 'bookshelf_screen.dart';
import 'settings_screen.dart';
import 'text_game/text_game_home_screen.dart';
import 'webview_browser_screen.dart';

/// Tab 页面构建器
///
/// [HomeTabPageBuilder.active] = 该 Tab 当前是否可见。IndexedStack 会
/// 保留所有 Tab 的 Element/State，浏览器等页面需要它区分「在前台」与
/// 「被切到后台」（如仅在可见时拦截系统返回手势）。
typedef HomeTabPageBuilder = Widget Function({required bool active});

/// Tab → 页面构建表（键集合必须覆盖 [HomeTab.values]，由测试守护）
final Map<HomeTab, HomeTabPageBuilder> homeTabPages =
    <HomeTab, HomeTabPageBuilder>{
  HomeTab.bookshelf: ({required bool active}) => const BookshelfScreen(),
  HomeTab.textGame: ({required bool active}) => const TextGameHomeScreen(),
  HomeTab.browser: ({required bool active}) =>
      WebViewBrowserScreen(active: active),
  HomeTab.settings: ({required bool active}) => const SettingsScreen(),
};

/// 按枚举顺序生成 IndexedStack 的 children
///
/// 仅 [current] 对应的页面拿到 `active: true`。
List<Widget> buildHomeTabPages({required HomeTab current}) => <Widget>[
      for (final tab in HomeTab.values) homeTabPages[tab]!(active: tab == current),
    ];

/// 按枚举顺序生成 NavigationBar 的 destinations
List<NavigationDestination> buildHomeTabDestinations() =>
    <NavigationDestination>[
      for (final tab in HomeTab.values)
        NavigationDestination(icon: Icon(tab.icon), label: tab.label),
    ];

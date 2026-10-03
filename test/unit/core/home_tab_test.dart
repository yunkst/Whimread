/// 底部导航 Tab 定义回归测试
///
/// 历史事故：v3.2.0-preview.9/10 中 `NavigationBar.destinations` 与
/// `IndexedStack.children` 是两份手工维护的位置列表，插入位置不一致
/// 导致「点『文字游戏』显示浏览器页」。修复后二者都从 [HomeTab.values]
/// 派生，本测试锁死三道防线：
/// 1. 枚举声明顺序 = 展示顺序（书架 → 文字游戏 → 浏览器 → 设置）；
/// 2. 页面构建表覆盖全部 Tab（漏一个运行时即空指针）；
/// 3. 页面栈顺序与导航栏顺序一致，且只有当前页 active。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/navigation/home_tab.dart';
import 'package:novel_app/screens/bookshelf_screen.dart';
import 'package:novel_app/screens/home_tab_pages.dart';
import 'package:novel_app/screens/settings_screen.dart';
import 'package:novel_app/screens/text_game/text_game_home_screen.dart';
import 'package:novel_app/screens/webview_browser_screen.dart';

void main() {
  group('HomeTab 枚举（单一真相源）', () {
    test('声明顺序 = 展示顺序：书架 → 文字游戏 → 浏览器 → 设置', () {
      expect(
        HomeTab.values.map((t) => t.label).toList(),
        ['书架', '文字游戏', '浏览器', '设置'],
      );
      expect(
        HomeTab.values.map((t) => t.icon).toList(),
        [Icons.book, Icons.sports_esports, Icons.public, Icons.settings],
      );
    });

    test('每个 Tab 的文案与图标非空', () {
      for (final tab in HomeTab.values) {
        expect(tab.label, isNotEmpty, reason: '${tab.name} 缺少文案');
      }
    });
  });

  group('homeTabPages 页面构建表', () {
    test('键集合覆盖全部 Tab（漏一个会在切 Tab 时空指针）', () {
      expect(homeTabPages.keys.toSet(), HomeTab.values.toSet());
    });

    test('各 Tab 构建出预期页面类型', () {
      expect(homeTabPages[HomeTab.bookshelf]!(active: true),
          isA<BookshelfScreen>());
      expect(homeTabPages[HomeTab.textGame]!(active: true),
          isA<TextGameHomeScreen>());
      expect(
          homeTabPages[HomeTab.browser]!(active: true), isA<WebViewBrowserScreen>());
      expect(homeTabPages[HomeTab.settings]!(active: true),
          isA<SettingsScreen>());
    });

    test('browser builder 把 active 透传给 WebViewBrowserScreen', () {
      final visible =
          homeTabPages[HomeTab.browser]!(active: true) as WebViewBrowserScreen;
      final offstage =
          homeTabPages[HomeTab.browser]!(active: false) as WebViewBrowserScreen;
      expect(visible.active, isTrue);
      expect(offstage.active, isFalse);
    });
  });

  group('IndexedStack 与 NavigationBar 的派生', () {
    test('页面栈顺序与枚举一致，且只有当前页 active', () {
      final pages = buildHomeTabPages(current: HomeTab.textGame);
      expect(
        pages.map((w) => w.runtimeType).toList(),
        [BookshelfScreen, TextGameHomeScreen, WebViewBrowserScreen, SettingsScreen],
      );
      // 浏览器在枚举中排第 3（index 2），当前选中的是文字游戏 →
      // 浏览器页必须拿到 active = false（曾因错位导致浏览器返回手势
      // 在错误页生效）
      expect(
          (pages[HomeTab.browser.index] as WebViewBrowserScreen).active, isFalse);
      final browserVisible =
          buildHomeTabPages(current: HomeTab.browser) as List;
      expect(
          (browserVisible[HomeTab.browser.index] as WebViewBrowserScreen)
              .active,
          isTrue);
    });

    test('导航栏目的地顺序与枚举文案一致', () {
      final destinations = buildHomeTabDestinations();
      expect(
        destinations.map((d) => d.label).toList(),
        HomeTab.values.map((t) => t.label).toList(),
      );
      expect(destinations.length, HomeTab.values.length);
    });

    test('页面栈与导航栏由同一枚举派生：两端索引一一对应', () {
      final pages = buildHomeTabPages(current: HomeTab.bookshelf);
      final destinations = buildHomeTabDestinations();
      for (var i = 0; i < HomeTab.values.length; i++) {
        // NavigationBar 第 i 项的文案必须等于 HomeTab.values[i]，
        // IndexedStack 第 i 项必须是 HomeTab.values[i] 的页面——
        // 二者同一来源，此处校验派生 helper 没有各自维护顺序。
        expect(destinations[i].label, HomeTab.values[i].label);
        expect(
          pages[i].runtimeType.toString(),
          homeTabPages[HomeTab.values[i]]!(active: false).runtimeType.toString(),
        );
      }
    });
  });
}

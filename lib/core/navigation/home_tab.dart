/// 底部导航 Tab 定义（单一真相源）
///
/// Tab 的**身份、文案、图标与顺序**全部定义在 [HomeTab] 枚举里；
/// `NavigationBar` 的目的地与 `IndexedStack` 的页面栈都按
/// [HomeTab.values] 顺序生成（页面构建器见 `screens/home_tab_pages.dart`），
/// 从结构上杜绝「两份手工维护的列表对不上位」——历史上因此出现过
/// 点「文字游戏」显示浏览器页的错位（v3.2.0-preview.9/10）。
///
/// 新增/调整 Tab：直接改枚举声明顺序即可，导航栏与页面栈同步变化；
/// 页面侧记得在 `homeTabPages` 表补对应 builder（覆盖完整性由测试守护）。
library;

import 'package:flutter/material.dart';

/// 应用底部导航 Tab（声明顺序 = 展示顺序 = IndexedStack 顺序）
enum HomeTab {
  /// 书架
  bookshelf('书架', Icons.book),

  /// 文字游戏（互动小说，专属游玩页 + 管理页）
  textGame('文字游戏', Icons.sports_esports),

  /// 内置浏览器（站点脚本解析 / 抓取）
  browser('浏览器', Icons.public),

  /// 设置
  settings('设置', Icons.settings);

  const HomeTab(this.label, this.icon);

  /// 导航栏文案
  final String label;

  /// 导航栏图标
  final IconData icon;
}

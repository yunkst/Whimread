/// 复现 + 修复验证：log_viewer_screen 级别过滤菜单。
///
/// 根因（已验证）：Flutter 的 PopupMenuItem 文档明确 ——「If itemBuilder
/// returns an item with a null value, the item will not be selectable.」
/// 原代码「全部级别」用 value: null，被 framework 吞掉点击，onSelected 不触发，
/// 表现为「点了没反应、UI 仍展示原级别」。
///
/// 修复：用 sentinel Object 替代 null 作为"全部"标记，绕过 framework
/// 对 null value 的特殊处理。
///
/// 本文件用最小复现对比两种实现：
///   1. 坏实现：value: null 的 PopupMenuItem → 点击被吞
///   2. 好实现：value: sentinel Object 的 PopupMenuItem → 点击触发 onSelected
///
/// 运行:
///   cd novel_app
///   flutter test test/bug/log_viewer_all_level_button_repro_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PopupMenuButton 行为验证', () {
    testWidgets('坏实现：value:null 的 item 点击不触发 onSelected', (tester) async {
      int callCount = 0;
      String? lastValue = '__sentinel__';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PopupMenuButton<String?>(
              icon: const Icon(Icons.filter_list),
              tooltip: '按级别过滤',
              onSelected: (v) {
                callCount++;
                lastValue = v;
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String?>(value: null, child: Text('全部级别')),
                const PopupMenuDivider(),
                const PopupMenuItem<String?>(value: 'error', child: Text('Error')),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('按级别过滤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部级别'));
      await tester.pumpAndSettle();

      // 关键事实：onSelected 没被调用（framework 行为）
      expect(callCount, 0,
          reason: 'Flutter PopupMenuButton 对 value:null 故意不触发 onSelected');
      expect(lastValue, '__sentinel__');

      // 对照：普通 item 正常
      await tester.tap(find.byTooltip('按级别过滤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Error'));
      await tester.pumpAndSettle();
      expect(callCount, 1);
      expect(lastValue, 'error');
    });

    testWidgets('好实现：sentinel Object 替代 null 后「全部」可点击', (tester) async {
      // sentinel：私有 const Object，identity 比较
      const allLevelsSentinel = Object();
      int callCount = 0;
      Object? lastValue = '__sentinel__';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PopupMenuButton<Object?>(
              icon: const Icon(Icons.filter_list),
              tooltip: '按级别过滤',
              onSelected: (v) {
                callCount++;
                lastValue = v;
              },
              itemBuilder: (context) => [
                const PopupMenuItem<Object?>(
                  value: allLevelsSentinel,
                  child: Text('全部级别'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<Object?>(value: 'error', child: Text('Error')),
                const PopupMenuItem<Object?>(value: 'warning', child: Text('Warning')),
              ],
            ),
          ),
        ),
      );

      // 点「全部级别」
      await tester.tap(find.byTooltip('按级别过滤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部级别'));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(identical(lastValue, allLevelsSentinel), isTrue,
          reason: '应收到 sentinel 自身（用 identical 判别，非值相等）');

      // 点 Error
      await tester.tap(find.byTooltip('按级别过滤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Error'));
      await tester.pumpAndSettle();
      expect(callCount, 2);
      expect(lastValue, 'error');

      // 点 Warning
      await tester.tap(find.byTooltip('按级别过滤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warning'));
      await tester.pumpAndSettle();
      expect(callCount, 3);
      expect(lastValue, 'warning');
    });
  });
}

/// 回归测试：log_viewer_screen 级别/分类过滤菜单的"全部"项必须能点。
///
/// 根因：Flutter 的 PopupMenuItem 对 value:null 故意跳过点击
/// （"If itemBuilder returns an item with a null value, the item will not be
/// selectable."）。原代码「全部级别」「全部分类」用 value:null，被 framework
/// 吞掉点击，onSelected 不触发，UI 仍展示原过滤器——bug 表现。
///
/// 修复：见 `lib/screens/log_viewer_screen.dart` —— 用文件级 const Object()
/// 作 sentinel，onSelected 里用 identical 判别还原成 nullable。
///
/// 本文件对真实 LogViewerScreen 做端到端回归,验证 sentinel 方案在 app 里成立。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/screens/log_viewer_filter_menu_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/screens/log_viewer_screen.dart';
import 'package:novel_app/services/logger_service.dart';

/// ThemeNotifier.build() 走 LoggerService 触发 1s 持久化定时器,
/// widget test 结束时必须显式 cancel,否则 _verifyInvariants 报 timersPending。
Future<void> _resetLogger() async => LoggerService.resetForTesting();

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(_resetLogger);

  testWidgets('点「全部级别」能清掉当前级别过滤', (tester) async {
    final logger = LoggerService.instance;
    logger.i('info-msg-A');
    logger.e('error-msg-B', category: LogCategory.network);

    await tester.pumpWidget(_wrap(const LogViewerScreen()));
    await tester.pumpAndSettle();

    // 1) 默认看到两条
    expect(find.text('info-msg-A'), findsOneWidget);
    expect(find.text('error-msg-B'), findsOneWidget);

    // 2) 点级别菜单 → 选 ERROR,只剩 error 那条
    await tester.tap(find.byTooltip('按级别过滤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ERROR'));
    await tester.pumpAndSettle();

    expect(find.text('info-msg-A'), findsNothing);
    expect(find.text('error-msg-B'), findsOneWidget);

    // 3) 再开菜单 → 点「全部级别」 —— 修复点
    await tester.tap(find.byTooltip('按级别过滤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部级别'));
    await tester.pumpAndSettle();

    expect(find.text('info-msg-A'), findsOneWidget,
        reason: '点「全部级别」后应清掉级别过滤,看到全部日志');
    expect(find.text('error-msg-B'), findsOneWidget);
  });

  testWidgets('点「全部分类」能清掉当前分类过滤', (tester) async {
    final logger = LoggerService.instance;
    logger.i('general-msg-uniq', category: LogCategory.general);
    logger.i('db-msg-uniq', category: LogCategory.database);

    await tester.pumpWidget(_wrap(const LogViewerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('general-msg-uniq'), findsOneWidget);
    expect(find.text('db-msg-uniq'), findsOneWidget);

    // 选「数据库」—— 用 byTooltip 限定到菜单项,避免和日志行内的 chip 冲突
    await tester.tap(find.byTooltip('按分类过滤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数据库').last);
    await tester.pumpAndSettle();

    expect(find.text('general-msg-uniq'), findsNothing);
    expect(find.text('db-msg-uniq'), findsOneWidget);

    // 点「全部分类」
    await tester.tap(find.byTooltip('按分类过滤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部分类'));
    await tester.pumpAndSettle();

    expect(find.text('general-msg-uniq'), findsOneWidget,
        reason: '点「全部分类」后应清掉分类过滤,看到全部日志');
    expect(find.text('db-msg-uniq'), findsOneWidget);
  });

  testWidgets('对照:点具体级别项能切换过滤', (tester) async {
    final logger = LoggerService.instance;
    logger.w('warn-only-uniq');

    await tester.pumpWidget(_wrap(const LogViewerScreen()));
    await tester.pumpAndSettle();
    expect(find.text('warn-only-uniq'), findsOneWidget);

    await tester.tap(find.byTooltip('按级别过滤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WARN'));
    await tester.pumpAndSettle();

    expect(find.text('warn-only-uniq'), findsOneWidget,
        reason: '点 WARN 后,只有 WARN 级别应留下来');

    // 再点 DEBUG,这条 warn 应被过滤掉
    await tester.tap(find.byTooltip('按级别过滤'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DEBUG'));
    await tester.pumpAndSettle();

    expect(find.text('warn-only-uniq'), findsNothing,
        reason: '点 DEBUG 后,warn 不应被显示');
  });
}

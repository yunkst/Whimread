import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_app/screens/log_viewer_screen.dart';
import 'package:novel_app/services/logger_service.dart';

/// LogViewerScreen 筛选崩溃复现测试
///
/// 驱动"打开页面 + 点击级别筛选"两条路径，定位闪退根因。
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // mock Fluttertoast 插件 channel，避免复制成功后的 toast 抛
    // MissingPluginException
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('Fluttertoast'),
      (MethodCall call) async => true,
    );
    SharedPreferences.setMockInitialValues({});
    LoggerService.resetForTesting();
    await LoggerService.instance.init();
  });

  tearDown(() {
    LoggerService.resetForTesting();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LogViewerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // 推进 LoggerService 写日志触发的 1s 持久化兜底 timer，
    // 避免 _verifyInvariants 的 !timersPending 断言（仅测试环境产物）。
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('打开页面不崩溃且显示全部日志', (tester) async {
    LoggerService.instance.i('info msg');
    LoggerService.instance.e('error msg');
    await pumpPage(tester);

    expect(find.text('info msg'), findsOneWidget);
    expect(find.text('error msg'), findsOneWidget);
  });

  testWidgets('点击级别筛选 ERROR 只显示错误日志', (tester) async {
    LoggerService.instance.i('info msg');
    LoggerService.instance.e('error msg');
    await pumpPage(tester);

    await tester.tap(find.byTooltip('按级别过滤'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ERROR').last);
    await tester.pumpAndSettle();

    expect(find.text('error msg'), findsOneWidget);
    expect(find.text('info msg'), findsNothing);
  });

  testWidgets('点击分类筛选只显示对应分类', (tester) async {
    LoggerService.instance.i('db op', category: LogCategory.database);
    LoggerService.instance.i('net op', category: LogCategory.network);
    await pumpPage(tester);

    await tester.tap(find.byTooltip('按分类过滤'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('数据库').last);
    await tester.pumpAndSettle();

    expect(find.text('db op'), findsOneWidget);
    expect(find.text('net op'), findsNothing);
  });

  // ===== 复制全部信息：纯单元测试（确定性覆盖格式化逻辑） =====
  //
  // 说明：未对"点击日志条目弹详情对话框 + 复制"做 widget 测试——
  // SelectableText 在 widget test 中会阻止帧收敛（pumpAndSettle 超时）。
  // 复制的核心逻辑（字段格式化）由此处单元测试确定性覆盖。

  test('formatLogForCopy 包含时间/级别/分类/标签/消息/堆栈全部字段', () {
    final entry = LogEntry(
      timestamp: DateTime(2026, 7, 17, 10, 30, 5),
      level: LogLevel.error,
      message: '致命错误',
      stackTrace: '#0  foo (file:1)',
      category: LogCategory.network,
      tags: ['api', 'retry'],
    );

    final text = LoggerService.formatLogForCopy(entry);

    expect(text, contains('时间: 2026-07-17 10:30:05'));
    expect(text, contains('级别: ERROR'));
    expect(text, contains('分类: 网络'));
    expect(text, contains('标签: api, retry'));
    expect(text, contains('消息: 致命错误'));
    expect(text, contains('堆栈:'));
    expect(text, contains('#0  foo (file:1)'));
  });

  test('formatLogForCopy 无标签无堆栈时省略对应行', () {
    final entry = LogEntry(
      timestamp: DateTime(2026, 1, 1),
      level: LogLevel.info,
      message: 'hi',
    );

    final text = LoggerService.formatLogForCopy(entry);

    expect(text, isNot(contains('标签')));
    expect(text, isNot(contains('堆栈')));
    expect(text, contains('消息: hi'));
  });
}

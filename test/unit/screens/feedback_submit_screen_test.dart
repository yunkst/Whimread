/// FeedbackSubmitScreen widget 测试。
///
/// 验证:
/// - 表单校验(标题/描述必填,空提交显示错误)
/// - 类别切换(SegmentedButton)
/// - 附带日志开关 + 副标题中的日志计数
/// - 提交成功 → fake service 收到正确参数 → toast + pop
/// - 提交失败 → inline 错误,表单内容保留
///
/// 技巧(沿用 settings_feedback_entry_test):
/// - SharedPreferences.setMockInitialValues 穿透 PreferencesService
/// - LoggerService.resetForTesting() 收尾,避免 timersPending
/// - feedback service 走构造器注入 fake,不触网
/// - 视口撑高,让表单底部按钮在初次 build 即可见
///
/// 运行:
///   flutter test test/unit/screens/feedback_submit_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/core/providers/theme_provider.dart';
import 'package:novel_app/screens/feedback_submit_screen.dart';
import 'package:novel_app/services/feedback_service.dart';
import 'package:novel_app/services/logger_service.dart';

/// 记录型 fake:拦截 submit,可配置成功/失败。
class _FakeFeedbackService extends FeedbackService {
  _FakeFeedbackService({this.result, this.error}) : super.forTest();

  final FeedbackSubmitResult? result;
  final FeedbackSubmitException? error;

  int submitCalls = 0;
  Map<String, dynamic>? lastArgs;

  @override
  Future<FeedbackSubmitResult> submit({
    required String title,
    required String description,
    FeedbackCategory category = FeedbackCategory.bug,
    String? steps,
    String? contact,
    bool includeLogs = false,
    bool includeLlmLogs = false,
    FeedbackKind kind = FeedbackKind.userReport,
  }) async {
    submitCalls++;
    lastArgs = {
      'title': title,
      'description': description,
      'category': category,
      'steps': steps,
      'contact': contact,
      'includeLogs': includeLogs,
      'includeLlmLogs': includeLlmLogs,
      'kind': kind,
    };
    if (error != null) throw error!;
    return result ??
        const FeedbackSubmitResult(reportId: 42, logCount: 0);
  }
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: const ThemeState(themeMode: AppThemeMode.light).getLightTheme(),
      home: child,
    ),
  );
}

/// 把测试视口撑高,让表单底部按钮在初次 build 即可见(避免每个测试都 scroll)。
void _expandViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await tester.enterText(
      find.widgetWithText(TextFormField, '标题'), '标题内容');
  await tester.enterText(
      find.widgetWithText(TextFormField, '问题描述'), '描述内容');
}

Future<void> _resetLogger() async => LoggerService.resetForTesting();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LoggerService.resetForTesting();
  });

  testWidgets('空表单提交 → 显示校验错误,不调用 submit', (tester) async {
    final fake = _FakeFeedbackService();
    _expandViewport(tester);
    await tester.pumpWidget(_wrap(FeedbackSubmitScreen(service: fake)));

    await tester.tap(find.text('提交反馈'));
    await tester.pump();

    expect(find.text('标题不能为空'), findsOneWidget);
    expect(find.text('描述不能为空'), findsOneWidget);
    expect(fake.submitCalls, 0);
    await _resetLogger();
  });

  testWidgets('填写必填项提交成功 → fake 收到参数 → pop 回上一页', (tester) async {
    final fake = _FakeFeedbackService();
    _expandViewport(tester);
    // 挂一个带导航入口的宿主页,push FeedbackSubmitScreen 验证 pop 行为
    await tester.pumpWidget(_wrap(
      MaterialApp(
        theme:
            const ThemeState(themeMode: AppThemeMode.light).getLightTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FeedbackSubmitScreen(service: fake),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _fillRequiredFields(tester);

    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(fake.submitCalls, 1);
    expect(fake.lastArgs!['title'], '标题内容');
    expect(fake.lastArgs!['description'], '描述内容');
    expect(fake.lastArgs!['kind'], FeedbackKind.userReport);
    expect(fake.lastArgs!['includeLogs'], false);
    // pop 回设置页
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(FeedbackSubmitScreen), findsNothing);
    await _resetLogger();
  });

  testWidgets('切换类别 → 提交时带上对应 category', (tester) async {
    final fake = _FakeFeedbackService();
    _expandViewport(tester);
    await tester.pumpWidget(_wrap(
      MaterialApp(
        theme:
            const ThemeState(themeMode: AppThemeMode.light).getLightTheme(),
        home: FeedbackSubmitScreen(service: fake),
      ),
    ));
    await _fillRequiredFields(tester);

    await tester.tap(find.text('功能建议'));
    await tester.pump();
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(fake.lastArgs!['category'], FeedbackCategory.feature);
    await _resetLogger();
  });

  testWidgets('附带日志开关打开 → 副标题显示计数,提交 includeLogs=true',
      (tester) async {
    final fake = _FakeFeedbackService();
    _expandViewport(tester);
    await tester.pumpWidget(_wrap(
      MaterialApp(
        theme:
            const ThemeState(themeMode: AppThemeMode.light).getLightTheme(),
        home: FeedbackSubmitScreen(service: fake),
      ),
    ));
    await _fillRequiredFields(tester);

    LoggerService.instance.i('log-entry-1');

    await tester.tap(find.text('一并提交近期日志（帮助定位问题）'));
    await tester.pump();

    expect(find.textContaining('将附带最近 1 条'), findsOneWidget);

    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(fake.lastArgs!['includeLogs'], true);
    await _resetLogger();
  });

  testWidgets('提交失败(服务端错误) → inline 红字,表单内容保留', (tester) async {
    final fake = _FakeFeedbackService(
      error: const FeedbackSubmitException('RATE_LIMITED', '提交过于频繁'),
    );
    _expandViewport(tester);
    await tester.pumpWidget(_wrap(
      MaterialApp(
        theme:
            const ThemeState(themeMode: AppThemeMode.light).getLightTheme(),
        home: FeedbackSubmitScreen(service: fake),
      ),
    ));
    await _fillRequiredFields(tester);

    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(find.text('提交过于频繁'), findsOneWidget);
    // 表单内容未丢(输入值仍在 controller)
    final titleField =
        tester.widget<TextFormField>(find.widgetWithText(TextFormField, '标题'));
    expect(titleField.controller!.text, '标题内容');
    expect(find.byType(FeedbackSubmitScreen), findsOneWidget); // 未 pop
    await _resetLogger();
  });
}
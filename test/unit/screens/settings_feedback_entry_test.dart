/// 设置页「问题反馈」入口 widget 测试。
///
/// 验证:
/// - 「关于」组末尾出现「问题反馈」ListTile
/// - trailing 携带 open_in_new 外链图标
/// - 点击 onTap 不抛异常（url_launcher 在测试环境走失败路径，不校验具体 URL）
///
/// 注意:
/// - SettingsScreen 用 ListView(懒加载),关于组在默认视口外不会 build,
///   故先 scrollUntilVisible 滚到「问题反馈」可见再断言。
/// - ThemeNotifier.build() 走 LoggerService 触发 1s 持久化定时器,
///   必须在 test body 结束前 cancel,否则 _verifyInvariants 报 timersPending。
///   用 addTearDown(resetForTesting) 在 invariant check 前清理。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/screens/settings_feedback_entry_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/core/providers/service_providers.dart';
import 'package:novel_app/core/providers/theme_provider.dart';
import 'package:novel_app/screens/settings_screen.dart';
import 'package:novel_app/services/backup_service.dart';
import 'package:novel_app/services/logger_service.dart';

/// mock 掉 PackageInfo 的 platform channel,避免测试环境 MissingPluginException。
/// SettingsScreen.initState 会调 PackageInfo.fromPlatform(),不 mock 会抛错。
void _mockPackageInfoChannel() {
  const channel = MethodChannel('plugins.flutter.io/package_info_plus');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getAll') {
      return <String, dynamic>{
        'appName': 'novel_app',
        'packageName': 'com.example.novel_app',
        'version': '2.0.2-test',
        'buildNumber': '999',
        'buildSignature': '',
        'installerStore': null,
      };
    }
    return null;
  });
}

/// 测试用 BackupService stub,getLastBackupTimeText 返回空字符串,跳过文件 IO。
///
/// SettingsScreen._loadLastBackupTime() 会 ref.read(backupServiceProvider)
/// .getLastBackupTimeText(); 不 stub 会真实读路径抛异常。
class _FakeBackupService implements BackupService {
  @override
  Future<String> getLastBackupTimeText() async => '';

  // 其余方法测试不关心,noSuchMethod 兜底。
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) {
  // ThemeNotifier.build() 走 PreferencesService.instance 单例读 'theme_mode';
  // setUp 里的 setMockInitialValues({}) 能穿透到它,故无需 override themeNotifierProvider。
  return ProviderScope(
    overrides: [
      backupServiceProvider.overrideWithValue(_FakeBackupService()),
    ],
    child: MaterialApp(
      // 用 ThemeState.light 的主题数据,它已含 AppColors.light extension,
      // 保证 SettingsScreen 内 context.appColors.neutral 命中真实扩展。
      theme: const ThemeState(themeMode: AppThemeMode.light).getLightTheme(),
      home: child,
    ),
  );
}

/// ThemeNotifier.build() 会经 LoggerService 创建 1s 持久化定时器,
/// 测试结束时必须显式 cancel,否则 _verifyInvariants 报 timersPending。
/// addTearDown 时机不可靠,直接在 body 末尾 widget dispose 前调。
Future<void> _resetLogger() async => LoggerService.resetForTesting();

void main() {
  setUpAll(_mockPackageInfoChannel);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('「关于」组出现「问题反馈」条目', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    // SettingsScreen 是 ListView,关于组在默认视口外懒加载未 build,
    // 需滚动到「问题反馈」可见。
    await tester.scrollUntilVisible(
      find.text('问题反馈'),
      200,
    );

    expect(find.text('问题反馈'), findsOneWidget);
    await _resetLogger();
  });

  testWidgets('「问题反馈」条目 trailing 是 open_in_new 外链图标',
      (tester) async {
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('问题反馈'),
      200,
    );

    // 找到 ListTile 后检查 trailing
    final tile = find.widgetWithText(ListTile, '问题反馈');
    expect(tile, findsOneWidget);
    final listTile = tester.widget<ListTile>(tile);
    expect(listTile.trailing, isA<Icon>());
    expect((listTile.trailing! as Icon).icon, Icons.open_in_new);
    await _resetLogger();
  });

  testWidgets('点击「问题反馈」条目 onTap 不抛异常', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('问题反馈'),
      200,
    );

    await tester.tap(find.text('问题反馈'));
    await tester.pump(); // 不调用 pumpAndSettle,launchUrl 在测试环境异步等待不会 settle

    // 无异常即通过(launchUrl 抛 PlatformException 被 try/catch 吞掉)
    expect(tester.takeException(), isNull);
    await _resetLogger();
  });
}

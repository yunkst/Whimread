import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/startup_splash.dart';

/// AppStartupSplash 品牌开屏层测试
///
/// 测试目标：
/// 1. 渲染品牌文案与标记，背景为启动链路统一底色
/// 2. 呼吸动画无限循环下多帧推进不抛异常（pumpAndSettle 会永不结束，
///    需用固定帧推进）
void main() {
  group('AppStartupSplash 品牌开屏层', () {
    testWidgets('渲染品牌文案与标记，背景为统一启动色', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppStartupSplash()));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('随心阅读'), findsOneWidget);
      expect(find.text('WHIMREAD'), findsOneWidget);
      expect(find.byIcon(Icons.auto_stories), findsOneWidget);

      final coloredBox = tester.widget<ColoredBox>(
        find.byType(ColoredBox),
      );
      expect(coloredBox.color, kStartupSplashBackground);
    });

    testWidgets('呼吸动画多帧推进不抛异常', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppStartupSplash()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
    });
  });
}

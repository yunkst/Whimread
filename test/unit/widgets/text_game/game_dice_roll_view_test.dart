/// GameDiceRollView 命运骰子卡测试
///
/// 覆盖：静态落定态渲染（选中高亮 + 百分比）/ 揭晓扫动动画播完回调 /
/// 判定中轮转态（不阻塞测试框架）/ 失败与中断降级。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/screens/text_game/game_transcript_projector.dart';
import 'package:novel_app/widgets/text_game/game_segment_views.dart';

GameDiceRoll _segment({
  List<GameRollBranch> branches = const [
    GameRollBranch(label: '闯关成功', weight: 70, percent: '70%'),
    GameRollBranch(label: '闯关失败', weight: 30, percent: '30%'),
  ],
  String reason = '主角强闯山门禁制',
  String? selectedLabel = '闯关失败',
  String? error,
  bool toolCompleted = true,
  bool live = false,
}) =>
    GameDiceRoll(
      toolCallId: 'tcR',
      reason: reason,
      branches: branches,
      selectedLabel: selectedLabel,
      error: error,
      toolCompleted: toolCompleted,
      live: live,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('静态落定态（animate=false，历史/回放）', () {
    testWidgets('渲染标题/缘由/分支/百分比/状态词', (tester) async {
      await tester.pumpWidget(_host(GameDiceRollView(segment: _segment())));
      await tester.pumpAndSettle();

      expect(find.text('概率判定'), findsOneWidget);
      expect(find.text('主角强闯山门禁制'), findsOneWidget);
      expect(find.text('闯关成功'), findsOneWidget);
      expect(find.text('闯关失败'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('命运落定'), findsOneWidget);
    });

    testWidgets('失败降级：显示错误信息与失败状态词', (tester) async {
      await tester.pumpWidget(_host(
        GameDiceRollView(
          segment: _segment(error: 'weight 必须是正数'),
          animate: true, // 失败也不应起动画
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('判定失败'), findsOneWidget);
      expect(find.text('weight 必须是正数'), findsOneWidget);
    });

    testWidgets('中断降级（定稿链里未完成）：静态展示不轮转', (tester) async {
      await tester.pumpWidget(_host(
        GameDiceRollView(
          segment: _segment(
            selectedLabel: null,
            toolCompleted: false,
            live: false,
          ),
        ),
      ));
      // live=false 不应有循环动画，pumpAndSettle 必须能结束
      await tester.pumpAndSettle();

      expect(find.text('判定未完成'), findsOneWidget);
    });
  });

  group('揭晓扫动（animate=true，首展）', () {
    testWidgets('动画播完 → 落定态 + onAnimated 恰好回调一次', (tester) async {
      var settledCount = 0;
      await tester.pumpWidget(_host(
        GameDiceRollView(
          segment: _segment(),
          animate: true,
          onAnimated: () => settledCount++,
        ),
      ));
      // 扫动中：状态词为落定中
      expect(find.text('命运落定中…'), findsOneWidget);

      await tester.pumpAndSettle(
          const Duration(milliseconds: 100)); // 1.8s 扫动播完
      expect(find.text('命运落定'), findsOneWidget);
      expect(find.text('闯关失败'), findsOneWidget);
      expect(settledCount, 1, reason: 'onAnimated 播完只回调一次');
    });

    testWidgets('onAnimated 后页面置 animate=false → 直接静态不重播', (tester) async {
      await tester.pumpWidget(_host(
        GameDiceRollView(
          segment: _segment(),
          animate: true,
          onAnimated: () {},
        ),
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('命运落定'), findsOneWidget);

      // 模拟页面重建（滚动回来）：animate=false → 无动画直接静态
      await tester.pumpWidget(_host(
        GameDiceRollView(segment: _segment(), animate: false),
      ));
      await tester.pump();
      expect(find.text('命运落定'), findsOneWidget);
    });
  });

  group('判定中轮转（live=true，循环动画）', () {
    testWidgets('渲染判定中状态与分支；循环动画持续推进不落定', (tester) async {
      await tester.pumpWidget(_host(
        GameDiceRollView(
          segment: _segment(
            selectedLabel: null,
            toolCompleted: false,
            live: true,
          ),
        ),
      ));
      expect(find.text('概率判定中'), findsOneWidget);
      expect(find.text('闯关成功'), findsOneWidget);
      expect(find.text('闯关失败'), findsOneWidget);

      // 循环动画期间状态词不变化为落定
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('命运落定'), findsNothing);
      expect(find.text('概率判定中'), findsOneWidget);
    });
  });
}

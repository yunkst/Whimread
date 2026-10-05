/// 剧情流入场动画测试（选项错峰入场 / 打字机光标 / 输入气泡 / 插图登场）
///
/// 核心纪律：**动画只为本次到访新增的内容播一次**，历史与页面重入一律
/// 静态（animate=false）。这些用例同时兜住"重播"回归。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/screens/text_game/game_transcript_projector.dart';
import 'package:novel_app/widgets/text_game/game_segment_views.dart';

GameChoices _choices({bool active = true}) => GameChoices(
      choices: const [
        GameChoice(label: '拔剑相向'),
        GameChoice(label: '转身离开', hint: '风险低'),
      ],
      active: active,
      toolCallId: 'tcC1',
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('选项组错峰入场', () {
    testWidgets('animate=true：按钮透明度随时间错峰上升，播完回调一次',
        (tester) async {
      var settled = 0;
      await tester.pumpWidget(_host(
        GameChoicesView(
          choices: _choices(),
          onSelected: (_) {},
          animate: true,
          onAnimated: () => settled++,
        ),
      ));

      // 首帧：第一项尚未完全出现（错峰起点）
      final firstOpacity =
          tester.widget<FadeTransition>(find.byType(FadeTransition).first);
      expect(firstOpacity.opacity.value, lessThan(0.5));

      // 播完后全部可见
      await tester.pumpAndSettle();
      for (final f in tester.widgetList<FadeTransition>(find.byType(FadeTransition))) {
        expect(f.opacity.value, 1.0);
      }
      expect(settled, 1, reason: 'onAnimated 只回调一次');
      expect(find.text('拔剑相向'), findsOneWidget);
      expect(find.text('转身离开'), findsOneWidget);
    });

    testWidgets('animate=false：首帧即完全可见（历史/已播不重播）', (tester) async {
      var settled = 0;
      await tester.pumpWidget(_host(
        GameChoicesView(
          choices: _choices(),
          onSelected: (_) {},
          onAnimated: () => settled++,
        ),
      ));
      // 未 pump 前就应完全可见
      for (final f in tester.widgetList<FadeTransition>(find.byType(FadeTransition))) {
        expect(f.opacity.value, 1.0);
      }
      expect(settled, 0, reason: '静态模式不触发动画回调');
    });

    testWidgets('历史选项（active=false）：按钮禁用展示', (tester) async {
      await tester.pumpWidget(_host(
        GameChoicesView(choices: _choices(active: false)),
      ));
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton).first);
      expect(button.onPressed, isNull);
    });
  });

  group('玩家输入气泡入场', () {
    testWidgets('animate=true：首帧半透明上滑，收敛到完全可见', (tester) async {
      await tester.pumpWidget(_host(
        const GamePlayerInputView(text: '我推门而入', animate: true),
      ));
      final fade =
          tester.widget<FadeTransition>(find.byType(FadeTransition).first);
      expect(fade.opacity.value, lessThan(1.0));
      final slide = tester.widget<SlideTransition>(find.byType(SlideTransition).first);
      expect(slide.position.value.dy, greaterThan(0));

      await tester.pumpAndSettle();
      final done = tester.widget<FadeTransition>(find.byType(FadeTransition).first);
      expect(done.opacity.value, 1.0);
      expect(find.text('我推门而入'), findsOneWidget);
    });

    testWidgets('animate=false：首帧即完全可见（历史输入不重播）', (tester) async {
      await tester.pumpWidget(
        _host(const GamePlayerInputView(text: '我推门而入')),
      );
      final fade =
          tester.widget<FadeTransition>(find.byType(FadeTransition).first);
      expect(fade.opacity.value, 1.0);
    });
  });

  group('场景插图占位与登场', () {
    testWidgets('未完成：占位 shimmer + "插图生成中…"', (tester) async {
      await tester.pumpWidget(_host(
        const GameSceneImageView(
          segment: GameSceneImage(
            toolCallId: 'img1',
            prompt: 'candlelit room',
            toolResultJson: null,
            toolCompleted: false,
          ),
        ),
      ));
      expect(find.text('插图生成中…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('完成但无媒体：静态错误提示（无 shimmer）', (tester) async {
      await tester.pumpWidget(_host(
        GameSceneImageView(
          segment: GameSceneImage(
            toolCallId: 'img1',
            prompt: 'candlelit room',
            toolResultJson: '{"error":"failed","message":"生成失败"}',
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('生成失败'), findsOneWidget);
      expect(find.text('插图生成中…'), findsNothing);
    });
  });
}

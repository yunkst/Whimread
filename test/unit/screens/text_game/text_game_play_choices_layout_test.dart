/// 游玩页选项渲染位置测试（选项随内容流内联，不常驻输入区上方）
///
/// 背景：活动选项曾固定渲染在输入区上方，常驻占掉底部一大块，把阅读内容
/// 空间大幅压缩。本测试锁住：活动选项组渲染在剧情流 ListView 内部（紧跟
/// 剧情之后），输入区不再持有选项实例；点选仍能把 label 送到控制器。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_app/models/text_game.dart';
import 'package:novel_app/screens/text_game/game_transcript_projector.dart';
import 'package:novel_app/screens/text_game/text_game_play_controller.dart';
import 'package:novel_app/screens/text_game/text_game_play_screen.dart';
import 'package:novel_app/widgets/text_game/game_segment_views.dart';

// 生成Mock类（控制器依赖 DB/会话/agent 服务，屏幕测试只消费状态与下发动作）
@GenerateNiceMocks([MockSpec<TextGamePlayController>()])
import 'text_game_play_choices_layout_test.mocks.dart';

const int _gameId = 7;

TextGame _game() => TextGame(
      id: _gameId,
      title: '流云试炼',
      sourceNovelId: 1,
      settings: const GameSettings(coreExperience: '快节奏战斗爽文'),
      chatSessionId: 9,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// 活动选项组（回合结束等待玩家输入）
GameChoices _activeChoices() => const GameChoices(
      choices: [
        GameChoice(label: '拔剑相向'),
        GameChoice(label: '转身离开', hint: '风险低'),
      ],
      active: true,
      toolCallId: 'tc-c1',
    );

TextGamePlayState _state() => TextGamePlayState(
      initializing: false,
      game: _game(),
      transcript: [
        const GameNarration('雨夜，你在城门口醒来。'),
        _activeChoices(),
      ],
    );

MockTextGamePlayController _controller() {
  final controller = MockTextGamePlayController();
  final st = _state();
  when(controller.state).thenReturn(st);
  // Riverpod 的 StateNotifierProvider 挂载时靠 addListener(fireImmediately:
  // true) 同步回调拿初始状态；mock 须真回调一次，否则报"provider did not
  // initialize"。返回函数的方法要用直调形式 stub（避免 thenReturn 的
  // 函数字面量推断问题）
  when(controller.addListener(any,
          fireImmediately: anyNamed('fireImmediately')))
      .thenAnswer((inv) {
    final cb = inv.positionalArguments.first
        as void Function(TextGamePlayState);
    cb(st);
    return () {};
  });
  return controller;
}

Widget _host(MockTextGamePlayController controller) {
  return ProviderScope(
    overrides: [
      textGamePlayControllerProvider(_gameId)
          .overrideWith((ref) => controller),
    ],
    child: MaterialApp(home: TextGamePlayScreen(gameId: _gameId)),
  );
}

void main() {
  testWidgets('活动选项组渲染在剧情流 ListView 内（不挂输入区）',
      (tester) async {
    await tester.pumpWidget(_host(_controller()));

    // 核心回归锁：选项是 ListView 的后代（此前它在 ListView 之外的输入区）
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(GameChoicesView),
      ),
      findsOneWidget,
      reason: '活动选项应随剧情流内联渲染',
    );
    // 全局只有一个选项实例（流内一处，底部输入区不再另挂一份）
    expect(find.byType(GameChoicesView), findsOneWidget);
    // 选项紧跟在剧情之后：按钮出现在同一屏，且可点
    expect(find.text('拔剑相向'), findsOneWidget);
    expect(find.text('转身离开'), findsOneWidget);
  });

  testWidgets('点选活动选项把 label 送进控制器（不再走输入框）', (tester) async {
    final controller = _controller();
    await tester.pumpWidget(_host(controller));

    await tester.tap(find.text('转身离开'));
    await tester.pump();

    final result = verify(controller.sendChoice(captureAny));
    expect(result.callCount, 1);
    expect((result.captured.single as GameChoice).label, '转身离开');
  });
}

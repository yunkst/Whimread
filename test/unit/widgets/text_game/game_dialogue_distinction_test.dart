/// 台词与旁白区分度测试（用户反馈 #10：人物行动/对话/旁白分不清）
///
/// 台词段必须是"对话气泡"：文本包在带底色装饰的容器里（surfaceContainerLow），
/// 且带彩色角色名签；旁白段必须是无装饰的裸文本段落——两种段在组件树层面
/// 结构不同，玩家扫一眼就能分辨"谁在说话"和"剧情叙述"。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/text_game/game_segment_views.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 装饰是否为"底色气泡"（有色 + 圆角）
bool _isBubbleDecoration(Decoration? decoration) {
  if (decoration is! BoxDecoration) return false;
  return decoration.color != null && decoration.borderRadius != null;
}

void main() {
  testWidgets('台词：文本在带底色圆角的气泡里，且渲染彩色角色名签',
      (tester) async {
    await tester.pumpWidget(_host(const GameDialogueView(
      character: '林昭',
      text: '你终于来了。',
      avatarMediaId: null,
    )));

    expect(find.text('林昭'), findsOneWidget);
    expect(find.text('你终于来了。'), findsOneWidget);

    final bubbles = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(GameDialogueView),
          matching: find.byType(DecoratedBox),
        ))
        .where((b) => _isBubbleDecoration(b.decoration))
        .toList();
    expect(bubbles, isNotEmpty,
        reason: '台词文本必须有底色气泡包裹，与旁白裸文本区分');
  });

  testWidgets('旁白：裸文本段落，无底色气泡', (tester) async {
    await tester.pumpWidget(_host(
      const GameNarrationView(text: '屋内烛火摇曳，映出半张旧棋盘。'),
    ));

    expect(find.text('屋内烛火摇曳，映出半张旧棋盘。'), findsOneWidget);
    final bubbles = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(GameNarrationView),
          matching: find.byType(DecoratedBox),
        ))
        .where((b) => _isBubbleDecoration(b.decoration))
        .toList();
    expect(bubbles, isEmpty, reason: '旁白必须保持无装饰的阅读器段落');
  });
}

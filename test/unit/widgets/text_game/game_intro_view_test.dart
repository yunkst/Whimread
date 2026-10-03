/// GameIntroView 新游戏扉页测试
///
/// 覆盖：短内容渲染（标题/开场/世界观/开始按钮）/ 长开场文本可滚动且
/// 开始按钮固定可点 / 空设定占位降级。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/text_game/game_intro_view.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 元素底边是否落在内容区视口内（视口 = 滚动区，不含底部固定开始按钮）。
/// 长开场文本整体是一个高过视口的 Text，只能以底边判断「末尾可见」。
bool _bottomInViewport(WidgetTester tester, Finder finder) {
  final viewport = tester.getRect(find.byType(SingleChildScrollView));
  final bottom = tester.getRect(finder).bottom;
  return bottom <= viewport.bottom && bottom >= viewport.top;
}

void main() {
  testWidgets('短内容：渲染标题/开场情境/世界观/开始按钮', (tester) async {
    await tester.pumpWidget(_host(GameIntroView(
      title: '雾锁长安',
      opening: '雨夜，你在城门口醒来。',
      worldview: '大唐末年，妖气渐起。',
      onStart: () {},
    )));

    expect(find.text('雾锁长安'), findsOneWidget);
    expect(find.text('开场情境'), findsOneWidget);
    expect(find.text('雨夜，你在城门口醒来。'), findsOneWidget);
    expect(find.text('世界观'), findsOneWidget);
    expect(find.text('大唐末年，妖气渐起。'), findsOneWidget);
    expect(find.text('开始游戏'), findsOneWidget);
  });

  testWidgets('长开场文本：内容区可滚动，开始按钮固定在滚动区外可点', (tester) async {
    final longOpening =
        List.generate(60, (i) => '第$i幕：命运的齿轮继续转动。').join('\n\n');
    var started = false;
    await tester.pumpWidget(_host(GameIntroView(
      title: '雾锁长安',
      opening: longOpening,
      worldview: '',
      onStart: () => started = true,
    )));
    await tester.pumpAndSettle();

    // SingleChildScrollView 会构建全部子节点，屏幕外文本也在树里——
    // 可滚动性看滚动范围与视口内可见性，不能靠 find 有无
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable));
    expect(
      scrollable.position.maxScrollExtent,
      greaterThan(0),
      reason: '长开场文本必须产生滚动范围（不可滚动=溢出裁切，即本次修复的缺陷）',
    );
    expect(_bottomInViewport(tester, find.textContaining('第59幕')), isFalse,
        reason: '初始末段在视口之外');

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0), reason: '拖拽应产生滚动位移');

    // 滚到最底：末段完整进入视口（视口=滚动区，不含底部固定按钮）
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_bottomInViewport(tester, find.textContaining('第59幕')), isTrue,
        reason: '长开场文本必须可滚动');

    // 开始按钮固定在滚动区外：滚到底依然直接可点
    // （FilledButton.icon 是私有子类，byType 精确匹配不到，直接点文本）
    await tester.tap(find.text('开始游戏'));
    await tester.pump();
    expect(started, isTrue);
  });

  testWidgets('未填写开场：展示占位文案，不渲染空卡片', (tester) async {
    await tester.pumpWidget(_host(GameIntroView(
      title: '雾锁长安',
      opening: '',
      worldview: '',
      onStart: () {},
    )));

    expect(find.text('你的故事等待开场'), findsOneWidget);
    expect(find.text('开场情境'), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}

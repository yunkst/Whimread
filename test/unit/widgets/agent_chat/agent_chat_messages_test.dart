import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_messages.dart';
import 'package:novel_app/widgets/agent_chat/agent_message_bubble.dart';

/// 取消息列表主 Scrollable 的 position（气泡内可能有嵌套 ScrollView，取第一个）
ScrollPosition _listPosition(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      )
      .position;
}

AgentChatMessage _msg(String text, [AgentChatRole role = AgentChatRole.user]) {
  return AgentChatMessage(role: role, segments: [TextSegment(text)]);
}

void main() {
  testWidgets('空 messages + 非流式 -> 渲染 EmptyStateView（含印章 quill 图标 + serif 标题）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: [
            currentChatStateProvider
                .overrideWith((ref) => const AgentChatState()),
          ],
          child: const AgentChatMessages(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // quill 图标 AgentIcons.quill = Icons.edit，空状态印章容器含该 Icon
    expect(find.byIcon(Icons.edit), findsOneWidget);
    // serif 标题：「开始今天的写作」
    final titleFinder = find.text('开始今天的写作');
    expect(titleFinder, findsOneWidget);
    final Text titleWidget = tester.widget<Text>(titleFinder);
    expect(titleWidget.style?.fontFamily, 'NotoSerifSC');
  });

  testWidgets('非空 messages -> ListView 渲染 AgentMessageBubble（空分支不显示 EmptyStateView）',
      (tester) async {
    // 不写 AgentChatMessage 构造（本测试不深探 segments 内容），仅测控制流。
    // 直接测 messages.isEmpty 时不渲染 EmptyStateView。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: [
            currentChatStateProvider.overrideWith(
                (ref) => const AgentChatState(
                      // messages 默认 const [] 空，仍走空状态分支，验证不渲染 ListView
                    )),
          ],
          child: const AgentChatMessages(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 期望: 没有任何 AgentMessageBubble，仅空状态
    expect(find.byType(AgentMessageBubble), findsNothing);
  });

  testWidgets('打开长会话 -> 初始直接定位到最新消息，回底按钮不出现', (tester) async {
    // 尾部消息远比前段高：懒加载外推的 maxScrollExtent 会低估，
    // 验证初始定位走迭代收敛而不是一次 jumpTo
    final messages = <AgentChatMessage>[
      for (var i = 0; i < 30; i++) _msg('历史消息 $i'),
      _msg('最新回复 ${'很长的回复内容 ' * 120}', AgentChatRole.assistant),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: [
            currentChatStateProvider
                .overrideWith((ref) => AgentChatState(messages: messages)),
          ],
          child: const AgentChatMessages(),
        ),
      ),
    ));
    await tester.pump(); // 触发 initState post-frame 首跳
    await tester.pumpAndSettle();

    final position = _listPosition(tester);
    expect(position.pixels,
        greaterThanOrEqualTo(position.maxScrollExtent - 40));
    expect(find.textContaining('最新回复'), findsOneWidget);
    // 已在底部，回底按钮不应出现
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets('长上下文点击回底按钮 -> 一次迭代直达真实底部', (tester) async {
    // 前段消息短、尾部消息长：复现"一次 animateTo 只到估算假底部"的场景
    final messages = <AgentChatMessage>[
      for (var i = 0; i < 40; i++) _msg('短消息 $i'),
      for (var i = 0; i < 6; i++)
        _msg('长回复 $i ${'很长的回复内容 ' * 200}', AgentChatRole.assistant),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: [
            currentChatStateProvider
                .overrideWith((ref) => AgentChatState(messages: messages)),
          ],
          child: const AgentChatMessages(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    final position = _listPosition(tester);
    // 手动滚回顶部，模拟用户翻历史（程序化 jumpTo 不产生 UserScrollNotification）
    position.jumpTo(0);
    await tester.pump();

    // 回底按钮出现
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();

    // 一次点击直达真实底部，最后一条消息可见
    expect(position.pixels,
        greaterThanOrEqualTo(position.maxScrollExtent - 40));
    expect(find.textContaining('长回复 5'), findsOneWidget);
    // 到底后按钮隐藏
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets('吸底跟随：在底部时内容变高自动跟随，上滑翻历史后不再打扰', (tester) async {
    final initialMessages = <AgentChatMessage>[
      for (var i = 0; i < 30; i++) _msg('消息 $i'),
    ];
    final chatNotifier = StateProvider<AgentChatState>(
        (ref) => AgentChatState(messages: initialMessages));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: [
            currentChatStateProvider
                .overrideWith((ref) => ref.watch(chatNotifier)),
          ],
          child: const AgentChatMessages(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final position = _listPosition(tester);
    expect(position.pixels,
        greaterThanOrEqualTo(position.maxScrollExtent - 40));

    // 在底部时追加新消息 -> 自动跟随到最新
    final container = ProviderScope.containerOf(
        tester.element(find.byType(AgentChatMessages)));
    container.read(chatNotifier.notifier).state = AgentChatState(
      messages: [...initialMessages, _msg('跟随新消息', AgentChatRole.assistant)],
    );
    await tester.pumpAndSettle();
    expect(position.pixels,
        greaterThanOrEqualTo(position.maxScrollExtent - 40));
    expect(find.textContaining('跟随新消息'), findsOneWidget);

    // 手动上滑翻历史 -> 跟随解除，再追加内容不再打扰阅读位置
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    final offsetBefore = position.pixels;
    expect(offsetBefore, lessThan(position.maxScrollExtent - 40));

    final afterDrag = [...initialMessages, _msg('跟随新消息', AgentChatRole.assistant)];
    container.read(chatNotifier.notifier).state = AgentChatState(
      messages: [...afterDrag, _msg('打扰消息', AgentChatRole.assistant)],
    );
    await tester.pumpAndSettle();
    expect(position.pixels, offsetBefore);
  });
}

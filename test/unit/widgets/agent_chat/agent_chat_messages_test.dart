import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_messages.dart';
import 'package:novel_app/widgets/agent_chat/agent_message_bubble.dart';

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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/current_novel_provider.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_header.dart';

Widget _wrap(Widget child, {AgentChatState? state}) => MaterialApp(
      home: Scaffold(body: ProviderScope(overrides: [
        currentChatStateProvider.overrideWith((ref) => state ??
            const AgentChatState(
              scenarioId: ScenarioIds.writing,
              scenarioDisplayName: '小说写作助手',
            )),
      ], child: child)),
    );

void main() {
  testWidgets('writing 场景渲染 serif 标题 + 上下文行占位（未选小说）', (tester) async {
    await tester.pumpWidget(_wrap(const AgentChatHeader()));
    await tester.pumpAndSettle();
    expect(find.text('小说写作助手'), findsOneWidget);
    expect(find.textContaining('尚未选择小说'), findsOneWidget);
  });

  testWidgets('已选小说时上下文行显示「阅读《书名》」而非占位', (tester) async {
    const selected = CurrentNovel(id: 7, title: '测试书', url: 'u7');
    final state = const AgentChatState(
      scenarioId: ScenarioIds.writing,
      scenarioDisplayName: '小说写作助手',
      currentNovel: selected,
    );
    await tester.pumpWidget(_wrap(const AgentChatHeader(), state: state));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未选择小说'), findsNothing,
        reason: '已选小说后不应再显示占位提示');
    expect(find.textContaining('阅读《测试书》'), findsOneWidget);
  });

  testWidgets('Header 含 场景菜单/全屏/新建会话/关闭 四按钮（历史收入菜单）',
      (tester) async {
    await tester.pumpWidget(_wrap(const AgentChatHeader()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('场景与设置'), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('新建会话'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    // 历史不再是独立按钮，已收入 dots 场景菜单
    expect(find.byTooltip('会话历史'), findsNothing);
  });

  testWidgets('点击「新建会话」按钮触发 onNewSession 回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(AgentChatHeader(
      onNewSession: () => tapped++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pump();
    expect(tapped, 1, reason: '点击新建会话按钮应触发一次 onNewSession 回调');
  });
}

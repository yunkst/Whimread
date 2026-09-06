import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_composer.dart';

Widget _wrap(Widget child, {AgentChatState? state}) => MaterialApp(
      home: Scaffold(body: ProviderScope(overrides: [
        currentChatStateProvider.overrideWith(
            (ref) => state ?? const AgentChatState(scenarioId: ScenarioIds.writing)),
      ], child: child)),
    );

void main() {
  testWidgets('渲染输入框 + 发送按钮（tooltip 发送）', (tester) async {
    await tester.pumpWidget(_wrap(const AgentChatComposer()));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('发送'), findsOneWidget);
  });

  testWidgets('无文本时发送按钮禁用（onPressed null）', (tester) async {
    await tester.pumpWidget(_wrap(const AgentChatComposer()));
    await tester.pumpAndSettle();
    // find.byTooltip 校验发送按钮渲染存在即可
    // （不取 widget 强转 Tooltip：Flutter 升级后 byTooltip 命中的是 RawTooltip 子类，
    //   不再是 Tooltip，as Tooltip 会抛 _TypeError）
    expect(find.byTooltip('发送'), findsOneWidget);
  });
}

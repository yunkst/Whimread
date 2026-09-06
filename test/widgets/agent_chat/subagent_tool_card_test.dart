/// 任务 10 Widget 测试：SubagentToolCard
///
/// 覆盖：
/// 1. 无 run 时显示 task 摘要（pending 默认）
/// 2. completed 状态显示 "完成" / finalSummary 摘要
/// 3. 点击触发 onTap
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/providers/subagent_providers.dart';
import 'package:novel_app/services/novel_agent/subagent_run.dart';
import 'package:novel_app/widgets/agent_chat/subagent_tool_card.dart';

void main() {
  group('SubagentToolCard', () {
    testWidgets('pending 默认文案（run 尚未创建时不崩）', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SubagentToolCard(
                sessionId: 's1',
                toolCallId: 'tc-missing',
                task: '梳理人物',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('梳理人物'), findsOneWidget);
      // 找不到 run 时 fallback 摘要为 "派发中…"
      expect(find.textContaining('派发中'), findsOneWidget);
    });

    testWidgets('completed 状态显示 finalSummary 第一行', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 预设一个 completed run
      final registry = container.read(subagentRegistryProvider);
      final run = registry.create(
        parentSessionId: 's1',
        task: '梳理人物',
        allowedTools: const ['get_outline'],
        toolCallId: 'tc1',
      );
      run.state = SubagentRunState.completed;
      run.finalSummary = '## 最终结论\n完成。';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SubagentToolCard(
                sessionId: 's1',
                toolCallId: 'tc1',
                task: '梳理人物',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('子 Agent: 梳理人物'), findsOneWidget);
      // finalSummary 第一行被截短到 60 字内显示
      expect(find.textContaining('最终结论'), findsOneWidget);
    });

    testWidgets('点击触发 onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SubagentToolCard(
                sessionId: 's1',
                toolCallId: 'tc1',
                task: 't',
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(SubagentToolCard));
      expect(tapped, isTrue);
    });

    testWidgets('failed 状态显示错误信息', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final registry = container.read(subagentRegistryProvider);
      final run = registry.create(
        parentSessionId: 's1',
        task: '出错了',
        allowedTools: const [],
        toolCallId: 'tc-fail',
      );
      run.state = SubagentRunState.failed;
      run.errorMessage = '网络超时';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SubagentToolCard(
                sessionId: 's1',
                toolCallId: 'tc-fail',
                task: '出错了',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('出错了'), findsOneWidget);
      expect(find.textContaining('网络超时'), findsOneWidget);
    });

    testWidgets('completed 状态默认禁用点击（防止误触误重开详情）', (tester) async {
      var tapped = false;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final registry = container.read(subagentRegistryProvider);
      final run = registry.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const [],
        toolCallId: 'tc-done',
      );
      run.state = SubagentRunState.completed;
      run.finalSummary = 'done';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SubagentToolCard(
                sessionId: 's1',
                toolCallId: 'tc-done',
                task: 't',
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(SubagentToolCard));
      expect(tapped, isFalse);
    });
  });
}

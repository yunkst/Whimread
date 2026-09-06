import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/subagent_providers.dart';
import 'package:novel_app/screens/subagent_detail_screen.dart';
import 'package:novel_app/services/novel_agent/subagent_run.dart';
import 'package:novel_app/utils/cancellation_token.dart';

void main() {
  group('SubagentDetailScreen', () {
    testWidgets('显示 task 标题、allowedTools chips、状态', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final registry = container.read(subagentRegistryProvider);
      final run = registry.create(
        parentSessionId: 's1',
        task: '梳理人物',
        allowedTools: const ['get_outline', 'read_chapter'],
        toolCallId: 'tc1',
      );
      run.state = SubagentRunState.running;

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SubagentDetailScreen(sessionId: 's1', toolCallId: 'tc1'),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('梳理人物'), findsWidgets);
      expect(find.text('get_outline'), findsOneWidget);
      expect(find.text('read_chapter'), findsOneWidget);
      // 状态 chip 文案 'running'
      expect(find.text('running'), findsWidgets);
    });

    testWidgets('running 状态显示停止按钮，点击触发 cancel', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final registry = container.read(subagentRegistryProvider);
      final run = registry.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const [],
        toolCallId: 'tc1',
      );
      run.state = SubagentRunState.running;
      run.tokenSource = CancellationTokenSource();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SubagentDetailScreen(sessionId: 's1', toolCallId: 'tc1'),
        ),
      ));
      await tester.pump();

      final stopBtn = find.byIcon(Icons.stop);
      expect(stopBtn, findsOneWidget);

      await tester.tap(stopBtn);
      await tester.pump();

      expect(run.tokenSource?.isCancelled, isTrue);
      // 让 _onStop 的 await run.done 完成，避免遗留 timer
      run.completeDone();
      await tester.pump();
    });

    testWidgets('completed 状态不显示停止按钮', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final registry = container.read(subagentRegistryProvider);
      final run = registry.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const [],
        toolCallId: 'tc1',
      );
      run.state = SubagentRunState.completed;

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SubagentDetailScreen(sessionId: 's1', toolCallId: 'tc1'),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.stop), findsNothing);
    });

    testWidgets('run 不存在时显示占位文案', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SubagentDetailScreen(sessionId: 's1', toolCallId: 'missing'),
        ),
      ));
      await tester.pump();

      expect(find.text('子 Agent 不存在或已清理'), findsOneWidget);
    });

    testWidgets('停止按钮点击后等 done 完成才恢复（loading → 按钮）',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final registry = container.read(subagentRegistryProvider);
      final run = registry.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const [],
        toolCallId: 'tc1',
      );
      run.state = SubagentRunState.running;
      run.tokenSource = CancellationTokenSource();

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SubagentDetailScreen(sessionId: 's1', toolCallId: 'tc1'),
        ),
      ));
      await tester.pump();

      // 模拟 _onStop 等待 done：测试期间不主动 completeDone，
      // 先验证按钮变 loading
      await tester.tap(find.byIcon(Icons.stop));
      // 不 pump 立即让 tap 落地，只 pump 一次让 _onStop 走完到 await
      await tester.pump();

      // 按钮应已消失（CircularProgressIndicator 出现）
      expect(find.byIcon(Icons.stop), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // 状态应已被 cancel
      expect(run.tokenSource?.isCancelled, isTrue);

      // 现在 completeDone，让 _onStop 恢复按钮
      run.state = SubagentRunState.cancelled;
      run.completeDone();
      // 给 _onStop 的 await run.done 解析 + 后续 setState + 重建窗口时间
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();

      // run 进入终态后，停止按钮按现状（不再显示）
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

/// Agent 场景显式声明链路测试（2026-09-05 修复）
///
/// 锁定修复：阅读页/章节列表页的 Agent FAB 此前依赖全局
/// currentAgentScenarioProvider 的"当前值"，而该值只跟踪底部 Tab 索引——
/// 从浏览器 Tab push 出的页面（章节列表/阅读页）继承 webview_extract，
/// 导致打开 Agent 看到「网页小说提取」而非「小说写作助手」。
///
/// 修复后场景由页面入口显式声明：AgentFloatingShell(scenarioId:) →
/// AgentFloatingButton → AgentChatLauncherEntry.open(scenarioId:) →
/// 弹窗前写入 provider → currentSessionProvider 按显式场景解析会话。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/widgets/agent_fab_scenario_test.dart
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/agent_events_provider.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_dialog.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_launcher_entry.dart';
import 'package:novel_app/widgets/agent_chat/agent_floating_button.dart';

void main() {
  final eventsController = StreamController<AgentEvent>.broadcast();

  setUp(() {
    // 避免 RetrySignals 全局单例残留启动 Timer、LoggerService 1s 刷写 Timer
    // 导致 testWidgets 因 pending timers 失败
    RetrySignals.instance.resetForTest();
    LoggerService.resetForTesting();
  });

  tearDown(() {
    RetrySignals.instance.resetForTest();
    LoggerService.resetForTesting();
  });

  /// 构建带安全 overrides 的容器（与 agent_chat_dialog_compaction_test 同款：
  /// 避免 ScenarioSessionsNotifier 跨 provider 写入告警）。
  /// [chatState] 决定 header 渲染的场景名。
  ProviderContainer buildContainer(AgentChatState chatState) {
    return ProviderContainer(overrides: [
      currentChatStateProvider.overrideWithValue(chatState),
      currentSessionProvider.overrideWithValue(null),
      agentEventsProvider.overrideWith((ref) => eventsController.stream),
    ]);
  }

  Future<void> pumpAndOpenScenarioEntry(
    WidgetTester tester, {
    required ProviderContainer container,
    String? scenarioId,
  }) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AgentChatLauncherEntry.open(
                context,
                scenarioId: scenarioId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('AgentChatLauncherEntry.open(scenarioId:) 弹窗前写入场景', () {
    testWidgets('全局 provider 残留 webview_extract 时，writing 入口仍切回 writing',
        (tester) async {
      final container = buildContainer(const AgentChatState());
      addTearDown(container.dispose);

      // 模拟：用户从浏览器 Tab 进入阅读页，全局场景残留 webview_extract
      container.read(currentAgentScenarioProvider.notifier).state =
          ScenarioIds.webviewExtract;

      await pumpAndOpenScenarioEntry(
        tester,
        container: container,
        scenarioId: ScenarioIds.writing,
      );

      expect(container.read(currentAgentScenarioProvider),
          ScenarioIds.writing,
          reason: 'open 必须在弹窗前写入显式场景，dialog 才能按 writing 解析会话');
      expect(find.byType(AgentChatDialog), findsOneWidget);
      expect(find.text('小说写作助手'), findsWidgets,
          reason: 'header 应显示 writing 场景名，而非残留的「网页小说提取」');
    });

    testWidgets('显式 webview_extract 入口同样生效（浏览器页降级方向）', (tester) async {
      final container = buildContainer(const AgentChatState(
        scenarioId: ScenarioIds.webviewExtract,
        scenarioDisplayName: '网页小说提取',
      ));
      addTearDown(container.dispose);

      container.read(currentAgentScenarioProvider.notifier).state =
          ScenarioIds.writing;

      await pumpAndOpenScenarioEntry(
        tester,
        container: container,
        scenarioId: ScenarioIds.webviewExtract,
      );

      expect(container.read(currentAgentScenarioProvider),
          ScenarioIds.webviewExtract);
      expect(find.text('网页小说提取'), findsWidgets);
    });

    testWidgets('scenarioId 为 null 时不干预全局 provider（ContextualAgentLauncher 兼容）',
        (tester) async {
      final container = buildContainer(const AgentChatState());
      addTearDown(container.dispose);

      container.read(currentAgentScenarioProvider.notifier).state =
          ScenarioIds.webviewExtract;

      await pumpAndOpenScenarioEntry(tester, container: container);

      expect(container.read(currentAgentScenarioProvider),
          ScenarioIds.webviewExtract,
          reason: '不传 scenarioId 时沿用全局当前值（调用方已自行写入）');
      expect(find.byType(AgentChatDialog), findsOneWidget);
    });
  });

  group('AgentFloatingShell(scenarioId:) 透传', () {
    testWidgets('scenarioId 传递给内部 AgentFloatingButton', (tester) async {
      final container = buildContainer(const AgentChatState());
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AgentFloatingShell(
              scenarioId: ScenarioIds.webviewExtract,
              child: const SizedBox(),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(
        find.byWidgetPredicate((w) =>
            w is AgentFloatingButton &&
            w.scenarioId == ScenarioIds.webviewExtract),
        findsOneWidget,
      );
    });

    testWidgets('不传 scenarioId 时为 null（不干预，跨 Tab 共享 Shell 沿用全局值）',
        (tester) async {
      final container = buildContainer(const AgentChatState());
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AgentFloatingShell(child: const SizedBox()),
          ),
        ),
      ));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
            (w) => w is AgentFloatingButton && w.scenarioId == null),
        findsOneWidget,
        reason: 'main.dart 的 Shell 跨书架/浏览器/设置三个 Tab 共享，'
            '场景由 Tab 切换逻辑维护，FAB 不得覆写',
      );
    });
  });
}

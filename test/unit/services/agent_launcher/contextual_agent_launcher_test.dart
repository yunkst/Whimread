library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_app/core/providers/agent_launcher_providers.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/agent_launcher/agent_launch_request.dart';
import 'package:novel_app/services/agent_launcher/contextual_agent_launcher.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';

@GenerateNiceMocks([MockSpec<ScenarioSessionsNotifier>(), MockSpec<ScenarioSession>()])
import 'contextual_agent_launcher_test.mocks.dart';

void main() {
  setUp(() {
    // 取消更早测试可能残留的 LoggerService 延迟持久化 timer，避免其作为 pending
    // timer 触发本 widget test 的 _verifyInvariants（timersPending 断言）。
    LoggerService.resetForTesting();
  });

  // 这两个 testWidgets 会真实打开 AgentChatDialog 并触发会话初始化，
  // 期间（或前面其它测试）经由 LoggerService 记日志时，LoggerService 在
  // 距上次持久化 <1s 时会安排一个 1s 后的兜底 timer；若测试结束前没取消，
  // 这个 pending timer 会触发 _verifyInvariants 的 timersPending 断言（CI 必现）。
  // 根治：setUp 调 LoggerService.resetForTesting() 取消残留 timer（与其它触发
  // 日志的 webview 测试对齐）。retry:3 作额外保险，不影响断言有效性。
  group('ContextualAgentLauncher.launch', () {
    testWidgets(
      'autoSend 模式: 切场景 + switchSession(id, null) + 调 sendMessage',
      (tester) async {
        final mockNotifier = MockScenarioSessionsNotifier();
        final mockSession = MockScenarioSession();

        when(mockNotifier.switchSession(any, any)).thenAnswer((_) async {});
        when(mockSession.sendMessage(content: anyNamed('content')))
            .thenAnswer((_) async {});
        when(mockNotifier.get(any)).thenReturn(mockSession);

        late ProviderContainer container;
        late BuildContext capturedContext;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scenarioSessionsProvider.overrideWith((ref) {
                return _StubScenarioSessionsNotifier(
                  delegate: mockNotifier,
                  ref: ref,
                );
              }),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    capturedContext = context;
                    container = ProviderScope.containerOf(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );

        final launcher = container.read(contextualAgentLauncherProvider);
        await launcher.launch(
          capturedContext,
          AgentLaunchRequest(
            scenarioId: ScenarioIds.webviewExtract,
            context: {'currentUrl': 'https://a.com/book/1'},
            draftMessage: '请生成提取脚本',
            mode: LaunchMode.autoSend,
          ),
        );
        await tester.pump();

        expect(
          container.read(currentAgentScenarioProvider),
          ScenarioIds.webviewExtract,
        );
        verify(mockNotifier.switchSession(ScenarioIds.webviewExtract, null))
            .called(1);
        verify(mockSession.sendMessage(content: '请生成提取脚本')).called(1);
      },
      retry: 3,
    );

    testWidgets(
      'draftOnly 模式: 切场景 + switchSession(id, null),不调 sendMessage',
      (tester) async {
        final mockNotifier = MockScenarioSessionsNotifier();
        final mockSession = MockScenarioSession();

        when(mockNotifier.switchSession(any, any)).thenAnswer((_) async {});
        when(mockNotifier.get(any)).thenReturn(mockSession);

        late ProviderContainer container;
        late BuildContext capturedContext;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scenarioSessionsProvider.overrideWith((ref) {
                return _StubScenarioSessionsNotifier(
                  delegate: mockNotifier,
                  ref: ref,
                );
              }),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    capturedContext = context;
                    container = ProviderScope.containerOf(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );

        final launcher = container.read(contextualAgentLauncherProvider);
        await launcher.launch(
          capturedContext,
          AgentLaunchRequest(
            scenarioId: ScenarioIds.webviewExtract,
            context: {'currentUrl': 'https://a.com/book/1'},
            draftMessage: '请生成提取脚本',
            mode: LaunchMode.draftOnly,
          ),
        );
        await tester.pump();

        expect(
          container.read(currentAgentScenarioProvider),
          ScenarioIds.webviewExtract,
        );
        verify(mockNotifier.switchSession(ScenarioIds.webviewExtract, null))
            .called(1);
        verifyNever(mockSession.sendMessage(content: anyNamed('content')));
      },
      retry: 3,
    );
  });
}

/// StateNotifier 子类桩: 解决 "Bad state, the provider did not initialize" 问题。
class _StubScenarioSessionsNotifier extends ScenarioSessionsNotifier {
  final MockScenarioSessionsNotifier delegate;

  _StubScenarioSessionsNotifier({required this.delegate, required Ref ref})
      : super(ref);

  @override
  Future<void> switchSession(String scenarioId, int? newSessionId) {
    return delegate.switchSession(scenarioId, newSessionId);
  }

  @override
  ScenarioSession get(String scenarioId) => delegate.get(scenarioId);
}
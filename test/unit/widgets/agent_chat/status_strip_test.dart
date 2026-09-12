import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/widgets/agent_chat/agent_status_strip.dart';

const _retry = RetryState(
  level: RetryLevel.transport,
  attempt: 2,
  maxAttempts: 8,
  delayMs: 7000,
  errorCategory: RetryErrorCategory.rateLimited,
  httpStatusCode: 429,
);

void main() {
  test('idle（无 error/retry/supplement）-> null', () {
    expect(selectStatus(const AgentChatState(), null), isNull);
  });

  test('error 且 !isLoading -> error', () {
    final s = selectStatus(const AgentChatState(error: 'boom'), null);
    expect(s?.kind, AgentStatusKind.error);
    expect(s?.message, 'boom');
  });

  test('普通 error 不带动作按钮（quotaExhausted=false）', () {
    final s = selectStatus(const AgentChatState(error: 'boom'), null);
    expect(s?.hasAction, isFalse);
  });

  test('额度耗尽 error -> error 态挂「去 Star 补额度」动作', () {
    var tapped = false;
    final s = selectStatus(
      const AgentChatState(error: '免费额度已用完', quotaExhausted: true),
      null,
      onQuotaAction: () => tapped = true,
    );
    expect(s?.kind, AgentStatusKind.error);
    expect(s?.hasAction, isTrue);
    // 未兑换过时文案改写为 Star 引导（原 toString 文案不指向任何动作）
    expect(s?.message, contains('GitHub'));
    expect(s?.message, contains('⭐'));
    s?.onAction?.call();
    expect(tapped, isTrue);
  });

  test('额度耗尽但已 Star 兑换过（一次性权益）-> 不再挂 Star 动作', () {
    final s = selectStatus(
      const AgentChatState(error: '免费额度已用完,请联系管理员或在设置中查看设备额度',
          quotaExhausted: true),
      null,
      onQuotaAction: () {},
      hasRedeemedStar: true,
    );
    expect(s?.kind, AgentStatusKind.error);
    expect(s?.hasAction, isFalse);
    // 已兑换过 → 保持原始错误文案（引导去设置页），不误导用户再撞 ALREADY_REDEEMED
    expect(s?.message, '免费额度已用完,请联系管理员或在设置中查看设备额度');
  });

  test('额度耗但未传 onQuotaAction -> 无回调（安全降级）', () {
    final s = selectStatus(
      const AgentChatState(error: '免费额度已用完', quotaExhausted: true),
      null,
    );
    expect(s?.hasAction, isFalse);
    expect(s?.onAction, isNull);
  });

  test('error 且 isLoading -> 不返 error（让位 retry/running）', () {
    final s = selectStatus(
        const AgentChatState(error: 'boom', isLoading: true), null);
    expect(s?.kind, isNot(AgentStatusKind.error));
  });

  test('retry 非 null -> retry，含 attempt/maxAttempts + 类别 + HTTP', () {
    final s = selectStatus(const AgentChatState(), _retry);
    expect(s?.kind, AgentStatusKind.retry);
    expect(s?.detail, contains('2/8'));
    expect(s?.detail, contains('限流'));
    expect(s?.detail, contains('HTTP 429'));
    expect(s?.countdownSeconds, 7);
  });

  test('isLoading + supplementaryCount>0 + 无 retry -> supplement', () {
    final s = selectStatus(
        const AgentChatState(isLoading: true, supplementaryCount: 3), null);
    expect(s?.kind, AgentStatusKind.supplement);
    expect(s?.message, contains('3'));
  });

  test('error 压 retry（同时存在 -> error）', () {
    final s = selectStatus(const AgentChatState(error: 'boom'), _retry);
    expect(s?.kind, AgentStatusKind.error);
  });

  test('retry 压 supplement', () {
    final s = selectStatus(
        const AgentChatState(isLoading: true, supplementaryCount: 3), _retry);
    expect(s?.kind, AgentStatusKind.retry);
  });

  test('retry round 层 -> detail 标「回合层」', () {
    final r = RetryState(
      level: RetryLevel.round,
      attempt: 1,
      maxAttempts: 3,
      delayMs: 2000,
      errorCategory: RetryErrorCategory.serverError,
      httpStatusCode: 502,
    );
    final s = selectStatus(const AgentChatState(), r);
    expect(s?.detail, contains('回合层'));
  });

  // ---- running 兜底态（停止按钮入口）----

  test('isLoading 无 supplement 无 retry -> running', () {
    final s = selectStatus(const AgentChatState(isLoading: true), null);
    expect(s?.kind, AgentStatusKind.running);
    expect(s?.message, '正在生成…');
  });

  test('retry 压 running（isLoading=true + retry -> retry 非 running）', () {
    final s = selectStatus(const AgentChatState(isLoading: true), _retry);
    expect(s?.kind, AgentStatusKind.retry);
  });

  test('supplement 压 running（isLoading + supplementaryCount>0 -> supplement）',
      () {
    final s = selectStatus(
        const AgentChatState(isLoading: true, supplementaryCount: 1), null);
    expect(s?.kind, AgentStatusKind.supplement);
  });

  // ---- widget：停止按钮渲染与点击 ----

  testWidgets('running 态渲染「停止」按钮且点击触发 onStop', (tester) async {
    var stopped = false;
    await tester.pumpWidget(
        _wrapRunning(AgentStatusStrip(onStop: () => stopped = true)));
    await tester.pump(); // running 态用 CircularProgressIndicator，pumpAndSettle 永不收敛
    expect(find.text('正在生成…'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(stopped, isTrue);
  });

  testWidgets('onStop 为 null 时不渲染停止按钮（向后兼容）', (tester) async {
    await tester.pumpWidget(_wrapRunning(const AgentStatusStrip()));
    await tester.pump();
    expect(find.text('正在生成…'), findsOneWidget);
    expect(find.text('停止'), findsNothing);
  });
}

Widget _wrapRunning(Widget child, {bool isLoading = true}) => MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          overrides: [
            currentChatStateProvider.overrideWith((ref) => AgentChatState(
                  scenarioId: ScenarioIds.writing,
                  scenarioDisplayName: '小说写作助手',
                  isLoading: isLoading,
                )),
          ],
          child: child,
        ),
      ),
    );

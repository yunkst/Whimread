library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_launcher_entry.dart';

/// 测试辅助：用最小 ProviderScope 包裹测试用例。
///
/// AgentChatDialog 是 ConsumerStatefulWidget，build 时会
/// ref.watch(currentChatStateProvider) 与 ref.read(currentSessionProvider)，
/// 必须提供 ProviderScope 祖先 + 这两个 provider 的安全 override，
/// 否则 pump 时直接抛出 ProviderScope 异常。
Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      currentChatStateProvider.overrideWithValue(
        const AgentChatState(),
      ),
      currentSessionProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  // 避免 RetrySignals 全局单例残留影响测试（RetryBanner 订阅它并启动 Timer）
  setUp(() {
    RetrySignals.instance.resetForTest();
    LoggerService.resetForTesting();
  });
  tearDown(() {
    RetrySignals.instance.resetForTest();
    LoggerService.resetForTesting();
  });

  group('AgentChatLauncherEntry.open', () {
    testWidgets('调用后弹出 AgentChatDialog', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AgentChatLauncherEntry.open(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // AgentChatDialog 打开后会渲染输入框
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('带 initialDraft 打开后输入框已预填', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AgentChatLauncherEntry.open(
                context,
                initialDraft: '预填内容',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final textField = find.byType(TextField).first;
      expect(
        tester.widget<TextField>(textField).controller!.text,
        '预填内容',
      );
    });
  });
}

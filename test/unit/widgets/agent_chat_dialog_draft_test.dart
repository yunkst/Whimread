library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_dialog.dart';

/// 测试辅助：用安全 overrides 包装 AgentChatDialog，避免 ScenarioSessionsNotifier
/// 在初始化阶段触发 "modify other providers" 断言（dialog build 时会
/// read currentSessionProvider，懒创建会立即 setState 触发跨 provider 修改）。
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

  group('AgentChatDialog initialDraft', () {
    testWidgets('initialDraft 非空时预填输入框', (tester) async {
      await tester.pumpWidget(
        _wrap(const AgentChatDialog(initialDraft: '请生成提取脚本')),
      );
      await tester.pump();
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      expect(
        tester.widget<TextField>(textField).controller!.text,
        '请生成提取脚本',
      );
    });

    testWidgets('initialDraft 为 null 时输入框为空', (tester) async {
      await tester.pumpWidget(
        _wrap(const AgentChatDialog()),
      );
      await tester.pump();
      final textField = find.byType(TextField);
      expect(
        tester.widget<TextField>(textField).controller!.text,
        '',
      );
    });
  });
}

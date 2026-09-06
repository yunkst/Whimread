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
Widget _wrap({AgentChatState? state}) {
  return ProviderScope(
    overrides: [
      currentChatStateProvider.overrideWithValue(
        state ?? const AgentChatState(),
      ),
      currentSessionProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      home: Scaffold(body: const AgentChatDialog()),
    ),
  );
}

/// 在 dialog 内查找指定 tooltip 的 IconButton。
IconButton? _findIconButtonByTooltip(WidgetTester tester, String tooltip) {
  for (final b in tester.widgetList<IconButton>(find.byType(IconButton))) {
    if (b.tooltip == tooltip) return b;
  }
  return null;
}

void main() {
  // 避免 RetrySignals 全局单例残留影响测试（AgentStatusStrip 订阅它）
  setUp(() {
    RetrySignals.instance.resetForTest();
    LoggerService.resetForTesting();
  });
  tearDown(() {
    RetrySignals.instance.resetForTest();
    LoggerService.resetForTesting();
  });

  // 输入栏右侧按钮（Task 7 Composer，2026-07-27）：
  //   - 「添加图片」IconButton 始终存在（Composer 始终渲染）
  //   - 「发送」_SendButton 始终存在，enabled 由 `_hasText || attachedMediaId != null` 决定
  //   - 「+」按钮在 isPickingImage 时禁用
  //
  // 旧的 _buildStopBar + _buildSupplementBar + _buildErrorBar 5 个手写 bar
  // 已合并为 AgentStatusStrip（selectStatus 优先级: error > retry > supplement > running）。
  // running/supplement/retry 三种运行态右侧带「停止」按钮（onStop -> ScenarioSession.cancel）。
  group('AgentChatDialog Composer 输入栏按钮 + StatusStrip', () {
    testWidgets('完全空时「+」按钮可点击，发送按钮 disabled', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final attachBtn = _findIconButtonByTooltip(tester, '添加图片');
      expect(attachBtn, isNotNull, reason: '空状态应显示 + 添加图片按钮');
      expect(attachBtn!.onPressed, isNotNull, reason: '非上传中 + 按钮应可点击');
      // 发送按钮也存在但 disabled（_hasText=false 且 attachedMediaId=null）
      final sendBtn = _findIconButtonByTooltip(tester, '发送');
      expect(sendBtn, isNotNull, reason: 'Composer 始终渲染发送按钮');
      expect(sendBtn!.onPressed, isNull, reason: '空文本/无图时发送按钮 disabled');
    });

    testWidgets('输入文本后发送按钮 enabled', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.enterText(find.byType(TextField), '帮我生成插图');
      await tester.pumpAndSettle();

      final sendBtn = _findIconButtonByTooltip(tester, '发送');
      expect(sendBtn, isNotNull, reason: '有文本时发送按钮 enabled');
      expect(sendBtn!.onPressed, isNotNull, reason: '有文本时发送按钮应可点击');
      // 「添加图片」按钮仍然存在（Composer 始终渲染，停止条件由 isPickingImage 决定）
      expect(_findIconButtonByTooltip(tester, '添加图片'), isNotNull);
    });

    testWidgets('LLM 运行时无错误/重试/补充时 StatusStrip 渲染 running 条 + 停止按钮',
        (tester) async {
      await tester.pumpWidget(
        _wrap(state: const AgentChatState(
          isLoading: true,
          supplementaryCount: 0,
        )),
      );
      await tester.pump();

      // 普通运行态（running 兜底）：StatusStrip 渲染「正在生成…」+「停止」按钮
      expect(find.text('正在生成…'), findsOneWidget,
          reason: 'running 态应渲染「正在生成…」文案');
      expect(find.text('停止'), findsOneWidget,
          reason: 'running 态 StatusStrip 应带「停止」按钮');

      // 输入栏 Composer 仍然渲染（添加图片 + 发送）
      expect(_findIconButtonByTooltip(tester, '添加图片'), isNotNull);
      expect(_findIconButtonByTooltip(tester, '发送'), isNotNull);
    });

    testWidgets('运行中输入文字后发送按钮仍 enabled（composer A 方案补充消息）',
        (tester) async {
      await tester.pumpWidget(
        _wrap(state: const AgentChatState(isLoading: true)),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), '排队等待的消息');
      await tester.pump();

      // A 方案：运行中点 send = 补充消息（Composer _SendButton enabled）
      final sendBtn = _findIconButtonByTooltip(tester, '发送');
      expect(sendBtn, isNotNull);
      expect(sendBtn!.onPressed, isNotNull,
          reason: '运行中有文本时发送按钮 enabled（补充消息）');
    });

    testWidgets('运行中 + 补充计数 > 0 时，StatusStrip 显示 supplement 条目',
        (tester) async {
      await tester.pumpWidget(
        _wrap(state: const AgentChatState(
          isLoading: true,
          supplementaryCount: 3,
        )),
      );
      await tester.pump();

      // StatusStrip 显示「已补充 3 条消息」+ detail「将在下一轮处理」
      expect(find.textContaining('已补充 3 条消息'), findsOneWidget,
          reason: 'AgentStatusStrip 应显示 supplement 文案');
      expect(find.textContaining('下一轮'), findsOneWidget,
          reason: 'detail 行应包含「下一轮」说明');

      // supplement 也是运行态，带停止按钮
      expect(find.text('停止'), findsOneWidget);
    });

    testWidgets('运行中文本框可输入（enabled=true）', (tester) async {
      await tester.pumpWidget(
        _wrap(state: const AgentChatState(isLoading: true)),
      );
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));
      // TextField 未显式设 enabled → 默认为 true（nullable → null → enabled）
      expect(textField.enabled != false, isTrue,
          reason: '运行中输入框应仍可输入（用于排队下一条消息）');
    });
  });
}
/// AgentChatDialog 与 context compaction UI 集成测试
///
/// 覆盖：
/// 1. itemBuilder 在 AgentChatRole.marker 上渲染 CompactionMarkerCard。
/// 2. agentEventsProvider emit CompactionEvent 时弹 SnackBar。
///
/// 关键背景：NovelAgentService.events 是 broadcast Stream，不是 Riverpod provider。
/// dialog 通过 StreamProvider of AgentEvent (agentEventsProvider) 监听，
/// 测试通过 override agentEventsProvider 注入受控流。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/agent_events_provider.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_dialog.dart';
import 'package:novel_app/widgets/agent_chat/agent_message_bubble.dart';
import 'package:novel_app/widgets/agent_chat/compaction_marker_card.dart';

/// 安全 overrides 包装：避免 ScenarioSessionsNotifier 跨 provider 写入告警。
/// 同时 override agentEventsProvider 注入受控 broadcast stream。
class _StreamHarness {
  final StreamController<AgentEvent> controller =
      StreamController<AgentEvent>.broadcast();
  Stream<AgentEvent> get stream => controller.stream;
}

Widget _wrap({
  required AgentChatState chatState,
  required _StreamHarness harness,
}) {
  return ProviderScope(
    overrides: [
      currentChatStateProvider.overrideWithValue(chatState),
      currentSessionProvider.overrideWithValue(null),
      agentEventsProvider.overrideWith((ref) => harness.stream),
    ],
    child: const MaterialApp(
      home: Scaffold(body: AgentChatDialog()),
    ),
  );
}

AgentChatMessage _markerMessage() {
  return AgentChatMessage.compactionMarker(
    const CompactionMarkerSegment(
      droppedMessageCount: 4,
      keptMessageCount: 6,
      removedChars: 12345,
      originalChars: 30000,
      compactedChars: 17655,
    ),
  );
}

CompactionEvent _sampleCompactionEvent() {
  return const CompactionEvent(
    removedChars: 12345,
    originalChars: 30000,
    compactedChars: 17655,
    keptMessageCount: 6,
    droppedMessageCount: 4,
    droppedAgentFromIndex: 0,
    compactionNote: '',
  );
}

void main() {
  group('AgentChatDialog itemBuilder', () {
    testWidgets('AgentChatRole.marker 渲染 CompactionMarkerCard', (tester) async {
      final chatState = AgentChatState(
        messages: [_markerMessage()],
      );
      final harness = _StreamHarness();
      addTearDown(harness.controller.close);

      await tester.pumpWidget(_wrap(chatState: chatState, harness: harness));
      await tester.pump();

      expect(find.byType(CompactionMarkerCard), findsOneWidget);
      // marker 折叠态默认文案
      expect(find.textContaining('丢弃 4 条'), findsOneWidget);
      // marker 不走 AgentMessageBubble（无流式末尾气泡的「思考中」骨架）
      expect(find.byType(AgentMessageBubble), findsNothing);
    });
  });

  group('AgentChatDialog CompactionEvent SnackBar', () {
    testWidgets('CompactionEvent 触发 SnackBar,展示 description',
        (tester) async {
      final chatState = const AgentChatState();
      final harness = _StreamHarness();
      addTearDown(harness.controller.close);

      await tester.pumpWidget(_wrap(chatState: chatState, harness: harness));
      await tester.pump();

      // 触发事件
      harness.controller.add(_sampleCompactionEvent());
      // StreamProvider 异步消费 + ref.listen 跨帧触发 + SnackBar 入场动画，
      // 需多帧 pump 才能稳定找到 SnackBar。
      await tester.pump();
      await tester.pumpAndSettle();

      // CompactionEvent.description 含「已压缩上下文：…」
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('已压缩上下文'),
        findsOneWidget,
      );
    });

    testWidgets('非 CompactionEvent 不弹 SnackBar', (tester) async {
      final chatState = const AgentChatState();
      final harness = _StreamHarness();
      addTearDown(harness.controller.close);

      await tester.pumpWidget(_wrap(chatState: chatState, harness: harness));
      await tester.pump();

      // emit 一个与压缩无关的事件
      harness.controller.add(const TextDeltaEvent('hello'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

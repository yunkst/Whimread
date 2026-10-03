/// ScenarioSession._projectUiMessages 压缩提示投影单元测试（Task 5）
///
/// 覆盖：
/// - 压缩提示 system 消息 → AgentChatRole.marker（含 CompactionMarkerSegment）
/// - 普通 system 消息仍被 continue 跳过
/// - 坏前缀 KV 不崩，降级为 continue
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/core/providers/scenario_session_projection_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/core/providers/scenario_session.dart';

void main() {
  group('ScenarioSession _projectUiMessages compression marker', () {
    test('压缩提示 system 投影为 AgentChatRole.marker', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'system', content:
            '[上下文压缩|droppedCount=23|keptCount=15|removedChars=420000|'
            'originalChars=580000|compactedChars=160000|rewrittenCount=8|timestamp=1706000101]\n后续。'),
        ChatMessage(role: 'user', content: '继续'),
      ];
      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      expect(ui[0].role, AgentChatRole.marker);
      expect(ui[0].segments.single, isA<CompactionMarkerSegment>());
      final seg = ui[0].segments.single as CompactionMarkerSegment;
      expect(seg.droppedMessageCount, 23);
      expect(seg.keptMessageCount, 15);
      expect(seg.removedChars, 420000);
      expect(seg.originalChars, 580000);
      expect(seg.compactedChars, 160000);
      expect(seg.rewrittenCount, 8);
      expect(seg.timestamp, isNotNull);
      expect(ui[1].role, AgentChatRole.user);
    });

    test('普通 system 消息仍被 continue 跳过', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'system', content: 'You are a writer'),
        ChatMessage(role: 'user', content: 'hi'),
      ];
      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      expect(ui, hasLength(1));
      expect(ui.single.role, AgentChatRole.user);
    });

    test('坏前缀 KV 不崩，降级为 continue', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'system', content: '[上下文压缩|broken'),
        ChatMessage(role: 'user', content: 'hi'),
      ];
      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      expect(ui, hasLength(1));
      expect(ui.single.role, AgentChatRole.user);
    });

    test('缺必填字段也降级为 continue', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'system', content:
            '[上下文压缩|droppedCount=5|keptCount=10|removedChars=100|timestamp=1]\n'),
        ChatMessage(role: 'user', content: 'hi'),
      ];
      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      expect(ui, hasLength(1));
      expect(ui.single.role, AgentChatRole.user);
    });

    test('标准 `[上下文压缩` 格式以外的 system 全部 continue', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'system', content: '这是一条普通的系统提示'),
        ChatMessage(role: 'system', content:
            '[上下文压缩|droppedCount=1|keptCount=2|removedChars=3|originalChars=4]\n有效但随后还有'),
        ChatMessage(role: 'user', content: 'hello'),
      ];
      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      // 第一条普通 system → continue；第二条是压缩提示 → marker
      expect(ui, hasLength(2));
      expect(ui[0].role, AgentChatRole.marker);
      expect(ui[1].role, AgentChatRole.user);
    });
  });

  // 回合合并：agent 协议里一个回合会拆成多条 assistant 消息（每轮工具调用
  // 一条 + 各自的 tool 结果），UI 侧必须合并成一条气泡，与流式态结构一致。
  group('ScenarioSession _projectUiMessages 回合合并', () {
    test('同一回合的多条 assistant 消息合并为一条，segments 保持时序', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'user', content: '写第一章'),
        ChatMessage(role: 'assistant', content: '好的，我先查大纲。',
            toolCalls: [ToolCall(id: 'c1', name: 'read_outline', arguments: {})]),
        ChatMessage(role: 'tool', content: '大纲内容', toolCallId: 'c1'),
        ChatMessage(role: 'assistant', content: '大纲读完了，接着创建章节。',
            toolCalls: [ToolCall(id: 'c2', name: 'create_chapter', arguments: {})]),
        ChatMessage(role: 'tool', content: '已创建', toolCallId: 'c2'),
        ChatMessage(role: 'assistant', content: '章节已创建完毕。'),
      ];

      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);

      // 合并前是 5 条 assistant，最终只渲染成 1 个气泡
      expect(ui, hasLength(2));
      expect(ui[0].role, AgentChatRole.user);
      expect(ui[1].role, AgentChatRole.assistant);

      final segs = ui[1].segments;
      expect(segs, hasLength(5));
      expect((segs[0] as TextSegment).content, '好的，我先查大纲。');
      expect((segs[1] as ToolCallSegment).call.id, 'c1');
      expect((segs[2] as TextSegment).content, '大纲读完了，接着创建章节。');
      expect((segs[3] as ToolCallSegment).call.id, 'c2');
      expect((segs[4] as TextSegment).content, '章节已创建完毕。');
      // 工具结果被吸收进工具段，status=completed
      expect((segs[1] as ToolCallSegment).call.status, AgentToolStatus.completed);
      expect((segs[1] as ToolCallSegment).call.result, '大纲内容');
      // 合并后的 content 仍是全部文本拼接（供日志/摘要等复用）
      expect(ui[1].content, '好的，我先查大纲。大纲读完了，接着创建章节。章节已创建完毕。');
    });

    test('合并后的 segments 形状与流式 _pendingSegments 一致', () {
      // 流式时序：文本1 → 工具1 → 文本2 → 工具2 → 文本3
      // finalize 按协议轮次拆成 3 条 assistant，投影后必须还原成同一形状
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'user', content: '继续'),
        ChatMessage(role: 'assistant', content: '文本1',
            toolCalls: [ToolCall(id: 'c1', name: 't', arguments: {})]),
        ChatMessage(role: 'tool', content: 'r1', toolCallId: 'c1'),
        ChatMessage(role: 'assistant', content: '文本2',
            toolCalls: [ToolCall(id: 'c2', name: 't', arguments: {})]),
        ChatMessage(role: 'tool', content: 'r2', toolCallId: 'c2'),
        ChatMessage(role: 'assistant', content: '文本3'),
      ];

      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      final shape = ui[1].segments
          .map((s) => s is TextSegment ? 'text' : 'tool')
          .toList();
      expect(shape, ['text', 'tool', 'text', 'tool', 'text']);
    });

    test('user 消息是回合边界：两个回合各自合并成一条', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'user', content: '第一问'),
        ChatMessage(role: 'assistant', content: '答1',
            toolCalls: [ToolCall(id: 'c1', name: 't', arguments: {})]),
        ChatMessage(role: 'tool', content: 'r1', toolCallId: 'c1'),
        ChatMessage(role: 'assistant', content: '答1收尾'),
        ChatMessage(role: 'user', content: '第二问'),
        ChatMessage(role: 'assistant', content: '答2',
            toolCalls: [ToolCall(id: 'c2', name: 't', arguments: {})]),
        ChatMessage(role: 'tool', content: 'r2', toolCallId: 'c2'),
        ChatMessage(role: 'assistant', content: '答2收尾'),
      ];

      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);

      expect(ui, hasLength(4));
      expect(ui.map((m) => m.role).toList(), [
        AgentChatRole.user,
        AgentChatRole.assistant,
        AgentChatRole.user,
        AgentChatRole.assistant,
      ]);
      expect(ui[1].segments, hasLength(3));
      expect(ui[3].segments, hasLength(3));
    });

    test('压缩 marker 切断合并组，marker 之后的 assistant 另起一条', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'user', content: '继续'),
        ChatMessage(role: 'assistant', content: '压缩前文本'),
        ChatMessage(role: 'system', content:
            '[上下文压缩|droppedCount=1|keptCount=2|removedChars=3|'
            'originalChars=4|compactedChars=5|rewrittenCount=0|timestamp=6]'),
        ChatMessage(role: 'assistant', content: '压缩后文本'),
      ];

      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);

      expect(ui, hasLength(4));
      expect(ui[1].role, AgentChatRole.assistant);
      expect((ui[1].segments.single as TextSegment).content, '压缩前文本');
      expect(ui[2].role, AgentChatRole.marker);
      expect(ui[3].role, AgentChatRole.assistant);
      expect((ui[3].segments.single as TextSegment).content, '压缩后文本');
    });

    test('运行中（无 tool 结果消息）的工具在合并消息里仍是 running', () {
      // partial 落库的 running 工具：投影后不能被误判为 completed
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'user', content: '写'),
        ChatMessage(
            role: 'assistant',
            toolCalls: [
              ToolCall(id: 'c1', name: 't', arguments: {'k': 'v'})
            ]),
      ];

      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      expect(ui, hasLength(2));
      final call = (ui[1].segments.single as ToolCallSegment).call;
      expect(call.status, AgentToolStatus.running);
      expect(call.arguments, {'k': 'v'});
    });

    test('无内容的 assistant 消息不产生空气泡', () {
      final agentMsgs = <ChatMessage>[
        ChatMessage(role: 'user', content: 'hi'),
        ChatMessage(role: 'assistant'),
        ChatMessage(role: 'assistant', content: '实内容'),
      ];

      final ui = ScenarioSession.projectUiMessagesForTest(agentMsgs);
      expect(ui, hasLength(2));
      expect(ui[1].content, '实内容');
    });
  });
}

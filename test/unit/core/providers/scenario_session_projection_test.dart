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
}

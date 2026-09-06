library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/agent_chat_message.dart';

void main() {
  group('AgentChatMessage ImageSegment 序列化', () {
    test('ImageSegment 序列化 round-trip', () {
      final msg = AgentChatMessage(
        role: AgentChatRole.user,
        segments: [
          const ImageSegment(mediaId: 'local_abc123'),
          const TextSegment('把这张图动起来'),
        ],
      );

      final json = msg.toJson();
      final restored = AgentChatMessage.fromJson(json);

      expect(restored.segments.length, 2);
      expect(restored.segments[0], isA<ImageSegment>());
      expect((restored.segments[0] as ImageSegment).mediaId, 'local_abc123');
      expect(restored.segments[1], isA<TextSegment>());
      expect((restored.segments[1] as TextSegment).content, '把这张图动起来');
    });

    test('老数据（纯 text）fromJson 兼容', () {
      final msg = AgentChatMessage.fromJson({
        'role': 'user',
        'content': '你好',
        'timestamp': 1700000000000,
        'segmentsJson': '[{"type":"text","content":"你好"}]',
      });

      expect(msg.segments.length, 1);
      expect(msg.segments[0], isA<TextSegment>());
      expect(msg.content, '你好');
    });

    test('老数据（纯 tool）fromJson 兼容', () {
      final msg = AgentChatMessage.fromJson({
        'role': 'assistant',
        'content': '',
        'timestamp': 1700000000000,
        'segmentsJson':
            '[{"type":"tool","id":"call_1","name":"create_images","arguments":"{\\"prompt\\":\\"cat\\"}","status":"running"}]',
      });

      expect(msg.segments.length, 1);
      expect(msg.segments[0], isA<ToolCallSegment>());
    });
  });

  group('CompactionMarkerSegment', () {
    test('segmentsToJson/FromJson 往返 marker 段', () {
      final seg = const CompactionMarkerSegment(
        droppedMessageCount: 23,
        keptMessageCount: 15,
        removedChars: 420000,
        originalChars: 580000,
        compactedChars: 160000,
        rewrittenCount: 8,
      );
      final msg = AgentChatMessage.compactionMarker(seg);
      final json = AgentChatMessage.segmentsToJson(msg.segments);
      final restored = AgentChatMessage.segmentsFromJson(json);
      expect(restored, hasLength(1));
      final r = restored.single as CompactionMarkerSegment;
      expect(r.droppedMessageCount, 23);
      expect(r.keptMessageCount, 15);
      expect(r.removedChars, 420000);
      expect(r.originalChars, 580000);
      expect(r.compactedChars, 160000);
      expect(r.rewrittenCount, 8);
    });

    test('compactionMarker 工厂 role == AgentChatRole.marker', () {
      final msg = AgentChatMessage.compactionMarker(const CompactionMarkerSegment(
        droppedMessageCount: 1,
        keptMessageCount: 1,
        removedChars: 10,
        originalChars: 20,
        compactedChars: 10,
      ));
      expect(msg.role, AgentChatRole.marker);
    });

    test('旧 DB 无 marker 段不崩', () {
      // 模拟只有 text 段的旧数据
      final json = '[{"type":"text","content":"hi"}]';
      final segs = AgentChatMessage.segmentsFromJson(json);
      expect(segs, hasLength(1));
      expect(segs.single, isA<TextSegment>());
    });
  });
}

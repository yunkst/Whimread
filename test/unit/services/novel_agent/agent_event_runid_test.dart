import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';

void main() {
  group('AgentEvent runId', () {
    test('基类默认 runId 为 null（兼容旧路径）', () {
      const event = TextDeltaEvent('hello');
      expect(event.runId, isNull);
    });

    test('可通过命名参数注入 runId', () {
      const event = TextDeltaEvent('hello', runId: 'sub-abc');
      expect(event.runId, 'sub-abc');
      expect(event.text, 'hello');
    });

    test('ToolCallEndEvent 带 runId 仍可构造', () {
      const event = ToolCallEndEvent('get_outline', 'tc1', 'result',
          runId: 'sub-abc');
      expect(event.runId, 'sub-abc');
      expect(event.success, isTrue);
    });

    test('AgentDoneEvent 默认无参构造仍可用（const 调用兼容）', () {
      const event = AgentDoneEvent();
      expect(event.runId, isNull);
    });

    test('CompactionEvent 带 runId 可构造', () {
      const event = CompactionEvent(
        removedChars: 100,
        originalChars: 200,
        compactedChars: 100,
        keptMessageCount: 2,
        droppedMessageCount: 1,
        droppedAgentFromIndex: 0,
        compactionNote: '[上下文压缩|removedChars=100|originalChars=200|compactedChars=100|rewrittenCount=0|timestamp=0]\n早期 1 条消息已被压缩移除。',
        runId: 'sub-abc',
      );
      expect(event.runId, 'sub-abc');
    });
  });
}

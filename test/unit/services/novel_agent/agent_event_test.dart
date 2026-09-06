import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';

void main() {
  group('CompactionEvent', () {
    test('description 含改写数（rewrittenContent 非空）', () {
      final e = CompactionEvent(
        removedChars: 420000,
        originalChars: 580000,
        compactedChars: 160000,
        keptMessageCount: 15,
        droppedMessageCount: 23,
        droppedAgentFromIndex: 23,
        compactionNote: '[上下文压缩|...]\n后续。',
        rewrittenContent: const [
          (index: 25, newContent: 'x'),
          (index: 26, newContent: 'y'),
        ],
      );
      expect(e.description, contains('改写 2 条'));
      expect(e.description, contains('丢弃 23 条'));
    });

    test('description 无改写时不提改写', () {
      final e = CompactionEvent(
        removedChars: 100,
        originalChars: 200,
        compactedChars: 100,
        keptMessageCount: 1,
        droppedMessageCount: 1,
        droppedAgentFromIndex: 1,
        compactionNote: '[上下文压缩|...]\n后续。',
      );
      expect(e.description, isNot(contains('改写')));
    });

    test('compactedChars / compactionNote 字段被保存', () {
      final e = CompactionEvent(
        removedChars: 100,
        originalChars: 200,
        compactedChars: 90,
        keptMessageCount: 1,
        droppedMessageCount: 1,
        droppedAgentFromIndex: 1,
        compactionNote: '[上下文压缩|foo=1]\n后续。',
      );
      expect(e.compactedChars, 90);
      expect(e.compactionNote, '[上下文压缩|foo=1]\n后续。');
    });
  });
}

/// CompactionNoteParser 单元测试
///
/// 覆盖场景：
/// 1. 全字段解析
/// 2. 缺 rewrittenCount → 0
/// 3. 缺 timestamp → null
/// 4. 缺 compactedChars → 派生 original - removed
/// 5. 坏前缀 → null（普通 system / `[上下文压缩]` 无 KV）
/// 6. 缺必填字段 → null
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/compaction_note_parser.dart';

void main() {
  group('CompactionNoteParser', () {
    const full = '[上下文压缩|droppedCount=23|keptCount=15|removedChars=420000|'
        'originalChars=580000|compactedChars=160000|rewrittenCount=8|timestamp=1706000101]\n'
        '早期 23 条消息已被压缩移除。请基于保留的最近 15 条消息继续对话。';

    test('解析全字段', () {
      final seg = CompactionNoteParser.parse(full)!;
      expect(seg.droppedMessageCount, 23);
      expect(seg.keptMessageCount, 15);
      expect(seg.removedChars, 420000);
      expect(seg.originalChars, 580000);
      expect(seg.compactedChars, 160000);
      expect(seg.rewrittenCount, 8);
      expect(seg.timestamp, isNotNull);
    });

    test('缺 rewrittenCount → 0', () {
      final seg = CompactionNoteParser.parse(
        '[上下文压缩|droppedCount=1|keptCount=1|removedChars=10|'
        'originalChars=20|compactedChars=10]\n后续。')!;
      expect(seg.rewrittenCount, 0);
    });

    test('缺 timestamp → null', () {
      final seg = CompactionNoteParser.parse(
        '[上下文压缩|droppedCount=1|keptCount=1|removedChars=10|'
        'originalChars=20|compactedChars=10]\n后续。')!;
      expect(seg.timestamp, isNull);
    });

    test('缺 compactedChars → 派生 original - removed', () {
      final seg = CompactionNoteParser.parse(
        '[上下文压缩|droppedCount=1|keptCount=1|removedChars=10|'
        'originalChars=30]\n后续。')!;
      expect(seg.compactedChars, 20);
    });

    test('坏前缀 → null', () {
      expect(CompactionNoteParser.parse('普通 system 消息'), isNull);
      expect(CompactionNoteParser.parse('[上下文压缩] 早期...'), isNull); // 注意是 ] 不是 |
    });

    test('缺必填字段 → null', () {
      expect(CompactionNoteParser.parse(
        '[上下文压缩|droppedCount=1|keptCount=1|removedChars=10]\n后续。'), isNull);
    });
  });
}

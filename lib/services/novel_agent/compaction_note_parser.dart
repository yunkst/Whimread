/// 解析 ContextCompactor 注入的压缩提示 system 消息（约定前缀 + KV）。
///
/// 格式见规格 §4.4：
/// [上下文压缩|droppedCount=23|keptCount=15|...|timestamp=1706000101]
/// 自然语言行（给 LLM 看）
///
/// 任何字段缺失/格式异常返回 null（调用方降级为 continue，不渲染 marker）。
library;

import '../../models/agent_chat_message.dart';

class CompactionNoteParser {
  static const _prefix = '[上下文压缩|';

  static CompactionMarkerSegment? parse(String content) {
    if (!content.startsWith(_prefix)) return null;
    final bracketEnd = content.indexOf(']');
    if (bracketEnd < 0) return null;

    final kvBlock = content.substring(_prefix.length, bracketEnd);
    final kv = <String, String>{};
    for (final part in kvBlock.split('|')) {
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      kv[part.substring(0, eq)] = part.substring(eq + 1);
    }

    int? intOrNull(String k) => int.tryParse(kv[k] ?? '');

    final dropped = intOrNull('droppedCount');
    final kept = intOrNull('keptCount');
    final removed = intOrNull('removedChars');
    final original = intOrNull('originalChars');
    // 必填字段缺失 → 降级
    if ([dropped, kept, removed, original].any((v) => v == null)) return null;

    final compacted = intOrNull('compactedChars') ?? (original! - removed!);
    final tsMs = intOrNull('timestamp');

    return CompactionMarkerSegment(
      droppedMessageCount: dropped!,
      keptMessageCount: kept!,
      removedChars: removed!,
      originalChars: original!,
      compactedChars: compacted,
      rewrittenCount: intOrNull('rewrittenCount') ?? 0,
      timestamp: tsMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(tsMs),
    );
  }
}

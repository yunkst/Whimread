/// 任务 8：ScenarioSession `_handleAgentEvent` 的 runId 过滤单元测试。
///
/// 测试目标：纯函数 [shouldMainSessionHandleEvent] 在以下场景的判定：
/// 1. event.runId == null（主 Agent 旧路径事件）→ 处理
/// 2. event.runId == mainSessionId（主 Agent 自身打标）→ 处理
/// 3. event.runId 是本 session 派出的子 Agent run → 不处理（不污染主对话）
/// 4. event.runId 是别 session 的子 Agent run → 不处理
///
/// ScenarioSession 直接构造依赖 Ref + DB，过于重型。本测试聚焦于
/// 已抽出的纯过滤函数，行为契约由函数名 + doc 明确，调用点（_handleAgentEvent 开头）
/// 只负责调用它并据此 return。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';

void main() {
  group('shouldMainSessionHandleEvent', () {
    test('runId == null（主 Agent 旧路径事件）→ 处理', () {
      // 主 Agent 事件流不打 runId（service 不改路径），runId 始终为 null。
      final event = TextDeltaEvent('hello');
      expect(shouldMainSessionHandleEvent(event, '42'), isTrue);
    });

    test('runId == null 时无论 mainSessionId 取值都处理（含 mainSessionId=null）', () {
      final event = AgentDoneEvent();
      expect(shouldMainSessionHandleEvent(event, null), isTrue);
      expect(shouldMainSessionHandleEvent(event, '42'), isTrue);
    });

    test('runId == mainSessionId（主 Agent 自身打标事件）→ 处理', () {
      // 预留：若未来主 Agent 也开始打标 runId（=sessionId.toString()），
      // 主 session 仍要消费这些事件。
      const mainSessionId = '42';
      final event = TextDeltaEvent('main', runId: mainSessionId);
      expect(
        shouldMainSessionHandleEvent(event, mainSessionId),
        isTrue,
      );
    });

    test('runId 属于本 session 派出的子 Agent run → 不处理（避免污染主对话）', () {
      // 子 Agent runId 由 registry 分配，形如 sub-<hash>-N，绝不等于 sessionId。
      const mainSessionId = '42';
      final childEvent = TextDeltaEvent('child output', runId: 'sub-xyz-1');
      expect(
        shouldMainSessionHandleEvent(childEvent, mainSessionId),
        isFalse,
      );
    });

    test('runId 属于别 session 的子 Agent run → 不处理', () {
      // 跨 session 隔离：别 session 派出的子 Agent 事件流也带 runId，
      // 本 session 一概忽略。
      const mainSessionId = '42';
      final otherChildEvent = ToolCallStartEvent(
        'search',
        {'q': 'foo'},
        'tc-9',
        runId: 'sub-other-5',
      );
      expect(
        shouldMainSessionHandleEvent(otherChildEvent, mainSessionId),
        isFalse,
      );
    });

    test('所有事件类型（含 ToolCallEnd / Progress / Done / Error / Compaction）遵守同一过滤规则', () {
      const mainSessionId = '42';
      // 带 runId 但非 mainSessionId 的事件一律拒绝
      expect(
        shouldMainSessionHandleEvent(
          ToolCallEndEvent('search', 'tc-1', 'ok', runId: 'sub-1-1'),
          mainSessionId,
        ),
        isFalse,
      );
      expect(
        shouldMainSessionHandleEvent(
          ToolProgressEvent('tc-1', 100, runId: 'sub-1-1'),
          mainSessionId,
        ),
        isFalse,
      );
      expect(
        shouldMainSessionHandleEvent(
          AgentErrorEvent('boom', runId: 'sub-1-1'),
          mainSessionId,
        ),
        isFalse,
      );
      // runId == null 的事件一律通过（不论类型）
      expect(
        shouldMainSessionHandleEvent(
          const CompactionEvent(
            removedChars: 10,
            originalChars: 100,
            compactedChars: 90,
            keptMessageCount: 5,
            droppedMessageCount: 2,
            droppedAgentFromIndex: 2,
            compactionNote: '[上下文压缩|removedChars=10|originalChars=100|compactedChars=90|rewrittenCount=0|timestamp=0]\n早期 2 条消息已被压缩移除。',
          ),
          mainSessionId,
        ),
        isTrue,
      );
    });
  });
}

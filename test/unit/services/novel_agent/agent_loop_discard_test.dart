/// 【后悔重置】撤回逻辑（truncateRetractableToolCalls）单元测试
///
/// 语义（用户确认）：只撤本回合（最后一条 user 之后）尚未展示的展示类
/// 工具调用（narrate/speak/present_choices）；count 不传 = 全撤，传 N = 撤
/// 最近 N 条；既成事实类工具（update_game_state 等）不撤。
///
/// 运行：
///   flutter test test/unit/services/novel_agent/agent_loop_discard_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_config.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';

ToolCall _call(String id, String name) =>
    ToolCall(id: id, name: name, arguments: const {});

ChatMessage _assistant(List<ToolCall> calls, {String? content}) =>
    ChatMessage(role: 'assistant', content: content, toolCalls: calls);

ChatMessage _tool(String callId) =>
    ChatMessage(role: 'tool', content: '{"ok":true}', toolCallId: callId);

const _retractable = {'narrate', 'speak', 'present_choices'};

void main() {
  group('truncateRetractableToolCalls', () {
    test('count 不传：撤回本回合全部展示类调用（跨多轮）', () {
      final messages = [
        const ChatMessage(role: 'system', content: '系统提示'),
        const ChatMessage(role: 'user', content: '上一回合的玩家输入'),
        _assistant([_call('a1', 'narrate'), _call('a2', 'speak')]),
        _tool('a1'),
        _tool('a2'),
        const ChatMessage(role: 'user', content: '本回合玩家输入'),
        _assistant([_call('b1', 'narrate')]),
        _tool('b1'),
        _assistant([_call('b2', 'speak')]),
        _tool('b2'),
      ];

      final removed = truncateRetractableToolCalls(messages, _retractable);

      expect(removed, ['b1', 'b2'], reason: '时间序返回，且只撤本回合');
      expect(messages, hasLength(6),
          reason: '本回合两条 assistant 被剔空整条移除（各带其 tool 消息）；'
              'system+上回合 4 条原样在列');
      // 上一回合内容原样保留
      expect(messages[1].content, '上一回合的玩家输入');
      expect((messages[2].toolCalls ?? []).map((c) => c.id), ['a1', 'a2']);
      expect(messages[3].toolCallId, 'a1');
      expect(messages[4].toolCallId, 'a2');
    });

    test('count=1：只撤本回合最近一条', () {
      final messages = [
        const ChatMessage(role: 'user', content: '本回合输入'),
        _assistant([_call('b1', 'narrate')]),
        _tool('b1'),
        _assistant([_call('b2', 'speak'), _call('b3', 'present_choices')]),
        _tool('b2'),
        _tool('b3'),
      ];

      final removed = truncateRetractableToolCalls(messages, _retractable,
          count: 1);

      expect(removed, ['b3']);
      // b2 所在 assistant 保留（还有未被撤的调用），b3 的 tool 消息移除
      expect((messages[3].toolCalls ?? []).map((c) => c.id), ['b2']);
      expect(messages.map((m) => m.toolCallId).where((id) => id != null),
          ['b1', 'b2']);
    });

    test('既成事实类工具（update_game_state）不撤，assistant↔tool 配对完好',
        () {
      final messages = [
        const ChatMessage(role: 'user', content: '本回合输入'),
        _assistant([
          _call('s1', 'update_game_state'),
          _call('n1', 'narrate'),
        ]),
        _tool('s1'),
        _tool('n1'),
      ];

      final removed = truncateRetractableToolCalls(messages, _retractable);

      expect(removed, ['n1']);
      expect(messages, hasLength(3));
      expect((messages[1].toolCalls ?? []).map((c) => c.id), ['s1']);
      expect(messages[2].toolCallId, 's1');
    });

    test('撤回范围不越过最后一条 user（上一回合的草稿原样保留）', () {
      final messages = [
        const ChatMessage(role: 'user', content: '上一回合输入'),
        _assistant([_call('old1', 'narrate')]),
        _tool('old1'),
        const ChatMessage(role: 'user', content: '本回合输入'),
        _assistant([_call('new1', 'narrate')]),
        _tool('new1'),
      ];

      final removed = truncateRetractableToolCalls(messages, _retractable);

      expect(removed, ['new1']);
      expect((messages[1].toolCalls ?? []).map((c) => c.id), ['old1']);
    });

    test('count 超过实际可撤条数 → 等于全撤', () {
      final messages = [
        const ChatMessage(role: 'user', content: '本回合输入'),
        _assistant([_call('b1', 'narrate')]),
        _tool('b1'),
      ];
      final removed =
          truncateRetractableToolCalls(messages, _retractable, count: 5);
      expect(removed, ['b1']);
      expect(messages, hasLength(1));
    });

    test('没有可撤内容（只有状态类调用）→ 返回空且消息链不变', () {
      final messages = [
        const ChatMessage(role: 'user', content: '本回合输入'),
        _assistant([_call('s1', 'update_game_state')]),
        _tool('s1'),
      ];
      final snapshot = List<ChatMessage>.from(messages);
      final removed = truncateRetractableToolCalls(messages, _retractable);
      expect(removed, isEmpty);
      expect(messages, snapshot);
    });

    test('无 user 消息（纯系统首轮）→ 空操作', () {
      final messages = [
        const ChatMessage(role: 'system', content: '系统提示'),
        _assistant([_call('a1', 'narrate')]),
        _tool('a1'),
      ];
      expect(truncateRetractableToolCalls(messages, _retractable), isEmpty);
      expect(messages, hasLength(3));
    });

    test('原位变更：保持同一 List 对象（loop 内闭包捕获的 messages）', () {
      final messages = [
        const ChatMessage(role: 'user', content: '本回合输入'),
        _assistant([_call('b1', 'narrate')]),
        _tool('b1'),
      ];
      final sameList = messages;
      truncateRetractableToolCalls(messages, _retractable);
      expect(identical(sameList, messages), isTrue);
      expect(messages, hasLength(1), reason: '内容已原位剔除');
    });

    test('discard 自身所在 assistant 保留：撤到只剩后悔重置调用', () {
      final messages = [
        const ChatMessage(role: 'user', content: '本回合输入'),
        _assistant([
          _call('n1', 'narrate'),
          _call('d1', kDiscardOutputToolName),
        ]),
        _tool('n1'),
        _tool('d1'),
      ];
      final removed = truncateRetractableToolCalls(messages, _retractable);
      expect(removed, ['n1']);
      expect((messages[1].toolCalls ?? []).map((c) => c.id), ['d1']);
      expect(messages[1].toolCalls!.single.name, kDiscardOutputToolName,
          reason: '后悔重置调用本身保留在链上（LLM 知道自己撤回了）');
      expect(messages[2].toolCallId, 'd1');
    });
  });
}

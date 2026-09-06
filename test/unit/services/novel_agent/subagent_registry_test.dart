import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/subagent_registry.dart';
import 'package:novel_app/services/novel_agent/subagent_run.dart';

void main() {
  group('SubagentRegistry', () {
    test('create 后可按 (session, runId) 查到', () {
      final reg = SubagentRegistry();
      final run = reg.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const ['get_outline'],
      );
      expect(run.runId, isNotEmpty);
      expect(reg.get('s1', run.runId), same(run));
    });

    test('create 传 toolCallId 后可按 toolCallId 反查', () {
      final reg = SubagentRegistry();
      final run = reg.create(
        parentSessionId: 's1',
        task: 't',
        allowedTools: const ['get_outline'],
        toolCallId: 'tc42',
      );
      expect(reg.getByToolCallId('s1', 'tc42'), same(run));
      expect(reg.getByToolCallId('s1', 'other'), isNull);
      expect(reg.getByToolCallId('s2', 'tc42'), isNull); // 跨 session 不可见
    });

    test('不同 session 的 run 互不可见', () {
      final reg = SubagentRegistry();
      final r1 = reg.create(parentSessionId: 's1', task: 't', allowedTools: const []);
      reg.create(parentSessionId: 's2', task: 't', allowedTools: const []);
      expect(reg.get('s2', r1.runId), isNull);
    });

    test('listForSession 只返回该 session 的 run', () {
      final reg = SubagentRegistry();
      reg.create(parentSessionId: 's1', task: 'a', allowedTools: const []);
      reg.create(parentSessionId: 's1', task: 'b', allowedTools: const []);
      reg.create(parentSessionId: 's2', task: 'c', allowedTools: const []);
      expect(reg.listForSession('s1').length, 2);
      expect(reg.listForSession('s2').length, 1);
    });

    test('countActiveBySession 统计 running+pending', () {
      final reg = SubagentRegistry();
      final r1 = reg.create(parentSessionId: 's1', task: 't', allowedTools: const []);
      r1.state = SubagentRunState.running;
      final r2 = reg.create(parentSessionId: 's1', task: 't', allowedTools: const []);
      r2.state = SubagentRunState.pending; // 排队
      final r3 = reg.create(parentSessionId: 's1', task: 't', allowedTools: const []);
      r3.state = SubagentRunState.completed; // 终态不计
      expect(reg.countActiveBySession('s1'), 2);
    });

    test('remove 删除指定 run', () {
      final reg = SubagentRegistry();
      final r = reg.create(parentSessionId: 's1', task: 't', allowedTools: const []);
      reg.remove('s1', r.runId);
      expect(reg.get('s1', r.runId), isNull);
    });

    test('clearForSession 清空该 session 全部 run', () {
      final reg = SubagentRegistry();
      reg.create(parentSessionId: 's1', task: 't', allowedTools: const []);
      reg.create(parentSessionId: 's1', task: 't', allowedTools: const []);
      reg.clearForSession('s1');
      expect(reg.listForSession('s1'), isEmpty);
    });

    test('pruneForSession 保留最近 N 个终态 run，清掉更早的', () {
      final reg = SubagentRegistry();
      for (var i = 0; i < 25; i++) {
        final r = reg.create(parentSessionId: 's1', task: 't$i', allowedTools: const []);
        r.state = SubagentRunState.completed;
      }
      reg.pruneForSession('s1', keep: 20);
      expect(reg.listForSession('s1').length, 20);
    });
  });
}

/// SubagentRunner.dispatch 接线 pruneForSession 的回归测试（spec §5.3）
///
/// 覆盖：
/// - 每注册新 run 后按 session 清理超额终态 run（保留最近 20 个供回看）
/// - 非终态 run（pending）绝不被清理——并发上限计数与 cancelAllForSession 依赖它们
///
/// 运行:
///   flutter test test/unit/services/novel_agent/subagent_runner_prune_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/subagent_registry.dart';
import 'package:novel_app/services/novel_agent/subagent_run.dart';
import 'package:novel_app/services/novel_agent/subagent_runner.dart';

void main() {
  group('SubagentRunner dispatch 接线 pruneForSession（spec §5.3）', () {
    test('连续 dispatch 25 个 run 后，session 内只保留最近 20 个终态 run', () async {
      final registry = SubagentRegistry();
      // LLM 工厂直接抛错：每个 dispatch 快速失败成终态（failed）run，
      // 不依赖真实 LLM，专注验证 prune 接线本身。
      final runner = SubagentRunner.forTest(
        registry: registry,
        llmProviderFactory: (scenarioId) =>
            throw StateError('测试用：不需要真实 LLM'),
      );

      for (var i = 0; i < 25; i++) {
        await runner.dispatchForTest(
          parentSessionId: 's1',
          task: 't$i',
          allowedTools: const ['get_outline'],
        );
      }

      expect(
        registry.listForSession('s1').length,
        SubagentRegistry.historyKeepLimit,
        reason: '超出 20 个的终态 run 应在每次注册新 run 时被清理',
      );
    });

    test('非终态 run 不被清理（并发计数与级联取消依赖它们）', () async {
      final registry = SubagentRegistry();
      final runner = SubagentRunner.forTest(
        registry: registry,
        llmProviderFactory: (scenarioId) =>
            throw StateError('测试用：不需要真实 LLM'),
      );

      // 最早创建一个 pending run（模拟排队中），其后 25 个快速失败的终态 run
      final pending = registry.create(
        parentSessionId: 's1',
        task: 'live',
        allowedTools: const ['get_outline'],
        toolCallId: 'tc-live',
      );
      for (var i = 0; i < 25; i++) {
        await runner.dispatchForTest(
          parentSessionId: 's1',
          task: 't$i',
          allowedTools: const ['get_outline'],
        );
      }

      // 超额清理只动终态 run：最老的 pending 必须原样保留
      expect(registry.get('s1', pending.runId), same(pending));
      expect(pending.state, SubagentRunState.pending);
      expect(registry.countActiveBySession('s1'), 1);
      // 20 个终态 + 1 个非终态
      expect(registry.listForSession('s1').length, 21);
    });
  });
}

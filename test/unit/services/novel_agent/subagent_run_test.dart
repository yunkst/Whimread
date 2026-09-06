import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/subagent_run.dart';

void main() {
  group('SubagentRun', () {
    test('初始状态为 pending', () {
      final run = SubagentRun(
        runId: 'r1',
        parentSessionId: 's1',
        task: '梳理前 30 章人物关系',
        allowedTools: const ['get_outline', 'read_chapter'],
        toolCallId: 'tc1',
      );
      expect(run.state, SubagentRunState.pending);
      expect(run.finalSummary, isNull);
      expect(run.errorMessage, isNull);
      expect(run.isTerminal, isFalse);
    });

    test('completed/failed/cancelled 为终态', () {
      for (final s in [
        SubagentRunState.completed,
        SubagentRunState.failed,
        SubagentRunState.cancelled,
      ]) {
        final run = SubagentRun(
            runId: 'r', parentSessionId: 's', task: 't', allowedTools: const [], toolCallId: 'tc');
        run.state = s;
        expect(run.isTerminal, isTrue, reason: '$s 应为终态');
      }
    });

    test('progressSummary 运行中取最后思考片段', () {
      final run = SubagentRun(
          runId: 'r', parentSessionId: 's', task: 't', allowedTools: const [], toolCallId: 'tc');
      run.state = SubagentRunState.running;
      run.lastThought = '正在分析第 12 章的对话';
      run.lastToolName = 'read_chapter';
      final s = run.progressSummary;
      expect(s.contains('分析第 12 章'), isTrue);
      expect(s.contains('read_chapter'), isTrue);
    });

    test('progressSummary 完成取 finalSummary 首段', () {
      final run = SubagentRun(
          runId: 'r', parentSessionId: 's', task: 't', allowedTools: const [], toolCallId: 'tc');
      run.state = SubagentRunState.completed;
      run.finalSummary = '## 最终结论\n发现 5 个主要人物。';
      expect(run.progressSummary.contains('最终结论'), isTrue);
    });

    test('progressSummary 失败取 errorMessage', () {
      final run = SubagentRun(
          runId: 'r', parentSessionId: 's', task: 't', allowedTools: const [], toolCallId: 'tc');
      run.state = SubagentRunState.failed;
      run.errorMessage = 'LLM 配置缺失';
      expect(run.progressSummary.contains('LLM 配置缺失'), isTrue);
    });

    test('progressSummary pending 返回排队中', () {
      final run = SubagentRun(
          runId: 'r', parentSessionId: 's', task: 't', allowedTools: const [], toolCallId: 'tc');
      expect(run.state, SubagentRunState.pending);
      expect(run.progressSummary, '排队中…');
    });

    test('progressSummary cancelled 返回已取消', () {
      final run = SubagentRun(
          runId: 'r', parentSessionId: 's', task: 't', allowedTools: const [], toolCallId: 'tc');
      run.state = SubagentRunState.cancelled;
      expect(run.progressSummary, '已取消');
    });
  });

  group('done 完成信号', () {
    SubagentRun newRun() => SubagentRun(
        runId: 'r',
        parentSessionId: 's',
        task: 't',
        allowedTools: const [],
        toolCallId: 'tc');

    test('初始 done 未完成', () {
      final run = newRun();
      expect(run.isDone, isFalse);
    });

    test('completeDone 后 done 完成且 isDone 为 true', () async {
      final run = newRun();
      run.completeDone();
      await run.done;
      expect(run.isDone, isTrue);
    });

    test('completeDone 幂等，重复调用不抛', () {
      final run = newRun();
      run.completeDone();
      run.completeDone();
      run.completeDone();
      expect(run.isDone, isTrue);
    });
  });
}
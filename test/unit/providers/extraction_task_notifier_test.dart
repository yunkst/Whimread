/// ExtractionTaskNotifier 单元测试
///
/// 覆盖：
/// - 状态机正确性：start/toolStart/toolEnd/setPhase/incrementRound/complete/fail
/// - copyWith 正确性
/// - isIdle / isRunning getter
/// - reset 清除状态
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/providers/extraction_task_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExtractionTaskNotifier notifier;

  setUp(() {
    notifier = ExtractionTaskNotifier();
  });

  // ================================================================
  // 初始状态
  // ================================================================
  group('初始状态', () {
    test('默认状态为 idle，roundCount=0', () {
      expect(notifier.state.phase, ExtractionPhase.idle);
      expect(notifier.state.domain, isNull);
      expect(notifier.state.currentTool, isNull);
      expect(notifier.state.roundCount, 0);
      expect(notifier.state.error, isNull);
      expect(notifier.state.startedAt, isNull);
      expect(notifier.state.completedAt, isNull);
    });

    test('isIdle == true，isRunning == false', () {
      expect(notifier.isIdle, isTrue);
      expect(notifier.isRunning, isFalse);
    });
  });

  // ================================================================
  // 状态机：start → toolStart → toolEnd → complete
  // ================================================================
  group('状态机正确性', () {
    test('start 启动任务，phase=analyzing，startedAt 设置', () {
      final before = DateTime.now();
      notifier.start('www.example.com');
      final after = DateTime.now();

      expect(notifier.state.phase, ExtractionPhase.analyzing);
      expect(notifier.state.domain, 'www.example.com');
      expect(notifier.state.startedAt, isNotNull);
      expect(
        notifier.state.startedAt!.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch),
      );
      expect(
        notifier.state.startedAt!.millisecondsSinceEpoch,
        lessThanOrEqualTo(after.millisecondsSinceEpoch),
      );
    });

    test('setPhase 切换阶段', () {
      notifier.start('www.example.com');
      notifier.setPhase(ExtractionPhase.executing, toolName: 'execute_js');
      expect(notifier.state.phase, ExtractionPhase.executing);
      expect(notifier.state.currentTool, 'execute_js');
    });

    test('toolStart/toolEnd 跟踪工具名', () {
      notifier.start('www.example.com');
      notifier.toolStart('execute_js');
      expect(notifier.state.currentTool, 'execute_js');

      notifier.toolEnd();
      expect(notifier.state.currentTool, isNull);
    });

    test('incrementRound 增加轮数', () {
      notifier.start('www.example.com');
      expect(notifier.state.roundCount, 0);

      notifier.incrementRound();
      notifier.incrementRound();
      notifier.incrementRound();
      expect(notifier.state.roundCount, 3);
    });

    test('complete 结束任务，phase=done，completedAt 设置', () {
      notifier.start('www.example.com');
      notifier.complete();

      expect(notifier.state.phase, ExtractionPhase.done);
      expect(notifier.state.completedAt, isNotNull);
      expect(notifier.isRunning, isFalse);
    });

    test('fail 标记错误，phase=error，error 设置', () {
      notifier.start('www.example.com');
      notifier.fail('脚本执行失败');

      expect(notifier.state.phase, ExtractionPhase.error);
      expect(notifier.state.error, '脚本执行失败');
      expect(notifier.state.completedAt, isNotNull);
      expect(notifier.isRunning, isFalse);
    });
  });

  // ================================================================
  // isRunning 状态判断
  // ================================================================
  group('isRunning 状态判断', () {
    test('analyzing 阶段 → isRunning = true', () {
      notifier.start('www.example.com');
      expect(notifier.isRunning, isTrue);
    });

    test('executing 阶段 → isRunning = true', () {
      notifier.start('www.example.com');
      notifier.setPhase(ExtractionPhase.executing);
      expect(notifier.isRunning, isTrue);
    });

    test('saving 阶段 → isRunning = true', () {
      notifier.start('www.example.com');
      notifier.setPhase(ExtractionPhase.saving);
      expect(notifier.isRunning, isTrue);
    });

    test('done 阶段 → isRunning = false', () {
      notifier.start('www.example.com');
      notifier.complete();
      expect(notifier.isRunning, isFalse);
    });

    test('error 阶段 → isRunning = false', () {
      notifier.start('www.example.com');
      notifier.fail('oops');
      expect(notifier.isRunning, isFalse);
    });

    test('idle 阶段 → isRunning = false', () {
      expect(notifier.isRunning, isFalse);
    });
  });

  // ================================================================
  // reset
  // ================================================================
  group('reset', () {
    test('reset 清除所有状态', () {
      notifier.start('www.example.com');
      notifier.setPhase(ExtractionPhase.executing, toolName: 'execute_js');
      notifier.incrementRound();

      notifier.reset();

      expect(notifier.state.phase, ExtractionPhase.idle);
      expect(notifier.state.domain, isNull);
      expect(notifier.state.currentTool, isNull);
      expect(notifier.state.roundCount, 0);
    });
  });

  // ================================================================
  // ExtractionTaskState.copyWith
  // ================================================================
  group('ExtractionTaskState.copyWith', () {
    test('不传任何参数 → 返回等价对象', () {
      const state = ExtractionTaskState(
        phase: ExtractionPhase.analyzing,
        domain: 'test.com',
        currentTool: 'get_page_info',
        roundCount: 2,
      );
      final copy = state.copyWith();
      expect(copy.phase, ExtractionPhase.analyzing);
      expect(copy.domain, 'test.com');
      expect(copy.currentTool, 'get_page_info');
      expect(copy.roundCount, 2);
    });

    test('传 phase → 更新 phase，其他保持', () {
      const state = ExtractionTaskState(
        phase: ExtractionPhase.idle,
        domain: 'test.com',
      );
      final updated = state.copyWith(phase: ExtractionPhase.executing);
      expect(updated.phase, ExtractionPhase.executing);
      expect(updated.domain, 'test.com');
    });

    test('clearError: true → error 被置为 null', () {
      const state = ExtractionTaskState(error: 'some error');
      final updated = state.copyWith(clearError: true);
      expect(updated.error, isNull);
    });

    test('clearDomain: true → domain 被置为 null', () {
      const state = ExtractionTaskState(domain: 'test.com');
      final updated = state.copyWith(clearDomain: true);
      expect(updated.domain, isNull);
    });
  });
}

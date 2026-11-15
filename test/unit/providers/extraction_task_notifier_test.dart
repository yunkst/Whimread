/// ExtractionTaskNotifier 单元测试
///
/// 覆盖（与生产写入侧对齐：start/setPhase/toolStart/toolEnd）：
/// - 状态机正确性
/// - copyWith 正确性
/// - isIdle / isRunning getter
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
    test('默认状态为 idle', () {
      expect(notifier.state.phase, ExtractionPhase.idle);
      expect(notifier.state.domain, isNull);
      expect(notifier.state.currentTool, isNull);
      expect(notifier.state.startedAt, isNull);
    });

    test('isIdle == true，isRunning == false', () {
      expect(notifier.isIdle, isTrue);
      expect(notifier.isRunning, isFalse);
    });
  });

  // ================================================================
  // 状态机：start → toolStart → toolEnd
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

    test('idle 阶段 → isRunning = false', () {
      expect(notifier.isRunning, isFalse);
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
      );
      final copy = state.copyWith();
      expect(copy.phase, ExtractionPhase.analyzing);
      expect(copy.domain, 'test.com');
      expect(copy.currentTool, 'get_page_info');
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

    test('clearDomain: true → domain 被置为 null', () {
      const state = ExtractionTaskState(domain: 'test.com');
      final updated = state.copyWith(clearDomain: true);
      expect(updated.domain, isNull);
    });
  });
}

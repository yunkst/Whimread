/// StartupPromptsRunner 启动期副作用编排测试
///
/// 验证约束:
/// - 阶段按声明顺序各执行一次
/// - 阶段抛异常只跳过自身
/// - mounted 门控在每阶段执行前判定,false 时放弃剩余全部阶段
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/startup_prompts_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StartupPromptsRunner 阶段解耦', () {
    test('两个阶段按声明顺序各执行一次', () async {
      final executed = <String>[];

      final runner = StartupPromptsRunner(
        canContinue: () => true,
        crashReportStage: () async => executed.add('crash'),
        updateCheckStage: () async => executed.add('update'),
      );

      await runner.run();

      expect(executed, ['crash', 'update']);
    });

    test('阶段抛异常只跳过自身,后续阶段继续', () async {
      final executed = <String>[];

      Future<void> throwingStage() async {
        throw StateError('阶段内部异常');
      }

      final runner = StartupPromptsRunner(
        canContinue: () => true,
        crashReportStage: throwingStage,
        updateCheckStage: () async => executed.add('update'),
      );

      await runner.run();

      expect(executed, ['update'],
          reason: 'crash 上报异常时,启动期更新检查仍必须执行');
    });

    test('canContinue 为 false 时放弃全部阶段', () async {
      var gateCalls = 0;

      final runner = StartupPromptsRunner(
        canContinue: () {
          gateCalls++;
          return false;
        },
        crashReportStage: () async => fail('不应执行'),
        updateCheckStage: () async => fail('不应执行'),
      );

      await runner.run();

      expect(gateCalls, 1, reason: '首个阶段前判定一次即放弃,无需重复判定');
    });

    test('canContinue 中途变 false 时放弃剩余阶段', () async {
      final executed = <String>[];

      final runner = StartupPromptsRunner(
        canContinue: () => executed.length < 1,
        crashReportStage: () async => executed.add('crash'),
        updateCheckStage: () async => executed.add('update'),
      );

      await runner.run();

      expect(executed, ['crash'],
          reason: '模拟 HomePage 被销毁:后续阶段不得再拿失效 context 执行');
    });
  });
}

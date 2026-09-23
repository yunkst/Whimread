/// StartupPromptsRunner 启动期副作用编排测试
///
/// 背景(用户反馈 #5):旧实现把 crash 上报 → star 引导 → 静默检查更新
/// 串在一个 async 函数里,star 引导「不满足弹窗门槛」时直接 return,
/// 连带跳过了启动期更新检查,更新弹窗只在 star 弹窗恰好弹出的启动才可能
/// 出现。抽出编排器后回归验证:
/// - 前序阶段「不适用即提前返回」不得短路后续阶段
/// - 阶段抛异常只跳过自身
/// - mounted 门控在每阶段执行前判定,false 时放弃剩余全部阶段
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/startup_prompts_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StartupPromptsRunner 阶段解耦', () {
    test('star 阶段提前返回不短路更新检查(反馈 #5 回归)', () async {
      final executed = <String>[];

      Future<void> starStageNotApplicable() async {
        // 模拟 shouldShow() == false:本阶段不做事直接结束
        executed.add('star');
      }

      final runner = StartupPromptsRunner(
        canContinue: () => true,
        crashReportStage: () async {},
        starPromptStage: starStageNotApplicable,
        updateCheckStage: () async => executed.add('update'),
      );

      await runner.run();

      expect(executed, contains('update'),
          reason: 'star 引导不弹窗时,启动期更新检查仍必须执行');
    });

    test('三个阶段按声明顺序各执行一次', () async {
      final executed = <String>[];

      final runner = StartupPromptsRunner(
        canContinue: () => true,
        crashReportStage: () async => executed.add('crash'),
        starPromptStage: () async => executed.add('star'),
        updateCheckStage: () async => executed.add('update'),
      );

      await runner.run();

      expect(executed, ['crash', 'star', 'update']);
    });

    test('阶段抛异常只跳过自身,后续阶段继续', () async {
      final executed = <String>[];

      Future<void> throwingStage() async {
        throw StateError('阶段内部异常');
      }

      final runner = StartupPromptsRunner(
        canContinue: () => true,
        crashReportStage: throwingStage,
        starPromptStage: () async => executed.add('star'),
        updateCheckStage: () async => executed.add('update'),
      );

      await runner.run();

      expect(executed, ['star', 'update']);
    });

    test('canContinue 为 false 时放弃全部阶段', () async {
      var gateCalls = 0;

      final runner = StartupPromptsRunner(
        canContinue: () {
          gateCalls++;
          return false;
        },
        crashReportStage: () async => fail('不应执行'),
        starPromptStage: () async => fail('不应执行'),
        updateCheckStage: () async => fail('不应执行'),
      );

      await runner.run();

      expect(gateCalls, 1, reason: '首个阶段前判定一次即放弃,无需重复判定');
    });

    test('canContinue 中途变 false 时放弃剩余阶段', () async {
      final executed = <String>[];

      final runner = StartupPromptsRunner(
        canContinue: () => executed.length < 2,
        crashReportStage: () async => executed.add('crash'),
        starPromptStage: () async => executed.add('star'),
        updateCheckStage: () async => executed.add('update'),
      );

      await runner.run();

      expect(executed, ['crash', 'star'],
          reason: '模拟 HomePage 被销毁:后续阶段不得再拿失效 context 执行');
    });
  });
}

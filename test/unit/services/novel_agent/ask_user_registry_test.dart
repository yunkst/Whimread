/// AskUserRegistry 单元测试
///
/// 覆盖挂起提问的注册 / 作答 / 批量放行 / 重复作答防护。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/ask_user_registry.dart';

void main() {
  late AskUserRegistry registry;

  PendingAskUser register({
    String scenarioId = 'writing',
    String toolCallId = 'call_1',
    List<String> options = const ['A', 'B'],
  }) {
    return registry.register(
      scenarioId: scenarioId,
      toolCallId: toolCallId,
      question: '选哪个？',
      options: options,
      multiSelect: false,
      allowFreeText: true,
    );
  }

  setUp(() => registry = AskUserRegistry());

  group('register', () {
    test('注册后可取到挂起项且未完成', () {
      final entry = register();
      expect(entry.isCompleted, false);
      expect(registry.pendingCount, 1);
    });

    test('同场景同 toolCallId 重复注册会取消旧项（防键冲突悬挂）', () async {
      final old = register();
      final fresh = register();
      expect(await old.future.then((a) => a.status),
          AskUserAnswerStatus.cancelled,
          reason: '旧挂起项应被放行为 cancelled，否则 executor 会永久挂起');
      expect(fresh.isCompleted, false);
    });
  });

  group('answer', () {
    test('作答后挂起项完成，答案携带 selected + freeText（空白归一为 trim）', () async {
      final entry = register();
      final ok = registry.answer(
        scenarioId: 'writing',
        toolCallId: 'call_1',
        selected: ['A'],
        freeText: '  补充说明  ',
      );
      expect(ok, isTrue);
      final answer = await entry.future;
      expect(answer.isAnswered, isTrue);
      expect(answer.selected, ['A']);
      expect(answer.freeText, '补充说明');
      expect(registry.pendingCount, 0,
          reason: '作答后挂起项应从注册表移除，与 executor 的 finally 幂等');
    });

    test('freeText 全空白归一为 null', () async {
      final entry = register();
      registry.answer(
        scenarioId: 'writing',
        toolCallId: 'call_1',
        freeText: '   ',
      );
      expect((await entry.future).freeText, isNull);
    });

    test('无匹配挂起项返回 false（已答过 / 已取消 / 会话重建）', () {
      expect(
        registry.answer(scenarioId: 'writing', toolCallId: 'nope'),
        isFalse,
      );
    });

    test('重复作答：第二次返回 false', () {
      register();
      expect(registry.answer(scenarioId: 'writing', toolCallId: 'call_1'),
          isTrue);
      expect(registry.answer(scenarioId: 'writing', toolCallId: 'call_1'),
          isFalse);
    });

    test('跨场景 toolCallId 同名不串（键含 scenarioId）', () {
      register(scenarioId: 'writing', toolCallId: 'call_1');
      register(scenarioId: 'other', toolCallId: 'call_1');
      expect(registry.pendingCount, 2);
      expect(
          registry.answer(scenarioId: 'writing', toolCallId: 'call_1'), isTrue);
      expect(registry.pendingCount, 1,
          reason: '另一场景的同 id 挂起项不应受影响');
    });
  });

  group('abortForScenario', () {
    test('批量放行本场景全部挂起项，其余场景不受影响', () async {
      final a = register(toolCallId: 'call_a');
      final b = register(toolCallId: 'call_b');
      final other = register(scenarioId: 'other', toolCallId: 'call_c');

      final count = registry.abortForScenario('writing');
      expect(count, 2);
      expect((await a.future).status, AskUserAnswerStatus.cancelled);
      expect((await b.future).status, AskUserAnswerStatus.cancelled);
      expect(other.isCompleted, isFalse);
      expect(registry.pendingCount, 1);
    });

    test('abort 传 timeout 时按超时语义放行', () async {
      final entry = register();
      registry.abortForScenario('writing',
          status: AskUserAnswerStatus.timeout);
      expect((await entry.future).status, AskUserAnswerStatus.timeout);
    });
  });

  group('remove', () {
    test('executor finally 移除幂等', () {
      register();
      registry.remove('writing', 'call_1');
      registry.remove('writing', 'call_1');
      expect(registry.pendingCount, 0);
    });
  });
}

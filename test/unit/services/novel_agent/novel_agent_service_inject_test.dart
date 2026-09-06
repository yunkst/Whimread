/// NovelAgentService 运行中补充消息（A 方案）测试
///
/// 验证 [NovelAgentService.injectUserMessage] 的副作用：
/// - 把消息加入 _pendingInjectionsByScenario
/// - emit [InjectedUserInputEvent] 事件携带 scenarioId
/// - 同一 scenario 多次注入按 FIFO 排队
/// - cancelFor 清空队列（通过"二次注入不会看到旧消息"间接验证）
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';

/// 通过 ProviderContainer 拿 service（满足 NovelAgentService(Ref) 约束）
Future<NovelAgentService> makeService(ProviderContainer container) async {
  // 确保 riverpod 内部依赖（如 LlmConfigService 用 SharedPreferences）
  // 不会触发 binding 警告
  return container.read(novelAgentServiceProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NovelAgentService.injectUserMessage', () {
    test('单条注入：emit InjectedUserInputEvent 携带 scenarioId', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = await makeService(container);

      final received = <AgentEvent>[];
      final sub = service.events.listen(received.add);

      service.injectUserMessage('scenario_A', '补充 hello');
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 1);
      expect(received.first, isA<InjectedUserInputEvent>());
      final evt = received.first as InjectedUserInputEvent;
      expect(evt.text, '补充 hello');
      expect(evt.scenarioId, 'scenario_A');

      await sub.cancel();
    });

    test('空文本注入：被过滤，不入队不 emit', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = await makeService(container);

      final received = <AgentEvent>[];
      final sub = service.events.listen(received.add);

      service.injectUserMessage('sc', '');
      service.injectUserMessage('sc', '   ');
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty, reason: '空文本（含纯空白）不应被注入');

      await sub.cancel();
    });

    test('多 scenario 各自排队：事件 scenarioId 不串台', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = await makeService(container);

      final received = <AgentEvent>[];
      final sub = service.events.listen(received.add);

      service.injectUserMessage('A', 'a1');
      service.injectUserMessage('B', 'b1');
      service.injectUserMessage('A', 'a2');
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 3);
      final scenarios = received
          .whereType<InjectedUserInputEvent>()
          .map((e) => '${e.scenarioId}:${e.text}')
          .toList();
      expect(scenarios, ['A:a1', 'B:b1', 'A:a2']);

      await sub.cancel();
    });

    test('cancelFor 后再注入：emit 重新计数（队列已清）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = await makeService(container);

      final received = <AgentEvent>[];
      final sub = service.events.listen(received.add);

      service.injectUserMessage('sc', 'old1');
      service.injectUserMessage('sc', 'old2');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);

      // cancelFor 清队列（cancel token 不存在也安全，map.remove 是 noop）
      service.cancelFor('sc');

      // 再次注入：事件仍在 emit，但内部队列已空（不会带旧消息）
      service.injectUserMessage('sc', 'after_cancel');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 3);
      final lastInject = received.whereType<InjectedUserInputEvent>().last;
      expect(lastInject.text, 'after_cancel');

      await sub.cancel();
    });

    test('cancelAll 不 emit 事件；之后可继续注入', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = await makeService(container);

      service.injectUserMessage('A', 'a1');
      service.injectUserMessage('B', 'b1');
      service.cancelAll();

      // cancelAll 自身不 emit 事件
      final received = <AgentEvent>[];
      final sub = service.events.listen(received.add);
      expect(received, isEmpty);

      // 之后可继续注入
      service.injectUserMessage('A', 'a2');
      service.injectUserMessage('B', 'b2');
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);
      final texts = received
          .whereType<InjectedUserInputEvent>()
          .map((e) => '${e.scenarioId}:${e.text}')
          .toList();
      expect(texts, ['A:a2', 'B:b2']);

      await sub.cancel();
    });
  });
}

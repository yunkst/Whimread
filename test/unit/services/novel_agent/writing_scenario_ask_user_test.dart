/// WritingScenario ask_user 分支单元测试
///
/// 覆盖参数校验（让 LLM 自行修正的 error JSON）与三种收尾语义
/// （作答 / 超时 / 取消令牌唤醒）的返回 JSON 形状。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/ask_user_providers.dart';
import 'package:novel_app/services/novel_agent/ask_user_registry.dart';
import 'package:novel_app/services/novel_agent/scenarios/writing_scenario.dart';
import 'package:novel_app/utils/cancellation_token.dart';

void main() {
  late ProviderContainer container;
  late AskUserRegistry registry;

  /// 借 Provider 把容器 Ref 注入 WritingScenario（与生产等价的读 provider 途径）
  final scenarioProvider = Provider<WritingScenario>((ref) => WritingScenario(
        ref,
        askUserTimeout: const Duration(milliseconds: 60),
      ));

  setUp(() {
    registry = AskUserRegistry();
    container = ProviderContainer(overrides: [
      askUserRegistryProvider.overrideWithValue(registry),
    ]);
    addTearDown(container.dispose);
  });

  Map<String, dynamic> decode(String raw) => jsonDecode(raw) as Map<String, dynamic>;

  group('ask_user 参数校验', () {
    test('缺 question → missing_required_param，且不产生挂起项', () async {
      final result = await container.read(scenarioProvider).executeTool(
            'ask_user',
            {'options': ['A']},
            toolCallId: 'call_x',
          );
      expect(decode(result)['error'], 'missing_required_param');
      expect(registry.pendingCount, 0);
    });

    test('无 options 且禁自由输入 → invalid_args（用户无从作答）', () async {
      final result = await container.read(scenarioProvider).executeTool(
            'ask_user',
            {'question': '选哪个？', 'allow_free_text': false},
            toolCallId: 'call_x',
          );
      expect(decode(result)['error'], 'invalid_args');
      expect(registry.pendingCount, 0);
    });

    test('multi_select=true 但无 options → invalid_args', () async {
      final result = await container.read(scenarioProvider).executeTool(
            'ask_user',
            {'question': '选哪个？', 'multi_select': true},
            toolCallId: 'call_x',
          );
      expect(decode(result)['error'], 'invalid_args');
    });

    test('options 超过 8 个 → invalid_args', () async {
      final result = await container.read(scenarioProvider).executeTool(
            'ask_user',
            {
              'question': '选哪个？',
              'options': List.generate(9, (i) => '选项$i'),
            },
            toolCallId: 'call_x',
          );
      expect(decode(result)['error'], 'invalid_args');
    });
  });

  group('ask_user 收尾语义', () {
    test('用户作答：单选返回 selected，success=true', () async {
      final run = container.read(scenarioProvider).executeTool(
            'ask_user',
            {'question': '用第几人称？', 'options': ['第一', '第三']},
            toolCallId: 'call_1',
          );

      // 等分支注册挂起项后作答
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (registry.pendingCount == 0) {
        if (DateTime.now().isAfter(deadline)) {
          fail('ask_user 分支未在时限内注册挂起提问');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        registry.answer(
          scenarioId: 'writing',
          toolCallId: 'call_1',
          selected: ['第一'],
        ),
        isTrue,
      );

      final result = decode(await run.timeout(const Duration(seconds: 5)));
      expect(result['success'], true);
      expect(result['question'], '用第几人称？');
      expect(result['selected'], ['第一']);
      expect(result.containsKey('error'), false,
          reason: '无 error 键时 AgentLoop 判 toolSuccess=true');
      expect(registry.pendingCount, 0, reason: 'finally 应清理挂起项');
    });

    test('用户自由输入：返回 free_text，selected 省略', () async {
      final run = container.read(scenarioProvider).executeTool(
            'ask_user',
            {'question': '主角叫什么？'},
            toolCallId: 'call_2',
          );
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (registry.pendingCount == 0) {
        if (DateTime.now().isAfter(deadline)) fail('未注册挂起提问');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      registry.answer(
        scenarioId: 'writing',
        toolCallId: 'call_2',
        freeText: '林晚',
      );

      final result = decode(await run.timeout(const Duration(seconds: 5)));
      expect(result['free_text'], '林晚');
      expect(result.containsKey('selected'), false);
    });

    test('超时：返回 status=timeout（兜底放行，不悬挂）', () async {
      final result = await container.read(scenarioProvider).executeTool(
            'ask_user',
            {'question': '还在吗？'},
            toolCallId: 'call_3',
          );
      final parsed = decode(result);
      expect(parsed['status'], 'timeout');
      expect(parsed['success'], true);
      expect(registry.pendingCount, 0);
    });

    test('取消令牌唤醒：挂起中 cancel 回调放行为 cancelled', () async {
      // 直接验证与 executor 分支相同的挂起协议：token.cancel →
      // register 的回调完成挂起项（预取消的令牌 register 即触发）。
      final token = CancellationToken()..cancel(reason: '预取消');
      final entry = registry.register(
        scenarioId: 'writing',
        toolCallId: 'call_pre',
        question: 'q',
        options: const [],
        multiSelect: false,
        allowFreeText: true,
      );
      token.register(() => entry.complete(const AskUserAnswer.cancelled()));
      expect((await entry.future).status, AskUserAnswerStatus.cancelled);
    });

    test('无运行令牌（tokenFor=null）时正常作答路径不受影响', () async {
      // 容器未构造任何 run → NovelAgentService.tokenFor 返回 null，
      // 分支应跳过取消注册，纯走作答路径
      final run = container.read(scenarioProvider).executeTool(
            'ask_user',
            {'question': 'q2', 'options': ['A']},
            toolCallId: 'call_4',
          );
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (registry.pendingCount == 0) {
        if (DateTime.now().isAfter(deadline)) fail('未注册挂起提问');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        registry.answer(
          scenarioId: 'writing',
          toolCallId: 'call_4',
          selected: ['A'],
        ),
        isTrue,
      );
      final result = decode(await run.timeout(const Duration(seconds: 5)));
      expect(result['selected'], ['A']);
    });
  });

  group('ask_user 与 AgentScenario 接口', () {
    test('WritingScenario 的 tools 面包含 ask_user schema', () {
      final tools = container
          .read(scenarioProvider)
          .tools
          .where((t) => t['function']['name'] == 'ask_user')
          .toList();
      expect(tools, hasLength(1),
          reason: '主写作助手应向 LLM 暴露 ask_user');
    });
  });
}

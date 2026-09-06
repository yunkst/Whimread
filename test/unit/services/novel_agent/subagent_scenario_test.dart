import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/subagent_scenario.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';

void main() {
  group('SubagentScenario', () {
    SubagentScenario make(List<String> allowed) =>
        SubagentScenario(task: 't', allowedTools: allowed);

    test('tools 只含白名单内工具', () {
      final s = make(['get_outline', 'read_chapter_content']);
      final names = s.tools.map((t) => t['function']['name'] as String).toSet();
      expect(names, {'get_outline', 'read_chapter_content'});
    });

    test('tools 不含 dispatch_subagent（即使白名单传入）', () {
      final s = make(['get_outline', 'dispatch_subagent']);
      final names = s.tools.map((t) => t['function']['name'] as String).toSet();
      expect(names.contains('dispatch_subagent'), isFalse);
    });

    test('id 为 subagent', () {
      expect(make(['get_outline']).id, 'subagent');
    });

    test('buildSystemPrompt 含通用模板纪律', () {
      final s = make(['get_outline']);
      final prompt = s.buildSystemPrompt(const AgentScenarioContext());
      expect(prompt.contains('子 Agent'), isTrue);
      expect(prompt.contains('最终结论'), isTrue); // 结果格式
      expect(prompt.contains('不要再派子 Agent'), isTrue); // 单层嵌套约束
    });

    test('buildSystemPrompt 含 task 文本', () {
      final s = SubagentScenario(
          task: '梳理第 1-30 章人物关系', allowedTools: ['get_outline']);
      final prompt = s.buildSystemPrompt(const AgentScenarioContext());
      expect(prompt.contains('梳理第 1-30 章人物关系'), isTrue);
    });

    test('executeTool 白名单外工具返回 guidanceError JSON', () async {
      final s = make(['get_outline']);
      final result = await s.executeTool('update_chapter_content', {});
      expect(result.contains('error'), isTrue);
      expect(result.contains('forbidden_tool') || result.contains('not_allowed'),
          isTrue);
    });

    test('executeTool 调用 dispatch_subagent 返回禁止错误', () async {
      final s = make(['get_outline']);
      final result = await s.executeTool('dispatch_subagent', {});
      expect(result.contains('error'), isTrue);
    });
  });
}

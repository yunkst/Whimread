import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_tools.dart';

void main() {
  group('AgentTools subagent', () {
    test('allTools 含 dispatch_subagent', () {
      final t = AgentTools.findTool('dispatch_subagent');
      expect(t, isNotNull);
      expect(
        (t!['function']['parameters']['properties'] as Map).containsKey('task'),
        isTrue,
      );
      expect(
        (t['function']['parameters']['properties'] as Map)
            .containsKey('allowed_tools'),
        isTrue,
      );
      expect(
        (t['function']['parameters']['required'] as List).contains('task'),
        isTrue,
      );
    });

    test('filterTools 返回白名单内工具且不含 dispatch_subagent', () {
      final filtered = AgentTools.filterTools(
        const ['get_outline', 'read_chapter_content', 'list_chapters'],
      );
      final names =
          filtered.map((t) => t['function']['name'] as String).toSet();
      expect(names.contains('get_outline'), isTrue);
      expect(names.contains('read_chapter_content'), isTrue);
      expect(names.contains('list_chapters'), isTrue);
      expect(names.contains('dispatch_subagent'), isFalse); // 子 Agent 不能再派
      expect(names.contains('update_chapter_content'), isFalse); // 白名单外
    });

    test('filterTools 自动剔除 dispatch_subagent（即使传入）', () {
      final filtered =
          AgentTools.filterTools(const ['get_outline', 'dispatch_subagent']);
      final names =
          filtered.map((t) => t['function']['name'] as String).toSet();
      expect(names.contains('dispatch_subagent'), isFalse);
      expect(names.contains('get_outline'), isTrue);
    });

    test('filterTools 白名单全空返回空列表（不崩）', () {
      expect(AgentTools.filterTools(const []), isEmpty);
    });

    test('filterTools 忽略不存在的工具名', () {
      final filtered =
          AgentTools.filterTools(const ['get_outline', 'nonexistent_tool']);
      expect(filtered.length, 1);
      expect(filtered.first['function']['name'], 'get_outline');
    });
  });
}

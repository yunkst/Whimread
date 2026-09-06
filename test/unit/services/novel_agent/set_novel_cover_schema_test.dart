import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_tools.dart';

void main() {
  test('AgentTools.allTools 含 set_novel_cover', () {
    final names = AgentTools.allTools
        .map((t) => (t['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();

    expect(names, contains('set_novel_cover'));
  });

  test('set_novel_cover 参数为 mediaId（string|null），required', () {
    final tool = AgentTools.allTools.firstWhere(
      (t) => (t['function'] as Map<String, dynamic>)['name'] == 'set_novel_cover',
    );
    final params =
        (tool['function'] as Map<String, dynamic>)['parameters'] as Map<String, dynamic>;
    final mediaId = (params['properties'] as Map<String, dynamic>)['mediaId']
        as Map<String, dynamic>;

    expect(params['required'], contains('mediaId'));
    expect(mediaId['type'], ['string', 'null']);
  });
}

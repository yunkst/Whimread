library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/agent_launcher/agent_launch_request.dart';

void main() {
  group('AgentLaunchRequest', () {
    test('autoSend 模式构造', () {
      final req = AgentLaunchRequest(
        scenarioId: 'webview_extract',
        context: {'currentUrl': 'https://a.com/book/1', 'domain': 'a.com'},
        draftMessage: '请生成提取脚本',
        mode: LaunchMode.autoSend,
      );
      expect(req.scenarioId, 'webview_extract');
      expect(req.mode, LaunchMode.autoSend);
      expect(req.context['domain'], 'a.com');
      expect(req.title, isNull);
    });

    test('draftOnly 模式构造带标题', () {
      final req = AgentLaunchRequest(
        scenarioId: 'writing',
        context: {'novelId': 5},
        draftMessage: '请添加章节',
        mode: LaunchMode.draftOnly,
        title: '添加章节',
      );
      expect(req.mode, LaunchMode.draftOnly);
      expect(req.title, '添加章节');
    });

    test('draftMessage 不应为空断言', () {
      expect(
        () => AgentLaunchRequest(
          scenarioId: 'webview_extract',
          context: {},
          draftMessage: '',
          mode: LaunchMode.autoSend,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('scenarioId 不应为空断言', () {
      expect(
        () => AgentLaunchRequest(
          scenarioId: '',
          context: {},
          draftMessage: 'x',
          mode: LaunchMode.autoSend,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

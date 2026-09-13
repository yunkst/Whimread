/// ScenarioInfo.supportsMemory 标志测试
///
/// 记忆管理页按此标志决定是否为场景展示记忆 Tab。契约：
/// - 有记忆闭环的场景（有 patch_memory 工具且 getMemories 读自己的存储）
///   必须显式置 true；
/// - 无记忆闭环的场景（如按标注重写：无 patch_memory，只读复用写作场景
///   的记忆）默认 false——若误置 true，用户在记忆页写入的记忆无人消费，
///   成为死数据。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/agent_scenario_factory.dart';

void main() {
  group('ScenarioInfo.supportsMemory', () {
    test('writing / webview_extract 有记忆闭环 → true', () {
      final flags = {
        for (final info in AgentScenarioFactory.availableScenarios)
          info.id: info.supportsMemory,
      };
      expect(flags[ScenarioIds.writing], isTrue);
      expect(flags[ScenarioIds.webviewExtract], isTrue);
    });

    test('annotation_rewrite 无 patch_memory（只读复用写作记忆）→ false', () {
      final info = AgentScenarioFactory.availableScenarios
          .firstWhere((i) => i.id == ScenarioIds.annotationRewrite);
      expect(info.supportsMemory, isFalse);
    });

    test('默认值为 false：新场景漏配标志时不会出现死记忆 Tab', () {
      const info = ScenarioInfo(id: 'x', displayName: 'x', icon: 'x');
      expect(info.supportsMemory, isFalse);
    });
  });
}

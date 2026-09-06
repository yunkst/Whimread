/// 测试用 AgentScenario 假实现基类
///
/// 提供 AgentScenario 接口 7 个固定方法的默认 no-op 实现；
/// 子类只 override `executeTool`（其他方法按需 override）。
/// 消除 agent_*_test.dart 系列里 30+ 行重复 boilerplate。
///
/// 命名说明：基类叫 `BaseFakeAgentScenario`，避免与具体测试里同名的子类（如
/// `agent_loop_cancel_test.dart` 的 `FakeAgentScenario`）同名冲突。
///
/// 已知不适用本基类的子类：
/// - _TestScenario in agent_memory_test.dart（用 AgentMemoryPatchMixin）
/// - _CancelAfterFirstToolScenario in agent_loop_cancel_test.dart（内层包装）
library;

import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart' show ChatMessage;

/// 测试基类：实现 AgentScenario 接口全部方法，子类按需 override。
///
/// 注意：构造时要求 `id` / `displayName` / `tools` 子类按需 override；
/// 默认值是 'fake' / 'Fake' / const []，覆盖大多数场景。
abstract class BaseFakeAgentScenario with AgentScenarioCleanupMixin
    implements AgentScenario {
  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  List<Map<String, dynamic>> get tools => const [];

  @override
  String buildSystemPrompt(AgentScenarioContext context) => 'sys';

  @override
  Future<List<String>> getMemories() async => const [];

  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async => null;

  @override
  Future<MemoryPatchResult> patchMemory(int? index, String newText) async =>
      MemoryPatchResult.error('fake 不支持 patchMemory', const []);
}

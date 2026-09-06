/// 子 Agent 相关 Riverpod Providers
///
/// 任务 7 提前建好供 WritingScenario 消费（原本属任务 9）：
/// - [subagentRegistryProvider]：内存注册表（按 parentSessionId 索引）
/// - [subagentRunnerProvider]：调度器，注入 NovelAgentService 用于事件回流
///
/// 决策 1（任务 7）：子 Agent 事件直接发到 NovelAgentService.events 全局流，
/// 不再依赖 emitParent 转发。subagentRunnerProvider 在此组装。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/novel_agent/novel_agent_service.dart';
import '../../services/novel_agent/subagent_registry.dart';
import '../../services/novel_agent/subagent_runner.dart';

/// 子 Agent 注册表
///
/// 生命周期：随主 ScenarioSession 一起 dispose（clearForSession）。
/// 应用级单例（无 family），所有 session 共享一份内存索引。
final subagentRegistryProvider = Provider<SubagentRegistry>((ref) {
  final registry = SubagentRegistry();
  ref.onDispose(registry.clearAll);
  return registry;
});

/// 子 Agent 调度器
///
/// 写作场景（WritingScenario）的 executeTool 路径调
/// `ref.read(subagentRunnerProvider).dispatch(...)` 派发子任务。
final subagentRunnerProvider = Provider<SubagentRunner>((ref) {
  final registry = ref.watch(subagentRegistryProvider);
  final agentService = ref.watch(novelAgentServiceProvider);
  return SubagentRunner(
    ref: ref,
    registry: registry,
    agentService: agentService,
  );
});

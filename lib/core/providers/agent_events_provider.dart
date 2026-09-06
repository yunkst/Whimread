/// Agent 全局事件流 Provider（Task 8）。
///
/// NovelAgentService.events 是 broadcast Stream（不是 Riverpod provider），
/// UI 层若要监听必须先经此 Provider 暴露。dialog 用 `ref.listen` 订阅
/// `agentEventsProvider`，StreamProvider 会自动把事件转成 AsyncValue of AgentEvent，
/// listener 内只取 `data` 部分触发 SnackBar。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/novel_agent/agent_event.dart';
import '../../services/novel_agent/novel_agent_service.dart';

/// Agent 全局事件流 — 把 NovelAgentService.events 暴露为 Riverpod StreamProvider。
///
/// 直接 `ref.read(novelAgentServiceProvider).events` 也可工作，但需要 widget
/// 持有 ref.read 调用并自行管理订阅生命周期；走 StreamProvider 配合 ref.listen
/// 是 Riverpod 推荐做法，自动管理订阅和销毁。
final agentEventsProvider = StreamProvider<AgentEvent>((ref) {
  final service = ref.read(novelAgentServiceProvider);
  return service.events;
});

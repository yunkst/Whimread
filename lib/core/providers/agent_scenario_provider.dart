/// 当前 Agent 场景 Provider
///
/// 根据用户当前所在的 UI 页面自动切换 AI Agent 的场景。
/// 各页面通过此 Provider 设置当前场景，AgentChatNotifier 读取此值。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/novel_agent/agent_scenario.dart';

/// 当前激活的 Agent 场景 ID
///
/// 页面在 initState 中设置此值，dispose 时恢复默认。
/// 默认为 'writing'（小说写作助手）。
final currentAgentScenarioProvider = StateProvider<String>(
  (ref) => ScenarioIds.writing,
);

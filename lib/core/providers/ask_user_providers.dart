/// ask_user 工具相关 Riverpod Providers
///
/// - [askUserRegistryProvider]：挂起提问注册表（应用级单例）。
///   写作场景（WritingScenario）的 ask_user 分支 register 并 await；
///   ScenarioSession.answerAskUser 作为 UI 作答入口委托给它。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/novel_agent/ask_user_registry.dart';

/// ask_user 挂起提问注册表
///
/// 应用级单例（无 family）：挂起项按 scenarioId::toolCallId 键控，
/// 支持多场景并发提问互不干扰；随 ProviderContainer 生命周期存活。
final askUserRegistryProvider = Provider<AskUserRegistry>((ref) {
  return AskUserRegistry();
});

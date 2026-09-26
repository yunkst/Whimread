/// AI 对话会话相关 Provider
///
/// - currentChatSessionIdProvider: 某场景当前选中的会话 id（按场景隔离，
///   null 表示该场景还没选）
/// - chatSessionsByScenarioProvider: 某 scenario 下所有会话的列表
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_session.dart';
import 'database_providers.dart';

/// 某场景当前激活的会话 id（来自 UI 切换或冷启动回查）— 按场景隔离
///
/// key = scenarioId：不同场景各自维护自己的"当前会话"，互不可见。
/// 曾经是全局单值，场景 A 聊天写入的 id 会被场景 B 的 ScenarioSession
/// 当作初始会话 hydrate，导致"切了场景但上下文还是旧的"跨场景串台。
final currentChatSessionIdProvider =
    StateProvider.family<int?, String>((ref, scenarioId) => null);

/// 列出某 scenario 下的所有会话（按 updatedAt DESC）
///
/// 用 FutureProvider.family 让多个 scenario 的列表互不串、且自动缓存。
final chatSessionsByScenarioProvider =
    FutureProvider.family<List<ChatSession>, String>((ref, scenarioId) async {
  final repo = ref.watch(chatSessionRepositoryProvider);
  return repo.listSessionsByScenario(scenarioId);
});

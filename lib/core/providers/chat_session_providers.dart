/// AI 对话会话相关 Provider
///
/// - currentChatSessionIdProvider: 当前选中的会话 id（null 表示还没选）
/// - chatSessionsByScenarioProvider: 某 scenario 下所有会话的列表
/// - chatMessagesBySessionProvider: 某 session 所有消息的列表
///
/// Provider 之间有依赖：scenario 切换时应该把 currentChatSessionId 重置为 null，
/// 由 dialog/UI 层在打开历史抽屉时按需刷新最近使用的会话。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_message_record.dart';
import '../../models/chat_session.dart';
import 'database_providers.dart';

/// 当前激活的会话 id（来自 UI 切换或冷启动回查）
///
/// null 表示当前 scenario 还没选定一个 session。
/// UI 切到别的 session 时直接写新值；切 scenario 时由调用方 reset 回 null。
final currentChatSessionIdProvider = StateProvider<int?>((ref) => null);

/// 列出某 scenario 下的所有会话（按 updatedAt DESC）
///
/// 用 FutureProvider.family 让多个 scenario 的列表互不串、且自动缓存。
final chatSessionsByScenarioProvider =
    FutureProvider.family<List<ChatSession>, String>((ref, scenarioId) async {
  final repo = ref.watch(chatSessionRepositoryProvider);
  return repo.listSessionsByScenario(scenarioId);
});

/// 列出某 session 的全部消息（按 orderIndex ASC）
///
/// 注：当前持久化流程在 user 刚发出 / agent 刚完成时分别落库，
/// 列表刷新主要被 UI 「切换 session」时调用。
final chatMessagesBySessionProvider =
    FutureProvider.family<List<ChatMessageRecord>, int>((ref, sessionId) async {
  final repo = ref.watch(chatSessionRepositoryProvider);
  return repo.listMessages(sessionId);
});

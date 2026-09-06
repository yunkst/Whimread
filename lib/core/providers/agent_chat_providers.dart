/// Agent Chat 状态和 Provider
///
/// 重构为多 Session 架构：
/// - ScenarioSession（scenario_session.dart）— 每个场景的独立运行时
/// - ScenarioSessionsNotifier（scenario_sessions_provider.dart）— 会话管理器
/// - agentChatProvider — 兼容层，委托给当前场景的 ScenarioSession
///
/// 对应 AI Agent 的三层隔离模型：
/// 1. 按 session_key 的 Agent 实例缓存 → ScenarioSession 按 scenarioId
/// 2. 独立事件流 → 每个 ScenarioSession 有独立的 _pendingSegments
/// 3. 会话状态机 → SessionLifecycle (fresh → active → idle → disposed)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/logger_service.dart';
import '../../services/novel_agent/agent_scenario_factory.dart';
import 'agent_scenario_provider.dart';
import 'current_novel_provider.dart';
import 'agent_chat_state.dart';
import 'scenario_session.dart';
import 'scenario_sessions_provider.dart';

// AgentChatState 已移到 agent_chat_state.dart

/// Agent Chat Notifier — 兼容层
///
/// 委托给 ScenarioSessionsNotifier，保持对外 API 不变。
/// 新代码应直接使用 currentChatStateProvider / currentSessionProvider。
class AgentChatNotifier extends StateNotifier<AgentChatState> {
  final Ref _ref;

  /// 是否正在从 UI 手动切换（避免和自动切换冲突）
  bool _isSwitchingFromUI = false;

  AgentChatNotifier(this._ref) : super(const AgentChatState()) {
    // 监听场景自动切换
    _ref.listen<String>(
      currentAgentScenarioProvider,
      (prev, next) {
        if (prev != next && !_isSwitchingFromUI) {
          _autoSwitchScenario(next);
        }
      },
    );

    // 监听 sessions 状态变化，同步当前场景的 state
    _ref.listen<Map<String, AgentChatState>>(
      scenarioSessionsProvider,
      (prev, next) {
        final scenarioId = _ref.read(currentAgentScenarioProvider);
        final newState = next[scenarioId];
        if (newState != null && newState != state) {
          state = newState;
        }
      },
    );

    // 初始化：同步当前场景状态
    _syncFromSession();
  }

  /// 获取当前场景的 ScenarioSession
  ScenarioSession? get _currentSession {
    final scenarioId = _ref.read(currentAgentScenarioProvider);
    return _ref.read(scenarioSessionsProvider.notifier).getIfExists(scenarioId);
  }

  /// 获取或创建当前场景的 ScenarioSession
  ScenarioSession get _ensureSession {
    final scenarioId = _ref.read(currentAgentScenarioProvider);
    return _ref.read(scenarioSessionsProvider.notifier).get(scenarioId);
  }

  /// 从 session 同步状态到本 notifier
  void _syncFromSession() {
    final scenarioId = _ref.read(currentAgentScenarioProvider);
    final sessions = _ref.read(scenarioSessionsProvider);
    state = sessions[scenarioId] ??
        AgentChatState(
          scenarioId: scenarioId,
          scenarioDisplayName: AgentScenarioFactory.availableScenarios
                  .where((s) => s.id == scenarioId)
                  .firstOrNull
                  ?.displayName ??
              scenarioId,
        );
  }

  /// 自动切换场景（由 Provider 变化触发）
  void _autoSwitchScenario(String scenarioId) {
    final info = AgentScenarioFactory.availableScenarios
        .where((s) => s.id == scenarioId)
        .firstOrNull;
    if (info == null) return;
    switchScenario(info.id, info.displayName);
  }

  /// 切换场景 — 不杀 Agent，只是切换 UI 视图
  ///
  /// 核心变化：之前 switchScenario 会 _agentSub.cancel() 杀掉 Agent，
  /// 现在只是切换 currentAgentScenarioProvider，让 UI 展示另一个 session 的状态。
  void switchScenario(String scenarioId, String displayName) {
    if (state.scenarioId == scenarioId) return;

    LoggerService.instance.i(
      'Agent 场景切换: ${state.scenarioId} → $scenarioId',
      category: LogCategory.ai,
      tags: ['provider', 'agent_chat', 'scenario-switch', scenarioId],
    );

    // 同步 currentAgentScenarioProvider（手动切换时）
    _isSwitchingFromUI = true;
    _ref.read(currentAgentScenarioProvider.notifier).state = scenarioId;
    _isSwitchingFromUI = false;

    // 懒创建目标场景的 session（如果还没有）
    _ref.read(scenarioSessionsProvider.notifier).get(scenarioId);

    // 同步状态到本 notifier
    _syncFromSession();
  }

  /// 发送消息 — 委托给当前场景的 ScenarioSession
  Future<void> sendMessage(String content) async {
    final session = _ensureSession;
    await session.sendMessage(content: content);
    // 同步状态
    state = session.state;
  }

  /// 停止当前生成 — 委托给当前场景的 ScenarioSession
  void cancelRequest() {
    _currentSession?.cancel();
    _syncFromSession();
  }

  /// 清空对话 — 委托给当前场景的 ScenarioSession
  void clearConversation() {
    _currentSession?.clearConversation();
    _syncFromSession();
  }

  /// 切换当前小说 — 委托给当前场景的 ScenarioSession
  Future<CurrentNovel?> selectNovel(int novelId) async {
    final session = _currentSession;
    if (session == null) return null;
    final result = await session.selectNovel(novelId);
    _syncFromSession();
    return result;
  }
}

/// Agent Chat Provider — 兼容层
///
/// StateNotifierProvider 在 Riverpod 2.x 中默认不 autoDispose，
/// 因此用户离开页面后对话历史和 Agent 任务状态会一直保持。
/// 用户切换到 APP 其他页面后返回，仍能看到之前的任务执行情况。
///
/// 新代码应优先使用 currentChatStateProvider / currentSessionProvider。
final agentChatProvider =
    StateNotifierProvider<AgentChatNotifier, AgentChatState>((ref) {
  return AgentChatNotifier(ref);
});

/// 场景会话管理器 — 按 scenarioId 管理 ScenarioSession 实例
///
/// 对应 Agent Gateway 的 _agent_cache 机制：
/// - 按 session_key (scenarioId) 懒创建 AIAgent 实例
/// - LRU 淘汰空闲实例（_AGENT_CACHE_MAX_SIZE = 128）
/// - _AGENT_CACHE_IDLE_TTL_SECS = 3600（空闲 1 小时驱逐）
///
/// 在 Flutter 中简化为：
/// - 按 scenarioId 懒创建 ScenarioSession
/// - LRU 淘汰（最多 8 个 session，空闲的优先淘汰）
/// - Riverpod state 同步（`Map<scenarioId, AgentChatState>`）
///
/// 多 session 持久化后，ScenarioSession 本身多一个 sessionId 字段（可空）；
/// 切换 session 时清空 in-memory messages，让 ScenarioSession 主动从 DB 加载。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_session.dart';
import '../../services/logger_service.dart';
import '../../services/novel_agent/agent_scenario_factory.dart';
import 'agent_scenario_provider.dart';
import 'chat_session_providers.dart';
import 'agent_chat_state.dart';
import 'database_providers.dart';
import 'scenario_session.dart';

/// 最大并发 session 数
const _maxSessions = 8;

/// 场景会话管理器
class ScenarioSessionsNotifier
    extends StateNotifier<Map<String, AgentChatState>> {
  final Ref _ref;

  /// scenarioId → ScenarioSession 实例
  final Map<String, ScenarioSession> _sessions = {};

  /// 访问顺序（用于 LRU 淘汰），最近访问的在末尾
  final List<String> _accessOrder = [];

  ScenarioSessionsNotifier(this._ref) : super({});

  /// 获取指定场景的 session（懒创建）。
  ///
  /// 第一次调用时，如果当前已经有选中的 sessionId（来自 currentChatSessionIdProvider），
  /// 用它；否则传 null，让 ScenarioSession 自身从 DB 选最近一个。
  ScenarioSession get(String scenarioId) {
    // 更新访问顺序
    _accessOrder.remove(scenarioId);
    _accessOrder.add(scenarioId);

    if (_sessions.containsKey(scenarioId)) {
      return _sessions[scenarioId]!;
    }

    // 懒创建
    LoggerService.instance.i(
      'ScenarioSessions 创建新 session: $scenarioId',
      category: LogCategory.ai,
      tags: ['sessions', 'create', scenarioId],
    );

    final initialSessionId = _ref.read(currentChatSessionIdProvider);
    final session = ScenarioSession(
      scenarioId: scenarioId,
      initialSessionId: initialSessionId,
      ref: _ref,
    );
    session.setOnStateChanged(() => _syncState(scenarioId));
    _sessions[scenarioId] = session;

    // LRU 淘汰 + 初始同步。
    // 注意：get() 可能被某个 Provider 的 build 周期调用（例如 currentSessionProvider），
    // 此时直接写 state 会触发 Riverpod 断言
    // "Providers are not allowed to modify other providers during their initialization"。
    // 故把 state 写入推迟到当前微任务之后，保证不在任何 provider 的构建阶段执行。
    _scheduleSync(() {
      _evictIfNeeded();
      _syncState(scenarioId);
    });

    // 冷启动自动 hydrate：如果已经选了 sessionId（或 DB 里有该 scenario 的历史），
    // 主动加载 messages，让 UI 一打开就能看到上次的对话。
    // fire-and-forget：失败只记日志，messages 留空也不影响 agent 后续运行。
    if (initialSessionId != null) {
      // 已知 sessionId → 直接 hydrate
      session.hydrateIfNeeded();
    } else {
      // 未知 sessionId → 让 ScenarioSession 内部先选最近再 hydrate
      session.hydrateFromRecentIfNeeded();
    }

    return session;
  }

  /// 切换会话 id（来自 UI「打开历史 → 点了一条」）。
  ///
  /// - 如果新 sessionId == 当前 ScenarioSession.sessionId：noop
  /// - 否则：把 in-memory messages 清空，让 ScenarioSession 内部重新从 DB hydrate
  ///
  /// 不杀 agent（跨 scenario 切场景不杀；同 scenario 切 sessionId 由 ScenarioSession
  /// 内部 cancel 兜底，避免数据污染）。
  Future<void> switchSession(String scenarioId, int? newSessionId) async {
    final session = _sessions[scenarioId];
    if (session == null) {
      // ScenarioSession 还没被创建，让下次 get() 用新 sessionId 初始化
      return;
    }
    await session.adoptSession(newSessionId);
    _syncState(scenarioId);
    // 触发重新 hydrate（内部 await，状态变化会通过 _onStateChanged 同步）
    session.hydrateIfNeeded();
  }

  /// 新建一条空白会话并切换过去（旧会话保留在历史列表）。
  ///
  /// 「对话窗口右上角按钮」与「会话历史 → 新建会话」共用本方法，保证两处入口行为一致。
  /// 运行中新建会话时，由 [ScenarioSession.adoptSession] 内部 cancel 老 agent 兜底，
  /// 避免流式 segment 落进新 session 造成数据污染。
  Future<void> startNewSession(String scenarioId) async {
    final repo = _ref.read(chatSessionRepositoryProvider);
    final id = await repo.createSession(
      ChatSession(scenarioId: scenarioId, title: ''),
    );
    _ref.read(currentChatSessionIdProvider.notifier).state = id;
    await switchSession(scenarioId, id); // adoptSession + hydrateIfNeeded
    _ref.invalidate(chatSessionsByScenarioProvider(scenarioId));
  }

  /// 获取当前场景的 session（如果已创建）
  ScenarioSession? getIfExists(String scenarioId) {
    return _sessions[scenarioId];
  }

  /// 获取所有活跃 session 的 scenarioId
  List<String> get activeSessionIds => _sessions.keys.toList();

  /// 是否有指定场景的 session
  bool hasSession(String scenarioId) => _sessions.containsKey(scenarioId);

  /// 是否有指定场景正在运行
  bool isRunning(String scenarioId) {
    return _sessions[scenarioId]?.isRunning ?? false;
  }

  /// 销毁指定场景的 session
  void disposeSession(String scenarioId) {
    final session = _sessions.remove(scenarioId);
    if (session != null) {
      session.dispose();
      _accessOrder.remove(scenarioId);
      state = <String, AgentChatState>{...state}..remove(scenarioId);
      LoggerService.instance.i(
        'ScenarioSessions 销毁 session: $scenarioId',
        category: LogCategory.ai,
        tags: ['sessions', 'dispose', scenarioId],
      );
    }
  }

  /// 销毁所有 session
  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    _accessOrder.clear();
    super.dispose();
  }

  // ===== 内部方法 =====

  /// 把一段「会改 state」的副作用推迟到当前微任务之后执行，
  /// 避免在某个 Provider 的 build 周期内触发 state 写入断言。
  void _scheduleSync(void Function() action) {
    scheduleMicrotask(action);
  }

  /// 把 session 状态同步到 Riverpod state
  void _syncState(String scenarioId) {
    final session = _sessions[scenarioId];
    if (session == null) return;
    state = <String, AgentChatState>{...state, scenarioId: session.state};
  }

  /// LRU 淘汰 — 超过 _maxSessions 时淘汰最早的不在运行的 session
  void _evictIfNeeded() {
    while (_sessions.length > _maxSessions) {
      // 从访问顺序的头部找第一个不在运行的 session
      String? evictKey;
      for (final key in _accessOrder) {
        final session = _sessions[key];
        if (session != null && !session.isRunning) {
          evictKey = key;
          break;
        }
      }

      if (evictKey == null) {
        // 所有 session 都在运行，无法淘汰
        LoggerService.instance.w(
          'ScenarioSessions 无法淘汰：所有 ${_sessions.length} 个 session 都在运行中',
          category: LogCategory.ai,
          tags: ['sessions', 'evict', 'all_running'],
        );
        break;
      }

      LoggerService.instance.i(
        'ScenarioSessions LRU 淘汰 session: $evictKey',
        category: LogCategory.ai,
        tags: ['sessions', 'evict', evictKey],
      );

      final session = _sessions.remove(evictKey);
      session?.dispose();
      _accessOrder.remove(evictKey);
      state = <String, AgentChatState>{...state}..remove(evictKey);
    }
  }
}

/// 场景会话管理器 Provider
///
/// 全局单例，管理所有场景的 ScenarioSession 实例。
/// StateNotifierProvider 在 Riverpod 2.x 中默认不 autoDispose。
final scenarioSessionsProvider =
    StateNotifierProvider<ScenarioSessionsNotifier, Map<String, AgentChatState>>(
  (ref) {
    LoggerService.instance.i(
      'ScenarioSessionsNotifier 初始化',
      category: LogCategory.ai,
      tags: ['sessions', 'init'],
    );
    return ScenarioSessionsNotifier(ref);
  },
);

/// 当前场景的聊天状态 — UI 只 watch 这个
///
/// UI 层不直接感知 ScenarioSession 的存在，
/// 只通过这个 Provider 读取当前场景的 AgentChatState。
///
/// 同时 watch `currentAgentScenarioProvider`（场景）和 `currentChatSessionIdProvider`
/// （会话 id）：sessionId 在 ScenarioSession 内部异步解析（冷启动选最近 / 首条消息新建）
/// 时会被写回，此时 sessions state 尚未携带新 messages，watch sessionId 可让 UI 立即
/// 反映「已选中某 session」并等待 hydrate 推送的二次重建。
final currentChatStateProvider = Provider<AgentChatState>((ref) {
  final scenarioId = ref.watch(currentAgentScenarioProvider);
  ref.watch(currentChatSessionIdProvider);
  final sessions = ref.watch(scenarioSessionsProvider);
  return sessions[scenarioId] ??
      AgentChatState(
        scenarioId: scenarioId,
        scenarioDisplayName: AgentScenarioFactory.availableScenarios
                .where((s) => s.id == scenarioId)
                .firstOrNull
                ?.displayName ??
            scenarioId,
      );
});

/// 当前场景的 session — 用于发送消息等操作
///
/// 懒创建：首次访问时自动创建对应场景的 ScenarioSession。
///
/// 会话 id 切换由调用方负责：UI 写入 `currentChatSessionIdProvider` 后再调用
/// `scenarioSessionsProvider.notifier.switchSession(...)` 触发 in-memory reload。
final currentSessionProvider = Provider<ScenarioSession?>((ref) {
  final scenarioId = ref.watch(currentAgentScenarioProvider);
  final notifier = ref.read(scenarioSessionsProvider.notifier);
  return notifier.get(scenarioId);
});

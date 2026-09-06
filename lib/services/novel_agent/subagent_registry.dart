/// 子 Agent 注册表（内存，按 parentSessionId 索引）
///
/// 生命周期：随 ScenarioSessionsNotifier 一起 dispose（clearForSession）。
/// 不持久化。
library;

import 'subagent_run.dart';

class SubagentRegistry {
  final Map<String, Map<String, SubagentRun>> _runsBySession = {};
  final Map<String, Map<String, SubagentRun>> _toolCallIndex = {};

  int _seq = 0;

  /// 生成 runId（不用 uuid 避免引入依赖；session 内唯一即可）
  String _newRunId(String sessionId) {
    _seq++;
    return 'sub-${sessionId.hashCode.toRadixString(36)}-$_seq';
  }

  SubagentRun create({
    required String parentSessionId,
    required String task,
    required List<String> allowedTools,
    String toolCallId = '', // 由 SubagentRunner.dispatch 传入父 toolCallId；测试可省略
  }) {
    final run = SubagentRun(
      runId: _newRunId(parentSessionId),
      parentSessionId: parentSessionId,
      task: task,
      allowedTools: List<String>.unmodifiable(allowedTools),
      toolCallId: toolCallId,
    );
    // 同时索引 toolCallId → run（同一 session 内 toolCallId 唯一）
    if (toolCallId.isNotEmpty) {
      (_toolCallIndex[parentSessionId] ??= <String, SubagentRun>{})[toolCallId] = run;
    }
    (_runsBySession[parentSessionId] ??= <String, SubagentRun>{})[run.runId] = run;
    return run;
  }

  SubagentRun? get(String parentSessionId, String runId) =>
      _runsBySession[parentSessionId]?[runId];

  /// 按 toolCallId 反查（供 UI 从主气泡 ToolCallSegment 找到子 run）
  SubagentRun? getByToolCallId(String parentSessionId, String toolCallId) =>
      _toolCallIndex[parentSessionId]?[toolCallId];

  List<SubagentRun> listForSession(String parentSessionId) {
    final m = _runsBySession[parentSessionId];
    if (m == null) return const <SubagentRun>[];
    // 按 createdAt 升序，便于 UI 稳定展示
    final list = m.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// 统计某 session 占用槽位/排队的 run（running + pending，即 !isTerminal）
  ///
  /// 用于 4 并发上限判断（[SubagentRunner._waitForSlot]）和 30 排队上限判断
  /// （[SubagentRunner.dispatch]）。两个语义此前由 countActiveBySession 和
  /// countTotalBySession 分别承担，但二者实现等价，已合并以消除歧义。
  int countActiveBySession(String parentSessionId) {
    final m = _runsBySession[parentSessionId];
    if (m == null) return 0;
    return m.values.where((r) => !r.isTerminal).length;
  }

  void remove(String parentSessionId, String runId) {
    final run = _runsBySession[parentSessionId]?.remove(runId);
    if (run != null && run.toolCallId.isNotEmpty) {
      _toolCallIndex[parentSessionId]?.remove(run.toolCallId);
    }
  }

  void clearForSession(String parentSessionId) {
    _runsBySession.remove(parentSessionId);
    _toolCallIndex.remove(parentSessionId);
  }

  /// 清空所有 session 的 run（应用级 dispose 时调用，subagentRegistryProvider.onDispose）
  void clearAll() {
    _runsBySession.clear();
    _toolCallIndex.clear();
  }

  /// 保留最近 keep 个 run（不限终态），清掉更早的——控制内存
  /// 用于「保留最近 N 个供回看」（spec §5.3 N=20）
  void pruneForSession(String parentSessionId, {required int keep}) {
    final m = _runsBySession[parentSessionId];
    if (m == null) return;
    if (m.length <= keep) return;
    final sorted = m.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 新→旧
    final toRemove = sorted.skip(keep);
    for (final r in toRemove) {
      m.remove(r.runId);
      if (r.toolCallId.isNotEmpty) {
        _toolCallIndex[parentSessionId]?.remove(r.toolCallId);
      }
    }
  }
}
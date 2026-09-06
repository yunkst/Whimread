/// 子 Agent 单次运行的内存模型（不持久化）
///
/// 由 [SubagentRunner] 创建并持有，[SubagentRegistry] 按 parentSessionId 索引。
/// 一个 [SubagentRun] = 主 Agent 一次 dispatch_subagent 调用派出的子任务。
library;

import 'dart:async';

import '../../core/providers/agent_chat_state.dart';
import '../../utils/cancellation_token.dart';
import 'agent_event.dart';

/// 子 Agent 运行状态
enum SubagentRunState {
  /// 排队中（未达并发槽位）
  pending,
  /// 正在运行
  running,
  /// 正常完成
  completed,
  /// 异常终止
  failed,
  /// 被用户/主 Agent 取消
  cancelled,
}

class SubagentRun {
  final String runId;
  final String parentSessionId;
  final String task;
  final List<String> allowedTools;
  final DateTime createdAt;

  /// 主 Agent 调用 dispatch_subagent 的 toolCallId（LLM 生成）。
  /// 用于 UI 把主气泡里的 ToolCallSegment 反查到本 run（详见任务 10）。
  final String toolCallId;

  /// 可变状态：由 SubagentRunner 推进
  SubagentRunState state;

  /// 子 Agent 的 UI 状态（供详情页渲染 messages / streamingSegments）
  AgentChatState chatState;

  /// 取消令牌；SubagentRunner 启动时创建，cancel() 时触发
  CancellationToken? token;

  /// 运行终止信号：[SubagentRunner._runOne] 终态时 complete（成功/失败/取消均走）。
  ///
  /// 供 [SubagentRunner.cancelAllForSession] 与详情页停止按钮 await，
  /// 使 cancel 调用方能确定性等待子 Agent 真正退出（配合 AgentLoop stream 中断）。
  final Completer<void> _doneCompleter = Completer<void>();

  /// 子 Agent 真正终止的 Future。
  Future<void> get done => _doneCompleter.future;

  /// 是否已终止（[done] 已 complete）。
  bool get isDone => _doneCompleter.isCompleted;

  /// 标记 run 终止（幂等）。由 [SubagentRunner._runOne] 的 finally 调用。
  void completeDone() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  /// 全局事件流订阅（按 runId 过滤后更新 chatState）
  StreamSubscription<AgentEvent>? eventSub;

  /// 运行中实时跟踪（供主气泡卡片进度摘要用）
  String? lastThought;
  String? lastToolName;

  /// 终态产物
  String? finalSummary;
  String? errorMessage;

  SubagentRun({
    required this.runId,
    required this.parentSessionId,
    required this.task,
    required this.allowedTools,
    required this.toolCallId,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        state = SubagentRunState.pending,
        chatState = const AgentChatState();

  /// 是否处于终态
  bool get isTerminal =>
      state == SubagentRunState.completed ||
      state == SubagentRunState.failed ||
      state == SubagentRunState.cancelled;

  /// 主气泡卡片用的轻量进度摘要（按 spec §8.3 投影规则）
  String get progressSummary {
    switch (state) {
      case SubagentRunState.pending:
        return '排队中…';
      case SubagentRunState.running:
        final parts = <String>[];
        if (lastToolName != null) parts.add('[$lastToolName]');
        if (lastThought != null) {
          // 取最近 40 字
          final t = lastThought!;
          parts.add(t.length > 40 ? t.substring(t.length - 40) : t);
        }
        return parts.isEmpty ? '运行中…' : parts.join(' ');
      case SubagentRunState.completed:
        if (finalSummary == null || finalSummary!.isEmpty) return '已完成';
        final firstLine = finalSummary!.split('\n').first;
        return firstLine.length > 60
            ? '${firstLine.substring(0, 60)}…'
            : firstLine;
      case SubagentRunState.failed:
        return errorMessage ?? '失败';
      case SubagentRunState.cancelled:
        return '已取消';
    }
  }
}
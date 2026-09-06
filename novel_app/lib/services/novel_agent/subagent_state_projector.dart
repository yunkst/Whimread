/// 子 Agent 事件打标 + 状态投影
///
/// 两个职责：
/// - [EventTagger]：给裸 AgentEvent 打 runId（不修改原数据）。
/// - [SubagentStateProjector]：把打标后的事件聚合到 [SubagentRun.chatState]，
///   供详情页渲染 messages / streamingSegments。
///
/// 投影规则精简：仅维持 messages + streamingSegments 两个状态字段，
/// 不读 DB、不调 ref、不改 currentNovel（这些由上层 ScenarioSession 负责）。
library;

import '../../models/agent_chat_message.dart';
import 'agent_event.dart';
import 'subagent_run.dart';

/// 给裸 [AgentEvent] 注入 [runId]（copy 重新构造）。
///
/// AgentEvent 所有子类都在构造时支持 `runId` 命名参数（任务 1），
/// 这里纯转发，不修改原对象。
class EventTagger {
  EventTagger._();

  static AgentEvent tag(AgentEvent e, String runId) {
    return switch (e) {
      TextDeltaEvent(:final text) => TextDeltaEvent(text, runId: runId),
      ToolCallStartEvent(
        name: final name,
        args: final args,
        toolCallId: final toolCallId
      ) =>
        ToolCallStartEvent(name, args, toolCallId, runId: runId),
      ToolCallEndEvent(
        name: final name,
        toolCallId: final toolCallId,
        result: final result,
        fullResult: final fullResult,
        success: final success
      ) =>
        ToolCallEndEvent(
          name,
          toolCallId,
          result,
          fullResult: fullResult,
          success: success,
          runId: runId,
        ),
      ToolProgressEvent(
        toolCallId: final toolCallId,
        generatedChars: final generatedChars
      ) =>
        ToolProgressEvent(toolCallId, generatedChars, runId: runId),
      AgentDoneEvent() => AgentDoneEvent(runId: runId),
      AgentErrorEvent(:final error) => AgentErrorEvent(error, runId: runId),
      InjectedUserInputEvent(:final text, :final scenarioId) =>
        InjectedUserInputEvent(text, scenarioId: scenarioId, runId: runId),
      CompactionEvent(
        removedChars: final removedChars,
        originalChars: final originalChars,
        compactedChars: final compactedChars,
        keptMessageCount: final keptMessageCount,
        droppedMessageCount: final droppedMessageCount,
        droppedAgentFromIndex: final droppedAgentFromIndex,
        compactionNote: final compactionNote,
        rewrittenContent: final rewrittenContent,
      ) =>
        CompactionEvent(
          removedChars: removedChars,
          originalChars: originalChars,
          compactedChars: compactedChars,
          keptMessageCount: keptMessageCount,
          droppedMessageCount: droppedMessageCount,
          droppedAgentFromIndex: droppedAgentFromIndex,
          compactionNote: compactionNote,
          rewrittenContent: rewrittenContent,
          runId: runId,
        ),
      RetryEvent(
        attempt: final attempt,
        maxAttempts: final maxAttempts,
        delayMs: final delayMs,
        errorText: final errorText,
        emittedChars: final emittedChars,
      ) =>
        RetryEvent(
          attempt: attempt,
          maxAttempts: maxAttempts,
          delayMs: delayMs,
          errorText: errorText,
          emittedChars: emittedChars,
          runId: runId,
        ),
    };
  }
}

/// 把 AgentEvent 投影到 [SubagentRun.chatState] + lastThought/lastToolName。
///
/// 规则：
/// - [TextDeltaEvent]：追加 [TextSegment] 到 streamingSegments 末尾（与末尾 TextSegment 合并）。
/// - [ToolCallStartEvent]：追加 [ToolCallSegment]（status=running）到 streamingSegments 末尾。
/// - [ToolProgressEvent]：更新对应 toolCallId 的 ToolCallSegment 的 progressChars。
/// - [ToolCallEndEvent]：更新对应 ToolCallSegment 的 status/result。
/// - [AgentDoneEvent]：把 streamingSegments 包装成 assistant 消息加入 messages，清空 streamingSegments。
/// - [AgentErrorEvent]：把当前 streamingSegments（若有）转为 assistant，加入 messages，
///   然后追加 user 错误消息并清空 streamingSegments（与 Done 类似，但对失败更明确）。
/// - [CompactionEvent]：无操作（spec §8.2 由 ScenarioSession 处理）。
class SubagentStateProjector {
  SubagentStateProjector._();

  static void project(AgentEvent event, SubagentRun run) {
    final state = run.chatState;
    switch (event) {
      case TextDeltaEvent(:final text):
        final segments = _appendText(state.streamingSegments, text);
        run.chatState = state.copyWith(streamingSegments: segments);
        // lastThought = 当前 streaming 累计文本（含文本段，跳过工具段）
        run.lastThought = _currentStreamingText(segments);
        return;

      case ToolCallStartEvent(:final name, :final args, :final toolCallId):
        // 工具段始终是独立的新段（不合并相邻工具）
        final newSegment = ToolCallSegment(AgentToolCall(
          id: toolCallId,
          name: name,
          arguments: Map<String, dynamic>.from(args),
        ));
        final segments = [...state.streamingSegments, newSegment];
        run.chatState = state.copyWith(streamingSegments: segments);
        run.lastToolName = name;
        return;

      case ToolProgressEvent(:final toolCallId, :final generatedChars):
        final segments = _updateToolSegment(
          state.streamingSegments,
          toolCallId,
          (call) => call.copyWith(progressChars: generatedChars),
        );
        run.chatState = state.copyWith(streamingSegments: segments);
        return;

      case ToolCallEndEvent(:final toolCallId, :final result, :final success):
        final segments = _updateToolSegment(
          state.streamingSegments,
          toolCallId,
          (call) => call.copyWith(
            status: success ? AgentToolStatus.completed : AgentToolStatus.error,
            result: result,
            clearProgress: true,
          ),
        );
        run.chatState = state.copyWith(streamingSegments: segments);
        return;

      case AgentDoneEvent():
        // 把当前 streamingSegments 落为 assistant 消息（如果有内容）
        if (state.streamingSegments.isEmpty) return;
        final messages = [
          ...state.messages,
          AgentChatMessage(
            role: AgentChatRole.assistant,
            segments: List<AgentChatSegment>.from(state.streamingSegments),
          ),
        ];
        run.chatState = state.copyWith(
          streamingSegments: const [],
          messages: messages,
        );
        return;

      case AgentErrorEvent(:final error):
        final newMessages = <AgentChatMessage>[
          ...state.messages,
          // 先把当前 streaming 段落为 assistant 消息（保留半成品）
          if (state.streamingSegments.isNotEmpty)
            AgentChatMessage(
              role: AgentChatRole.assistant,
              segments: List<AgentChatSegment>.from(state.streamingSegments),
            ),
          AgentChatMessage.user('[Agent 错误] $error'),
        ];
        run.chatState = state.copyWith(
          streamingSegments: const [],
          messages: newMessages,
        );
        return;

      case CompactionEvent():
        // No-op: spec §8.2 由 ScenarioSession 处理 CompactionEvent
        return;

      case RetryEvent(:final emittedChars):
        // 回合重试：砍掉末尾 TextSegment 中本轮已作废的 partial 字符，
        // 防止重试后的完整输出与残缺前缀拼接（与 ScenarioSession 对称）。
        final segments =
            _truncateTrailingText(state.streamingSegments, emittedChars);
        run.chatState = state.copyWith(streamingSegments: segments);
        run.lastThought = _currentStreamingText(segments);
        return;

      case InjectedUserInputEvent():
        // No-op: 主 session 行为（运行中补充消息），子 Agent 不处理
        return;
    }
  }

  /// 从 streamingSegments 末尾 TextSegment 砍掉 [chars] 个字符。
  ///
  /// 与 [_appendText] 的追加规则对称：本轮 partial 一定累积在末尾
  /// TextSegment（可能与之前轮次的完整文本同段）。截断后剩余为空则移除该段；
  /// chars<=0 或末尾非 TextSegment 时原样返回（防御，正常不会发生）。
  static List<AgentChatSegment> _truncateTrailingText(
      List<AgentChatSegment> segs, int chars) {
    if (chars <= 0 || segs.isEmpty || segs.last is! TextSegment) {
      return segs;
    }
    final last = segs.last as TextSegment;
    final remaining = last.content.length - chars;
    if (remaining > 0) {
      return [
        ...segs.sublist(0, segs.length - 1),
        TextSegment(last.content.substring(0, remaining))
      ];
    }
    return segs.sublist(0, segs.length - 1);
  }

  /// 把 text 追加到 streamingSegments 末尾 TextSegment；末尾不是 TextSegment 则新建。
  static List<AgentChatSegment> _appendText(
      List<AgentChatSegment> segs, String text) {
    if (segs.isNotEmpty && segs.last is TextSegment) {
      final last = segs.last as TextSegment;
      return [
        ...segs.sublist(0, segs.length - 1),
        TextSegment(last.content + text)
      ];
    }
    return [...segs, TextSegment(text)];
  }

  /// 找到 streamingSegments 里 toolCallId 匹配的 ToolCallSegment 并 copyWith 更新。
  static List<AgentChatSegment> _updateToolSegment(
    List<AgentChatSegment> segs,
    String toolCallId,
    AgentToolCall Function(AgentToolCall) update,
  ) {
    final result = <AgentChatSegment>[];
    for (final s in segs) {
      if (s is ToolCallSegment && s.call.id == toolCallId) {
        result.add(ToolCallSegment(update(s.call)));
      } else {
        result.add(s);
      }
    }
    return result;
  }

  /// 提取当前 streamingSegments 中的所有 TextSegment 文本（按顺序拼接）。
  static String _currentStreamingText(List<AgentChatSegment> segs) {
    final buf = StringBuffer();
    for (final s in segs) {
      if (s is TextSegment) {
        buf.write(s.content);
      }
    }
    return buf.toString();
  }
}

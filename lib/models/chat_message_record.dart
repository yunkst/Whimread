/// AI 对话消息记录（chat_messages 表）—— v32 统一历史模型
///
/// 一条 chat_message 直接对应 agent 内部的一条 [ChatMessage]（ReAct 链中的一个节点），
/// 含完整 role（system/user/assistant/tool）、toolCalls、toolCallId、agentMsgIndex。
///
/// 设计变更（v31→v32）：
/// - 不再从 UI 视角（AgentChatMessage/segments）重建 agent history，
///   DB 直接存 agent 视角的完整消息，hydrate 时 1:1 还原。
/// - 解决：跨会话续聊工具结果丢失、压缩后无法重建、owner 对齐漂移。
///
/// UI 渲染由 [ScenarioSession._projectUiMessages] 把 agent messages 投影为
/// [AgentChatMessage]（含 TextSegment / ToolCallSegment），UI 层无需感知本模型。
library;

import 'dart:convert';

import '../services/dsl_engine/llm_provider.dart';

class ChatMessageRecord {
  final int? id;
  final int sessionId;
  final String role; // 'system' | 'user' | 'assistant' | 'tool'
  final String content; // role='assistant' 且只有 toolCalls 时为 ''
  final String? toolCallsJson; // assistant 的 toolCalls 序列化（OpenAI tool_calls 格式）
  final String? toolCallId; // tool 消息关联的 tool_call ID
  final DateTime timestamp;
  final int agentMsgIndex; // agent 内部 messages 列表中的索引（还原顺序用）

  ChatMessageRecord({
    this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.toolCallsJson,
    this.toolCallId,
    DateTime? timestamp,
    required this.agentMsgIndex,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 从 agent ChatMessage 构造（落库主路径）
  ///
  /// [agentMsgIndex] 该消息在 agent 内部 messages 列表中的索引。
  factory ChatMessageRecord.fromAgentMessage(
    int sessionId,
    int agentMsgIndex,
    ChatMessage m,
  ) {
    return ChatMessageRecord(
      sessionId: sessionId,
      role: m.role,
      content: m.content ?? '',
      toolCallsJson: m.toolCalls != null && m.toolCalls!.isNotEmpty
          ? jsonEncode(m.toolCalls!.map((tc) => tc.toJson()).toList())
          : null,
      toolCallId: m.toolCallId,
      timestamp: DateTime.now(),
      agentMsgIndex: agentMsgIndex,
    );
  }

  /// 还原为 agent ChatMessage（hydrate 主路径）
  ///
  /// 反序列化失败时 toolCalls 降级为 null（不抛异常），保证 hydrate 不阻塞。
  ChatMessage toAgentMessage() {
    List<ToolCall>? toolCalls;
    if (toolCallsJson != null && toolCallsJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(toolCallsJson!);
        if (decoded is List) {
          toolCalls = decoded
              .whereType<Map<String, dynamic>>()
              .map((j) => ToolCall.fromJson(j))
              .toList();
        }
      } catch (_) {
        // toolCalls 解析失败降级为 null
      }
    }
    return ChatMessage(
      role: role,
      content: content.isEmpty && toolCalls != null ? null : content,
      toolCalls: toolCalls,
      toolCallId: toolCallId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sessionId': sessionId,
      'role': role,
      'content': content,
      if (toolCallsJson != null) 'toolCallsJson': toolCallsJson,
      if (toolCallId != null) 'toolCallId': toolCallId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'agentMsgIndex': agentMsgIndex,
    };
  }

  factory ChatMessageRecord.fromMap(Map<String, dynamic> map) {
    final ts = map['timestamp'];
    return ChatMessageRecord(
      id: map['id'] as int?,
      sessionId: (map['sessionId'] as num).toInt(),
      role: (map['role'] as String?) ?? 'user',
      content: (map['content'] as String?) ?? '',
      toolCallsJson: map['toolCallsJson'] as String?,
      toolCallId: map['toolCallId'] as String?,
      timestamp: ts is int
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now(),
      agentMsgIndex: (map['agentMsgIndex'] as num).toInt(),
    );
  }

  @override
  String toString() =>
      'ChatMessageRecord(id: $id, sessionId: $sessionId, role: $role, '
      'agentMsgIndex: $agentMsgIndex, contentLen: ${content.length})';
}

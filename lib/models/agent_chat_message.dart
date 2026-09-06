import 'dart:convert';

import '../services/logger_service.dart';
import '../services/novel_agent/agent_event.dart';

/// Agent 聊天消息角色
enum AgentChatRole {
  system,
  user,
  assistant,
  marker,
}

/// 消息内容片段（有序，保留时序关系）
///
/// assistant 消息由交替的 TextSegment 和 ToolCallSegment 组成，
/// 精确反映 Agent 的"思考 → 行动 → 思考"流程。
sealed class AgentChatSegment {
  const AgentChatSegment();
}

/// 文本片段（LLM 输出内容）
class TextSegment extends AgentChatSegment {
  final String content;
  const TextSegment(this.content);
}

/// 工具调用片段
class ToolCallSegment extends AgentChatSegment {
  final AgentToolCall call;
  const ToolCallSegment(this.call);
}

/// 用户上传的图片段（仅 user 消息）。
/// mediaId 来自 MediaProxy.upload（前缀 local_），渲染走 MediaView。
class ImageSegment extends AgentChatSegment {
  final String mediaId;
  const ImageSegment({required this.mediaId});
}

/// 上下文压缩分隔条（UI 投影层引入，不进 LLM）。
class CompactionMarkerSegment extends AgentChatSegment {
  final int droppedMessageCount;
  final int keptMessageCount;
  final int removedChars;
  final int originalChars;
  final int compactedChars;
  final int rewrittenCount;
  final DateTime? timestamp;

  const CompactionMarkerSegment({
    required this.droppedMessageCount,
    required this.keptMessageCount,
    required this.removedChars,
    required this.originalChars,
    required this.compactedChars,
    this.rewrittenCount = 0,
    this.timestamp,
  });

  double get compressionRatio =>
      originalChars > 0 ? removedChars / originalChars : 0;
}

/// Agent 聊天消息
class AgentChatMessage {
  final AgentChatRole role;
  final List<AgentChatSegment> segments;
  final DateTime timestamp;

  AgentChatMessage({
    required this.role,
    this.segments = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 合并所有文本片段的内容（用于 LLM 历史和日志）
  String get content => segments
      .whereType<TextSegment>()
      .map((s) => s.content)
      .join('');

  /// 提取所有工具调用（用于向后兼容）
  List<AgentToolCall> get toolCalls => segments
      .whereType<ToolCallSegment>()
      .map((s) => s.call)
      .toList();

  /// 创建系统消息
  factory AgentChatMessage.system(String content) => AgentChatMessage(
        role: AgentChatRole.system,
        segments: [TextSegment(content)],
      );

  /// 创建用户消息
  factory AgentChatMessage.user(String content) => AgentChatMessage(
        role: AgentChatRole.user,
        segments: [TextSegment(content)],
      );

  /// 创建用户消息（直接使用 segments 列表，含 ImageSegment 等多类型片段）
  ///
  /// 用于投影层把含图片占位文本的 user content 还原为多 segment 消息。
  factory AgentChatMessage.userFromSegments(List<AgentChatSegment> segments) =>
      AgentChatMessage(
        role: AgentChatRole.user,
        segments: segments,
      );

  /// 创建助手消息（兼容旧格式：文本 + 工具调用列表）
  ///
  /// 生成结构为 [TextSegment(content), ToolCallSegment×N]
  factory AgentChatMessage.assistant(String content, {List<AgentToolCall> toolCalls = const []}) {
    final segs = <AgentChatSegment>[
      if (content.isNotEmpty) TextSegment(content),
      for (final call in toolCalls) ToolCallSegment(call),
    ];
    return AgentChatMessage(
      role: AgentChatRole.assistant,
      segments: segs,
    );
  }

  /// 创建助手消息（直接使用 segments 列表，保留交替时序）
  factory AgentChatMessage.assistantFromSegments(List<AgentChatSegment> segments) =>
      AgentChatMessage(
        role: AgentChatRole.assistant,
        segments: segments,
      );

  /// 创建上下文压缩标记消息（仅用于 UI 投影层展示，不进 LLM 历史）
  factory AgentChatMessage.compactionMarker(CompactionMarkerSegment seg) {
    return AgentChatMessage(
      role: AgentChatRole.marker,
      segments: [seg],
      timestamp: seg.timestamp ?? DateTime.now(),
    );
  }

  /// segments → JSON 字符串（持久化到 chat_messages.segmentsJson）
  ///
  /// 每条 segment 输出 `{type:'text', content}` 或
  /// `{type:'tool', id, name, arguments, status, result?}`。
  /// 任何异常不会抛出，返回空数组，保证 DB 写入不阻塞主流程。
  static String segmentsToJson(List<AgentChatSegment> segments) {
    try {
      final list = segments.map((s) {
        if (s is TextSegment) {
          return {'type': 'text', 'content': s.content};
        }
        if (s is ToolCallSegment) {
          final c = s.call;
          return {
            'type': 'tool',
            'id': c.id,
            'name': c.name,
            'arguments': c.arguments,
            'status': c.status.name,
            if (c.result != null) 'result': c.result,
          };
        }
        if (s is ImageSegment) {
          return {'type': 'image', 'mediaId': s.mediaId};
        }
        if (s is CompactionMarkerSegment) {
          return {
            'type': 'marker',
            'droppedCount': s.droppedMessageCount,
            'keptCount': s.keptMessageCount,
            'removedChars': s.removedChars,
            'originalChars': s.originalChars,
            'compactedChars': s.compactedChars,
            'rewrittenCount': s.rewrittenCount,
            if (s.timestamp != null)
              'timestamp': s.timestamp!.millisecondsSinceEpoch,
          };
        }
        // 未知子类降级为 text（防御未来扩展）
        return {'type': 'text', 'content': ''};
      }).toList();
      return jsonEncode(list);
    } catch (e) {
      LoggerService.instance.w(
        'segmentsToJson 失败: $e',
        category: LogCategory.ai,
        tags: ['agent_chat', 'serialize_failed'],
      );
      return '[]';
    }
  }

  /// JSON 字符串 → segments（坏数据降级为空 list，不抛异常）
  static List<AgentChatSegment> segmentsFromJson(String json) {
    if (json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      final result = <AgentChatSegment>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final type = item['type']?.toString();
        if (type == 'text') {
          result.add(TextSegment(item['content']?.toString() ?? ''));
        } else if (type == 'tool') {
          final argumentsRaw = item['arguments'];
          final arguments = argumentsRaw is Map
              ? Map<String, dynamic>.from(argumentsRaw)
              : <String, dynamic>{};
          final statusStr = item['status']?.toString() ?? 'running';
          final status = AgentToolStatus.values.firstWhere(
            (s) => s.name == statusStr,
            orElse: () => AgentToolStatus.running,
          );
          result.add(ToolCallSegment(AgentToolCall(
            id: item['id']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            arguments: arguments,
            status: status,
            result: item['result']?.toString(),
          )));
        } else if (type == 'image') {
          final mediaId = item['mediaId']?.toString() ?? '';
          if (mediaId.isNotEmpty) {
            result.add(ImageSegment(mediaId: mediaId));
          }
        } else if (type == 'marker') {
          final ts = item['timestamp'];
          result.add(CompactionMarkerSegment(
            droppedMessageCount: item['droppedCount'] as int? ?? 0,
            keptMessageCount: item['keptCount'] as int? ?? 0,
            removedChars: item['removedChars'] as int? ?? 0,
            originalChars: item['originalChars'] as int? ?? 0,
            compactedChars: item['compactedChars'] as int? ?? 0,
            rewrittenCount: item['rewrittenCount'] as int? ?? 0,
            timestamp: ts is int
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : null,
          ));
        }
        // 未知 type 跳过
      }
      return result;
    } catch (e) {
      LoggerService.instance.w(
        'segmentsFromJson 失败: $e rawLen=${json.length}',
        category: LogCategory.ai,
        tags: ['agent_chat', 'deserialize_failed'],
      );
      return const [];
    }
  }

  /// 序列化为完整快照（含 segments 多态细节，用于持久化）
  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'segmentsJson': segmentsToJson(segments),
    };
  }

  /// 从完整快照反序列化（坏数据降级为仅文本 user 消息）
  factory AgentChatMessage.fromJson(Map<String, dynamic> map) {
    final roleStr = map['role']?.toString() ?? 'user';
    final AgentChatRole role;
    switch (roleStr) {
      case 'system':
        role = AgentChatRole.system;
        break;
      case 'assistant':
        role = AgentChatRole.assistant;
        break;
      case 'marker':
        role = AgentChatRole.marker;
        break;
      default:
        role = AgentChatRole.user;
    }
    final tsMs = map['timestamp'];
    final ts = tsMs is int
        ? DateTime.fromMillisecondsSinceEpoch(tsMs)
        : DateTime.now();
    final rawSegments = map['segmentsJson']?.toString() ?? '[]';
    final segs = segmentsFromJson(rawSegments);
    if (segs.isEmpty) {
      return AgentChatMessage(
        role: role,
        segments: [TextSegment(map['content']?.toString() ?? '')],
        timestamp: ts,
      );
    }
    return AgentChatMessage(role: role, segments: segs, timestamp: ts);
  }

  /// 序列化为 LLM 历史格式（只保留 role + content，不含 segments 细节）
  ///
  /// 保留供历史/外部 LLM 历史回放使用，不被持久化路径调用。
  Map<String, String> toMap() {
    return {
      'role': role.name,
      'content': content,
    };
  }

  factory AgentChatMessage.fromMap(Map<String, dynamic> map) {
    final roleStr = map['role']?.toString() ?? 'user';
    AgentChatRole role;
    switch (roleStr) {
      case 'system':
        role = AgentChatRole.system;
        break;
      case 'assistant':
        role = AgentChatRole.assistant;
        break;
      case 'marker':
        role = AgentChatRole.marker;
        break;
      default:
        role = AgentChatRole.user;
    }
    return AgentChatMessage(
      role: role,
      segments: [TextSegment(map['content']?.toString() ?? '')],
    );
  }

  AgentChatMessage copyWith({
    AgentChatRole? role,
    List<AgentChatSegment>? segments,
    DateTime? timestamp,
  }) {
    return AgentChatMessage(
      role: role ?? this.role,
      segments: segments ?? this.segments,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    final contentPreview = content.length > 50
        ? '${content.substring(0, 50)}...'
        : content;
    return 'AgentChatMessage(role: $role, content: $contentPreview, segments: ${segments.length})';
  }
}
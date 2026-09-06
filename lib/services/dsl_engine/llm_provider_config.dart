/// LLM Provider — 配置与消息模型
///
/// 从原 `llm_provider.dart` 上帝文件拆分。本文件承载 wire-level DTO：
/// [LlmConfig] 运行时配置、[ToolCall]/[LlmResponse]/[ChatMessage] 消息模型、
/// 以及 tool_call arguments 解析失败标记常量与 [markParseError] 辅助函数。
library;

import 'dart:convert';

import 'package:novel_app/services/logger_service.dart';

// -- 配置 --

class LlmConfig {
  final String baseUrl; // 如 https://api.deepseek.com/v1
  final String apiKey;
  final String defaultModel;
  final double temperature;

  // max_tokens 已移除：输出长度交给模型/provider 原生上限
  // （原默认 4096 会截断长章节生成，且无任何用户配置入口，2026-09-04）。

  const LlmConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.defaultModel = '',
    this.temperature = 0.7,
  });

  LlmConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? defaultModel,
    double? temperature,
  }) {
    return LlmConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      defaultModel: defaultModel ?? this.defaultModel,
      temperature: temperature ?? this.temperature,
    );
  }
}

// -- 工具调用模型 (Phase 1: Function Calling) --

/// tool_calls arguments JSON 解析失败的标记 key
///
/// 解析失败时（流式拼接被截断 / JSON 不闭合 / 解析成功但不是对象），
/// [ToolCall.arguments] 会被填入包含此 key 的标记字典。
/// 上层 [ToolExecutor] 据此短路返回引导错误，避免 LLM 拿到空参 {} 而语义崩塌。
const String kArgsParseErrorKey = '__parse_error';

/// 解析失败的详细错误信息（来自 jsonDecode 的 FormatException 等）
const String kArgsParseErrorDetailKey = '__parse_error_detail';

/// 原始 JSON 字符串的预览（截断到 500 字符），供 LLM 自助修复时参考
const String kArgsRawPreviewKey = '__raw_args_preview';

/// 构造「解析失败」标记字典的辅助函数
///
/// 供 [ToolCall.fromJson] 与 `StreamingResult.buildToolCalls`（sse 模块）共用。
Map<String, dynamic> markParseError({
  required String detail,
  required String raw,
}) {
  return {
    kArgsParseErrorKey: true,
    kArgsParseErrorDetailKey: detail,
    kArgsRawPreviewKey:
        raw.length > 500 ? '${raw.substring(0, 500)}...(truncated)' : raw,
  };
}

/// LLM 返回的工具调用
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final func = json['function'] as Map<String, dynamic>? ?? {};
    var args = <String, dynamic>{};
    final rawArgs = func['arguments'];
    if (rawArgs is String && rawArgs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map<String, dynamic>) {
          args = decoded;
        } else {
          // 合法 JSON 但不是对象（数组、字符串、数字）→ 标记错误
          args = markParseError(
            detail: 'JSON 解析成功但不是对象: ${decoded.runtimeType}',
            raw: rawArgs,
          );
        }
      } catch (e) {
        // 流式拼接截断 / JSON 不闭合等 → 标记错误并保留预览
        LoggerService.instance.w(
          'ToolCall arguments 解析失败: id=${json['id']}, name=${func['name']}, err=$e',
          category: LogCategory.ai,
          tags: ['dsl', 'llm', 'tool_call', 'parse_error'],
        );
        args = markParseError(detail: e.toString(), raw: rawArgs);
      }
    } else if (rawArgs is Map<String, dynamic>) {
      args = rawArgs;
    } else if (rawArgs != null && !(rawArgs is String && rawArgs.isEmpty)) {
      // 数字、bool 等异常类型 → 标记
      // 空字符串保持空 args（正常情况：某些工具无参）
      args = markParseError(
        detail: 'arguments 字段类型异常: ${rawArgs.runtimeType}',
        raw: rawArgs.toString(),
      );
    }
    // rawArgs == null / 空字符串 → 保持空 args（正常情况：某些工具无参）
    return ToolCall(
      id: (json['id'] as String?) ?? '',
      name: (func['name'] as String?) ?? '',
      arguments: args,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': jsonEncode(arguments),
        },
      };
}

/// LLM 完整响应（Phase 1: 替代纯 String 返回）
class LlmResponse {
  final String content;
  final List<ToolCall> toolCalls;

  const LlmResponse({this.content = '', this.toolCalls = const []});

  bool get hasToolCalls => toolCalls.isNotEmpty;

  /// 兼容旧代码：隐式转换回纯文本
  @override
  String toString() => content;
}

// -- 消息 --

class ChatMessage {
  final String role; // 'system' | 'user' | 'assistant' | 'tool'
  final String? content; // 可为 null（当 assistant 只有 tool_calls 无文本时）
  final String? name; // 可选：发送者名称
  final String? toolCallId; // tool 角色关联的 tool_call ID
  final List<ToolCall>? toolCalls; // assistant 角色的工具调用

  const ChatMessage({
    required this.role,
    this.content,
    this.name,
    this.toolCallId,
    this.toolCalls,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'role': role};
    if (content != null) map['content'] = content;
    if (name != null) map['name'] = name;
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!.map((tc) => tc.toJson()).toList();
    }
    return map;
  }
}

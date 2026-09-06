/// LLM Provider — SSE 解析器
///
/// 从原 `llm_provider.dart` 上帝文件拆分。本文件承载 SSE 流式协议解析：
/// [SseParseResult]/[StreamingResult] 结果模型、[SseParser] 解析骨架、
/// 以及流式 tool_call delta 聚合辅助 [_ToolCallDelta]。
library;

import 'dart:convert';

import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_config.dart';

// -- SSE 解析器 --

class SseParseResult {
  final List<String> content;
  final List<String> reasoning;

  const SseParseResult({required this.content, required this.reasoning});
}

/// 流式响应累积结果（Phase 1: 支持 tool_calls 收集）
///
/// 注意：默认构造函数创建的是**可变**空列表，便于在流式消费中
/// 逐 chunk add/addAll。
class StreamingResult {
  final List<String> contentChunks;
  final List<String> reasoningChunks;
  final List<Map<String, dynamic>> toolCallDeltas;

  /// 创建可变空列表实例（用于流式累积）
  StreamingResult({
    List<String>? contentChunks,
    List<String>? reasoningChunks,
    List<Map<String, dynamic>>? toolCallDeltas,
  })  : contentChunks = contentChunks ?? [],
        reasoningChunks = reasoningChunks ?? [],
        toolCallDeltas = toolCallDeltas ?? [];

  String get fullContent => contentChunks.join();

  /// 从累积的 tool_call deltas 构建最终的 ToolCall 列表
  List<ToolCall> buildToolCalls() {
    if (toolCallDeltas.isEmpty) return [];

    // 按 index 聚合 tool_call deltas
    final aggregated = <int, _ToolCallDelta>{};
    for (final delta in toolCallDeltas) {
      final idx = (delta['index'] as int?) ?? 0;
      final entry =
          aggregated.putIfAbsent(idx, () => _ToolCallDelta(index: idx));

      final id = delta['id'] as String?;
      if (id != null) entry.id = id;

      final func = delta['function'] as Map<String, dynamic>?;
      if (func != null) {
        // 空串视为缺失：OpenAI 规范在后续 delta 帧省略 name 字段，
        // 但 DeepSeek-V4-Pro 通过 new-api 网关时会把 name 发成 ""（实测见
        // tmp/sse_capture_<ts>.txt frame #56）。一旦 if(name != null)
        // 放过，会覆盖首帧已聚合的真名（如"list_prompt_tags"），下游将
        // 用空函数名调用未知工具。空串不写入即可兼容两种格式。
        final name = func['name'] as String?;
        if (name != null && name.isNotEmpty) entry.name = name;
        final args = func['arguments'] as String?;
        if (args != null) entry.argumentsBuffer.write(args);
      }
    }

    return aggregated.values.where((d) => d.name != null && d.name!.isNotEmpty).map((d) {
      var args = <String, dynamic>{};
      final argsStr = d.argumentsBuffer.toString();
      if (argsStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(argsStr);
          if (decoded is Map<String, dynamic>) {
            args = decoded;
          } else {
            args = markParseError(
              detail: 'JSON 解析成功但不是对象: ${decoded.runtimeType}',
              raw: argsStr,
            );
          }
        } catch (e) {
          LoggerService.instance.w(
            'Streaming tool_call arguments 解析失败: '
            'name=${d.name}, id=${d.id}, argsLen=${argsStr.length}, err=$e',
            category: LogCategory.ai,
            tags: ['dsl', 'llm', 'tool_call', 'streaming_parse_error'],
          );
          args = markParseError(detail: e.toString(), raw: argsStr);
        }
      }
      return ToolCall(id: d.id ?? '', name: d.name ?? '', arguments: args);
    }).toList();
  }
}

class _ToolCallDelta {
  final int index;
  String? id;
  String? name;
  final StringBuffer argumentsBuffer = StringBuffer();

  _ToolCallDelta({required this.index});
}

class SseParser {
  /// 解析单行 SSE `data:` 帧，提取 (contentChunk, reasoningChunk)。
  ///
  /// 抽出来的共用骨架，供 [parseSseStreamWithReasoning]（DeepSeek reasoning）
  /// 与 [parseStreamingResult]（OpenAI tool_calls）复用：
  /// - 跳过非 data 行、空 payload、[DONE] 哨兵
  /// - 解析失败只 warn 一次，不影响后续帧
  /// - 返回的字符串列表可能为空（取决于该帧只更新了哪类字段）
  static (List<String>, List<String>) _parseDataPayload(String raw) {
    final content = <String>[];
    final reasoning = <String>[];

    final lines = raw.split('\n');
    for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;

      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final first = choices.first as Map<String, dynamic>;
        final delta = first['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        // reasoning_content（DeepSeek thinking 扩展）
        final rc = delta['reasoning_content'];
        if (rc is String && rc.isNotEmpty) {
          reasoning.add(rc);
        }

        // 正常 content
        final c = delta['content'];
        if (c is String && c.isNotEmpty) {
          content.add(c);
        }
      } catch (_) {
        LoggerService.instance.w(
          'SSE 行解析失败: $line',
          category: LogCategory.ai,
          tags: ['dsl', 'llm', 'sse'],
        );
        // 忽略解析失败
      }
    }

    return (content, reasoning);
  }

  /// 解析带 reasoning_content 的 SSE 流（DeepSeek thinking 格式）
  static SseParseResult parseSseStreamWithReasoning(String raw) {
    final (content, reasoning) = _parseDataPayload(raw);
    return SseParseResult(content: content, reasoning: reasoning);
  }

  /// 解析流式响应为 StreamingResult（Phase 1: 支持 tool_calls）
  ///
  /// 复用 [_parseDataPayload] 提取 content / reasoning，额外收集
  /// delta.tool_calls 列表。
  static StreamingResult parseStreamingResult(String raw) {
    final (contentChunks, reasoningChunks) = _parseDataPayload(raw);
    final toolCallDeltas = <Map<String, dynamic>>[];

    final lines = raw.split('\n');
    for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final first = choices.first as Map<String, dynamic>;
        final delta = first['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;
        final tcDeltas = delta['tool_calls'] as List?;
        if (tcDeltas != null) {
          for (final tc in tcDeltas) {
            if (tc is Map<String, dynamic>) {
              toolCallDeltas.add(tc);
            }
          }
        }
      } catch (_) {
        // tool_calls 解析失败独立 warn，骨架里已有内容/推理 warn，不会重复
        LoggerService.instance.w(
          'SSE tool_calls 解析失败: $line',
          category: LogCategory.ai,
          tags: ['dsl', 'llm', 'sse', 'tool_calls'],
        );
      }
    }

    return StreamingResult(
      contentChunks: contentChunks,
      reasoningChunks: reasoningChunks,
      toolCallDeltas: toolCallDeltas,
    );
  }
}

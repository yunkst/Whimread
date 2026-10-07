/// LLM Provider — API 门面与 HTTP 抽象
///
/// 从原 `llm_provider.dart` 上帝文件拆分。本文件承载：
/// [LlmHttpClient] 抽象接口、[LlmStreamChunk] 流式帧模型、
/// [LlmProvider] 业务门面（chatStream / chatStreamWithTools）、
/// 以及流式响应行分割器 [LineSplitter]。
library;

import 'dart:async';
import 'dart:convert';

import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_config.dart';

// -- LLM Provider --

/// HTTP 客户端抽象（便于测试和替换真实 HTTP 库）
abstract class LlmHttpClient {
  Future<String> postJson(String url, Map<String, String> headers, String body);
  Stream<String> postJsonStream(
      String url, Map<String, String> headers, String body);
}

/// 具备可释放资源的传输层（可选能力接口）。
///
/// [LlmProvider.dispose] 据此把释放转发给真实传输实现，
/// 测试 fake 不实现即自动 no-op，不被迫加方法。
abstract class DisposableTransport {
  void dispose();
}

/// LLM 响应 usage 统计（OpenAI 兼容 `usage` 字段的被动解析结果）
///
/// 部分 OpenAI 兼容网关（DeepSeek 等）在流式末帧默认附带 usage；
/// OpenAI 官方需 `stream_options.include_usage`（本项目不主动发送，
/// 避免个别兼容网关 400）。字段缺失时为 null，消费方走启发式 fallback。
class LlmUsage {
  final int? promptTokens;
  final int? completionTokens;

  const LlmUsage({this.promptTokens, this.completionTokens});

  @override
  String toString() =>
      'LlmUsage(prompt=$promptTokens, completion=$completionTokens)';
}

/// 流式 chat completion 的单帧事件
///
/// - [contentChunk] 文本增量（可能为空，例如当帧只更新 tool_calls）
/// - [toolCallDeltas] tool_calls 增量列表（可能为空）
/// - [finishReason] 当 LLM 完成一帧响应时由 choices[].finish_reason 给出；
///   - null 表示中间帧（未完成）
///   - 'stop' 表示文本流式结束
///   - 'tool_calls' 表示 LLM 决定调用工具
///   - 'length' 表示达到 max_tokens 上限
///   - 'content_filter' / 其他
/// - [usage] 部分网关在末帧附带（choices 常为空数组）；供 AgentLoop 做
///   真实 token 压缩判定，不参与常规 chunk 过滤。
class LlmStreamChunk {
  final String? contentChunk;
  final List<Map<String, dynamic>> toolCallDeltas;
  final String? finishReason;
  final LlmUsage? usage;

  /// 思维链增量（DeepSeek `reasoning_content` 扩展；仅部分模型/网关提供）。
  /// 仅供 UI 展示（如文字游戏"GM 思考"开关），不参与任何业务逻辑。
  final String? reasoningChunk;

  const LlmStreamChunk({
    this.contentChunk,
    this.toolCallDeltas = const [],
    this.finishReason,
    this.usage,
    this.reasoningChunk,
  });

  bool get isContent => contentChunk != null && contentChunk!.isNotEmpty;
  bool get isToolCallDelta => toolCallDeltas.isNotEmpty;
  bool get isReasoning => reasoningChunk != null && reasoningChunk!.isNotEmpty;
  bool get isFinished => finishReason != null;
  bool get hasUsage => usage != null;

  @override
  String toString() =>
      'LlmStreamChunk(content=$contentChunk, deltas=${toolCallDeltas.length}, '
      'reasoning=$reasoningChunk, finish=$finishReason, usage=$usage)';
}

class LlmProvider {
  final LlmConfig config;
  final LlmHttpClient _httpClient;

  /// 构造时必须注入 [httpClient]，编译期强制非空，
  /// 杜绝运行时才发现 httpClient 缺失（替代原 _requireHttpClient null 检查）。
  LlmProvider(this.config, {required LlmHttpClient httpClient})
      : _httpClient = httpClient;

  /// 释放底层传输资源（io.HttpClient 连接池）。
  ///
  /// [LlmHttpClient] 是接口，为不影响测试 fake 的实现面，这里按可选能力
  /// 接口向下转发：未实现 [DisposableTransport] 的（mock/fake）为 no-op。
  void dispose() {
    final Object transport = _httpClient;
    if (transport is DisposableTransport) transport.dispose();
  }

  /// chat completions 端点 URL
  String get chatCompletionsUrl {
    var base = config.baseUrl;
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/chat/completions';
  }

  /// 构建请求体（Phase 1: 增加 tools / toolChoice 参数）
  ///
  /// 不发送 max_tokens：输出长度交给模型 / provider 原生上限。
  ///
  /// model 字段缺省 / 显式空字符串 → 不写入 body，由服务端按 catalog baseline
  /// 兜底（否则空字符串会被 OpenAI 兼容网关解读为「指定空 model」而 400）。
  Map<String, dynamic> buildRequestBody({
    required List<ChatMessage> messages,
    bool stream = false,
    String? model,
    double? temperature,
    Map<String, dynamic>? responseFormat,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
    Map<String, dynamic>? extra,
  }) {
    final resolvedModel = model ?? config.defaultModel;
    final body = <String, dynamic>{
      if (resolvedModel.isNotEmpty) 'model': resolvedModel,
      'stream': stream,
      'temperature': temperature ?? config.temperature,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    if (responseFormat != null) {
      body['response_format'] = responseFormat;
    }
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = _normalizeToolsSchema(tools);
    }
    if (toolChoice != null && toolChoice.isNotEmpty) {
      body['tool_choice'] = toolChoice;
    }
    if (extra != null) {
      body.addAll(extra);
    }
    return body;
  }

  /// 规范化 function 工具 schema，补全缺失的 `required` 字段。
  List<Map<String, dynamic>> _normalizeToolsSchema(
    List<Map<String, dynamic>> tools,
  ) {
    return tools.map((tool) {
      final fn = tool['function'];
      if (fn is! Map<String, dynamic>) return tool;
      final params = fn['parameters'];
      if (params is! Map<String, dynamic>) return tool;
      if (params.containsKey('required')) return tool;
      final newParams = Map<String, dynamic>.from(params);
      newParams['required'] = <String>[];
      final newFn = Map<String, dynamic>.from(fn);
      newFn['parameters'] = newParams;
      final newTool = Map<String, dynamic>.from(tool);
      newTool['function'] = newFn;
      return newTool;
    }).toList();
  }

  /// 默认请求头
  Map<String, String> get defaultHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      };

  /// 解析阻塞响应为 LlmResponse（Phase 1: 支持 tool_calls）
  static LlmResponse parseBlockingResponse(String rawBody) {
    final json = jsonDecode(rawBody) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      LoggerService.instance.w(
        'LLM 返回空响应（choices 为空）',
        category: LogCategory.ai,
        tags: ['dsl', 'llm', 'empty_response'],
      );
      return const LlmResponse();
    }
    final first = choices.first as Map<String, dynamic>;
    final message = first['message'] as Map<String, dynamic>?;
    if (message == null) {
      return LlmResponse(content: (first['text'] as String?) ?? '');
    }
    final content = (message['content'] as String?) ?? '';
    final toolCallsRaw = message['tool_calls'] as List?;
    final toolCalls = toolCallsRaw
            ?.map((tc) => ToolCall.fromJson(tc as Map<String, dynamic>))
            .toList() ??
        [];
    return LlmResponse(content: content, toolCalls: toolCalls);
  }

  Stream<String> chatStream({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
    Map<String, dynamic>? responseFormat,
  }) {
    LoggerService.instance.d(
      'LLM chatStream 流式调用入口: model=${model ?? config.defaultModel}, '
      'messages=${messages.length}, baseUrl=${config.baseUrl}, '
      'temperature=${temperature ?? config.temperature}',
      category: LogCategory.ai,
      tags: ['dsl', 'llm'],
    );
    final client = _httpClient;
    final body = buildRequestBody(
      messages: messages,
      model: model,
      temperature: temperature,
      responseFormat: responseFormat,
      tools: null,
      stream: true,
    );
    return client
        .postJsonStream(chatCompletionsUrl, defaultHeaders, jsonEncode(body))
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trim())
        .where((payload) => payload.isNotEmpty && payload != '[DONE]')
        .map((payload) {
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) return '';
        final first = choices.first as Map<String, dynamic>;
        final delta = first['delta'] as Map<String, dynamic>?;
        return (delta?['content'] as String?) ?? '';
      } catch (_) {
        return '';
      }
    }).where((chunk) => chunk.isNotEmpty);
  }

  /// 流式调用（支持 tools + tool_calls delta 聚合）
  Stream<LlmStreamChunk> chatStreamWithTools({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
  }) async* {
    LoggerService.instance.d(
      'LLM chatStreamWithTools 流式+工具调用入口: '
      'model=${model ?? config.defaultModel}, '
      'messages=${messages.length}, tools=${tools?.length ?? 0}, '
      'toolChoice=$toolChoice',
      category: LogCategory.ai,
      tags: ['dsl', 'llm', 'stream-tools'],
    );
    final client = _httpClient;
    final body = buildRequestBody(
      messages: messages,
      model: model,
      temperature: temperature,
      tools: tools,
      toolChoice: toolChoice,
      stream: true,
    );
    yield* client
        .postJsonStream(chatCompletionsUrl, defaultHeaders, jsonEncode(body))
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trim())
        .where((payload) => payload.isNotEmpty && payload != '[DONE]')
        .map((payload) {
      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        // 被动解析 usage：部分网关在末帧附带（OpenAI 兼容）。
        // choices 经常是空数组（usage-only 帧），不能直接 skip。
        final usage = _parseUsage(json['usage']);
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          if (usage != null) return LlmStreamChunk(usage: usage);
          return const LlmStreamChunk();
        }
        final first = choices.first as Map<String, dynamic>;
        final delta = first['delta'] as Map<String, dynamic>?;
        if (delta == null) {
          final finishReason = first['finish_reason'] as String?;
          if (finishReason != null) {
            return LlmStreamChunk(finishReason: finishReason, usage: usage);
          }
          if (usage != null) return LlmStreamChunk(usage: usage);
          return const LlmStreamChunk();
        }
        final content = (delta['content'] as String?) ?? '';
        final reasoning = (delta['reasoning_content'] as String?) ?? '';
        final tcDeltas = <Map<String, dynamic>>[];
        final tcRaw = delta['tool_calls'] as List?;
        if (tcRaw != null) {
          for (final tc in tcRaw) {
            if (tc is Map<String, dynamic>) {
              tcDeltas.add(tc);
            }
          }
        }
        final finishReason = first['finish_reason'] as String?;
        return LlmStreamChunk(
          contentChunk: content.isNotEmpty ? content : null,
          reasoningChunk: reasoning.isNotEmpty ? reasoning : null,
          toolCallDeltas: tcDeltas,
          finishReason: finishReason,
          usage: usage,
        );
      } catch (e) {
        LoggerService.instance.w(
          'chatStreamWithTools SSE 行解析失败: $e',
          category: LogCategory.ai,
          tags: ['dsl', 'llm', 'stream-tools'],
        );
        return const LlmStreamChunk();
      }
    }).where((chunk) =>
            chunk.isContent ||
            chunk.isToolCallDelta ||
            chunk.isReasoning ||
            chunk.isFinished ||
            chunk.hasUsage);
  }

  /// 解析 OpenAI 兼容 SSE 帧的 usage 字段。字段缺失或类型不匹配返回 null。
  static LlmUsage? _parseUsage(dynamic raw) {
    if (raw is! Map) return null;
    final pt = raw['prompt_tokens'];
    final ct = raw['completion_tokens'];
    final prompt = pt is int ? pt : null;
    final completion = ct is int ? ct : null;
    if (prompt == null && completion == null) return null;
    return LlmUsage(promptTokens: prompt, completionTokens: completion);
  }
}

/// 流式响应行分割器 — 将 chunked stream 按换行切分。
///
/// 原 `_LineSplitter`（私有）升级为公开 [LineSplitter]，供本模块内
/// [LlmProvider.chatStream]/[chatStreamWithTools] 共用。
/// 仅限库内使用，不对外暴露为 public API 的一部分。
class LineSplitter extends StreamTransformerBase<String, String> {
  const LineSplitter();

  @override
  Stream<String> bind(Stream<String> stream) {
    final controller = StreamController<String>();
    final buffer = StringBuffer();
    StreamSubscription<String>? subscription;
    controller.onCancel = () {
      // 下游取消（用户中断生成 / await for 提前 break）时同步取消上游订阅，
      // 否则 HTTP 连接会继续读取完整响应——白耗流量并占用连接池
      return subscription?.cancel();
    };
    subscription = stream.listen(
      (data) {
        buffer.write(data);
        final s = buffer.toString();
        final lines = s.split('\n');
        for (var i = 0; i < lines.length - 1; i++) {
          if (lines[i].isNotEmpty) controller.add(lines[i]);
        }
        buffer.clear();
        buffer.write(lines.last);
      },
      onError: controller.addError,
      onDone: () {
        if (buffer.isNotEmpty) controller.add(buffer.toString());
        controller.close();
      },
      cancelOnError: false,
    );
    return controller.stream;
  }
}
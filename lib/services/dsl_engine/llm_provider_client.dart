/// LLM Provider — dart:io HTTP 传输实现
///
/// 从原 `llm_provider.dart` 上帝文件拆分。本文件承载：
/// [IoLlmHttpClient] 基于 dart:io 的真实 HTTP 客户端（含 withRetry 重试包装）、
/// 流式握手辅助 [_StreamHandshake]、LLM 日志拦截、以及 HTTP 错误统一处理。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:novel_app/services/llm_logger/llm_logger.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/utils/retry_helper.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_core.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_sse.dart';

// ---------------------------------------------------------------------------
// IoLlmHttpClient: 使用 dart:io HttpClient 的真实 HTTP 客户端
// ---------------------------------------------------------------------------

/// 流式握手阶段的结果（握手成功后供 [IoLlmHttpClient._wrapStreamWithLogging] 落盘）
class _StreamHandshake {
  final Stream<String> bodyStream;
  final String logId;
  final Stopwatch stopwatch;
  final StringBuffer responseBuffer;
  _StreamHandshake({
    required this.bodyStream,
    required this.logId,
    required this.stopwatch,
    required this.responseBuffer,
  });
}

/// 基于 dart:io HttpClient 的 LlmHttpClient 实现
class IoLlmHttpClient implements LlmHttpClient {
  // connectionTimeout: TCP/TLS 建连超时；idleTimeout: 空闲连接超时
  final io.HttpClient _client = io.HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 60);

  /// 重试预算（传输层 maxAttempts 单一真理源，可由 [AiServiceFactory] 注入）
  final LlmRetryBudget _budget;

  IoLlmHttpClient({LlmRetryBudget? budget})
      : _budget = budget ?? const LlmRetryBudget();

  @override
  Future<String> postJson(
      String url, Map<String, String> headers, String body) async {
    return withRetry(
      () => _postJsonOnce(url, headers, body),
      config: RetryConfig(maxAttempts: _budget.transportBlockingMaxAttempts),
      label: 'llm_post',
      onRetry: (a, m, d, e) {
        try {
          RetrySignals.instance.reportTransport(
            attempt: a,
            maxAttempts: m,
            delayMs: d,
            error: e,
          );
        } catch (ex, st) {
          LoggerService.instance.w(
            '重试信号上报(transport)失败: $ex',
            category: LogCategory.ai,
            tags: ['retry-signal', 'report-failed'],
            stackTrace: st.toString(),
          );
        }
      },
    );
  }

  /// 单次 HTTP 调用（被 [postJson] 包装重试）
  Future<String> _postJsonOnce(
      String url, Map<String, String> headers, String body) async {
    final logId = _generateLogId();
    final stopwatch = Stopwatch()..start();
    LlmLogger.instance.logRequest(
      id: logId, endpoint: url, requestBody: body, isStreaming: false,
    );

    final uri = Uri.parse(url);
    final request = await _client.postUrl(uri);
    headers.forEach((k, v) => request.headers.set(k, v));
    request.add(utf8.encode(body));
    final response = await request.close();
    final statusCode = response.statusCode;
    final responseBody = await response.transform(utf8.decoder).join();

    stopwatch.stop();
    final isSuccess = statusCode < 400;
    LlmLogger.instance.logResponse(
      id: logId, responseBody: responseBody,
      durationMs: stopwatch.elapsedMilliseconds, isSuccess: isSuccess,
      errorMessage: isSuccess ? null : 'HTTP $statusCode',
    );

    if (statusCode >= 400) {
      _handleHttpFailure(
        response: response, responseBody: responseBody,
        url: url, headers: headers, body: body,
        logId: logId, stopwatch: stopwatch, isStreaming: false,
      );
    }
    RetrySignals.instance.clear();
    return responseBody;
  }

  @override
  Stream<String> postJsonStream(
      String url, Map<String, String> headers, String body) async* {
    final handshake = await withRetry(
      () => _postJsonStreamHandshake(url, headers, body),
      config: RetryConfig(maxAttempts: _budget.transportStreamMaxAttempts),
      label: 'llm_stream_establish',
      onRetry: (a, m, d, e) {
        try {
          RetrySignals.instance.reportTransport(
            attempt: a, maxAttempts: m, delayMs: d, error: e,
          );
        } catch (ex, st) {
          LoggerService.instance.w(
            '重试信号上报(stream transport)失败: $ex',
            category: LogCategory.ai,
            tags: ['retry-signal', 'report-failed'],
            stackTrace: st.toString(),
          );
        }
      },
    );

    yield* _wrapStreamWithLogging(
      handshake.bodyStream, handshake.logId,
      handshake.stopwatch, handshake.responseBuffer,
    );
  }

  Future<_StreamHandshake> _postJsonStreamHandshake(
      String url, Map<String, String> headers, String body) async {
    final logId = _generateLogId();
    final stopwatch = Stopwatch()..start();
    final responseBuffer = StringBuffer();
    LlmLogger.instance.logRequest(
      id: logId, endpoint: url, requestBody: body, isStreaming: true,
    );

    final uri = Uri.parse(url);
    final request = await _client.postUrl(uri);
    headers.forEach((k, v) => request.headers.set(k, v));
    request.add(utf8.encode(body));
    final response = await request.close();
    final statusCode = response.statusCode;
    if (statusCode >= 400) {
      final errorBody = await response.transform(utf8.decoder).join();
      stopwatch.stop();
      LlmLogger.instance.logResponse(
        id: logId, responseBody: errorBody,
        durationMs: stopwatch.elapsedMilliseconds, isSuccess: false,
        errorMessage: 'HTTP $statusCode',
      );
      _handleHttpFailure(
        response: response, responseBody: errorBody,
        url: url, headers: headers, body: body,
        logId: logId, stopwatch: stopwatch, isStreaming: true,
      );
    }
    RetrySignals.instance.clear();
    return _StreamHandshake(
      bodyStream: response.transform(utf8.decoder),
      logId: logId, stopwatch: stopwatch, responseBuffer: responseBuffer,
    );
  }

  Stream<String> _wrapStreamWithLogging(
    Stream<String> source, String logId,
    Stopwatch stopwatch, StringBuffer buffer,
  ) async* {
    try {
      await for (final chunk in source) {
        buffer.write(chunk);
        yield chunk;
      }
      stopwatch.stop();
      LlmLogger.instance.logResponse(
        id: logId,
        responseBody: _reconstructStreamedJson(buffer.toString()),
        durationMs: stopwatch.elapsedMilliseconds,
        isSuccess: true,
      );
    } catch (e) {
      stopwatch.stop();
      LlmLogger.instance.logError(
        id: logId, errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  static String _reconstructStreamedJson(String raw) {
    final result = SseParser.parseStreamingResult(raw);
    Map<String, dynamic>? usage;
    String? finishReason;
    for (final line in raw.split('\n')) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final obj = jsonDecode(payload) as Map<String, dynamic>;
        final u = obj['usage'] as Map<String, dynamic>?;
        if (u != null) usage = u;
        final choices = obj['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final fr = (choices.first as Map<String, dynamic>)['finish_reason'];
          if (fr is String) finishReason = fr;
        }
      } catch (e, st) {
        LoggerService.instance.w(
          'SSE finish_reason/token-usage 解析失败: $e',
          category: LogCategory.ai,
          tags: ['sse-parse', 'parse-err'],
          stackTrace: st.toString(),
        );
      }
    }
    final content = result.fullContent;
    final reasoning = result.reasoningChunks.join();
    final toolCalls = result.buildToolCalls();
    if (content.isEmpty && reasoning.isEmpty && toolCalls.isEmpty &&
        usage == null && finishReason == null) {
      return jsonEncode({
        '_stream_raw': raw,
        '_note': 'SSE 解析未提取到有效内容，保留原始流文本',
      });
    }
    final message = <String, dynamic>{
      'role': 'assistant',
      if (content.isNotEmpty) 'content': content,
    };
    if (reasoning.isNotEmpty) message['reasoning_content'] = reasoning;
    if (toolCalls.isNotEmpty) {
      message['tool_calls'] = toolCalls.map((t) => t.toJson()).toList();
    }
    return jsonEncode({
      'object': 'chat.completion',
      'choices': [{
        'index': 0, 'finish_reason': finishReason ?? 'stop',
        'message': message,
      }],
      if (usage != null) 'usage': usage,
      '_stream_meta': {
        'raw_size': raw.length,
        'content_chunk_count': result.contentChunks.length,
      },
    });
  }

  static String _buildHttpErrorContext(String url, Map<String, String> headers,
      String body, String responseBody) {
    String model = 'unknown';
    int messageCount = -1;
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      model = decoded['model']?.toString() ?? 'unknown';
      final messages = decoded['messages'];
      if (messages is List) messageCount = messages.length;
    } catch (e, st) {
      LoggerService.instance.w(
        'LLM请求body model字段提取失败: $e',
        category: LogCategory.ai,
        tags: ['llm-provider-client', 'parse-err'],
        stackTrace: st.toString(),
      );
    }
    final hasApiKey = headers['Authorization']?.isNotEmpty == true ||
        headers['authorization']?.isNotEmpty == true;
    final errorSnippet = responseBody.length > 1000
        ? '${responseBody.substring(0, 1000)}...(truncated)'
        : responseBody;
    return [
      'LLM HTTP 错误诊断上下文:',
      '  url: $url', '  model: $model',
      '  messages: $messageCount 条',
      '  requestBodySize: ${body.length} 字节',
      '  apiKeyConfigured: $hasApiKey',
      '  responseBody: $errorSnippet',
    ].join('\n');
  }

  static Never _handleHttpFailure({
    required io.HttpClientResponse response,
    required String responseBody,
    required String url,
    required Map<String, String> headers,
    required String body,
    required String logId,
    required Stopwatch stopwatch,
    required bool isStreaming,
  }) {
    final statusCode = response.statusCode;
    final tag = isStreaming ? 'stream_establish' : 'post_json';
    final label = isStreaming ? ' (stream)' : '';
    final retryAfterMs = parseRetryAfterMs(
      response.headers.value('retry-after'),
    );
    LoggerService.instance.w(
      'LLM HTTP $statusCode$label (retryable): '
      '${retryAfterMs != null ? 'retryAfter=${retryAfterMs}ms, ' : ''}'
      'url=$url',
      category: LogCategory.ai,
      stackTrace: _buildHttpErrorContext(url, headers, body, responseBody),
      tags: ['dsl', 'llm', 'http', tag, 'retryable'],
    );
    throw RetryableHttpException(
      statusCode, responseBody, url, retryAfterMs: retryAfterMs,
    );
  }
}

/// 生成 LLM 日志记录 ID（时间戳 + 随机后缀）
String _generateLogId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rand = Random().nextInt(9999).toString().padLeft(4, '0');
  return 'llm_${ts}_$rand';
}
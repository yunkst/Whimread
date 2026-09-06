/// LLM 调用日志记录的数据模型。
///
/// 用法：由 [LlmLogger] 自动创建，不需要手动构造。
/// 通过 [LlmLogger.getRecent] / [LlmLogger.getById] 查询后使用。
class LlmCallRecord {
  final String id;
  final DateTime timestamp;
  final String endpoint;
  final String? model;
  final bool isStreaming;

  /// 完整的请求体 JSON 字符串
  final String requestBody;

  /// 完整的响应体 JSON 字符串（流式为拼接后的完整内容）
  final String? responseBody;

  /// 请求耗时（毫秒），null 表示未完成或异常中断
  final int? durationMs;

  final bool isSuccess;
  final String? errorMessage;

  /// token 使用统计
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const LlmCallRecord({
    required this.id,
    required this.timestamp,
    required this.endpoint,
    this.model,
    required this.isStreaming,
    required this.requestBody,
    this.responseBody,
    this.durationMs,
    required this.isSuccess,
    this.errorMessage,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  /// 从 JSONL 行反序列化
  factory LlmCallRecord.fromJson(Map<String, dynamic> json) {
    return LlmCallRecord(
      id: json['id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int,
        isUtc: true,
      ),
      endpoint: json['endpoint'] as String,
      model: json['model'] as String?,
      isStreaming: json['is_streaming'] as bool? ?? false,
      requestBody: json['request_body'] as String? ?? '',
      responseBody: json['response_body'] as String?,
      durationMs: json['duration_ms'] as int?,
      isSuccess: json['is_success'] as bool? ?? false,
      errorMessage: json['error_message'] as String?,
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
    );
  }

  /// 序列化为 JSON（用于写入 JSONL）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'endpoint': endpoint,
      'model': model,
      'is_streaming': isStreaming,
      'request_body': requestBody,
      'response_body': responseBody,
      'duration_ms': durationMs,
      'is_success': isSuccess,
      'error_message': errorMessage,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'total_tokens': totalTokens,
    };
  }

  /// 列表页预览文本：取 requestBody 中 messages 最后一项 content 前 80 字符
  String get previewText {
    try {
      final body = requestBody;
      // 简单正则提取最后 content
      final contentRegex = RegExp(r'"content"\s*:\s*"([^"]{0,80})');
      final matches = contentRegex.allMatches(body);
      if (matches.isNotEmpty) {
        return matches.last.group(1) ?? '';
      }
      return body.length > 80 ? body.substring(0, 80) : body;
    } catch (_) {
      return requestBody.length > 80 ? requestBody.substring(0, 80) : requestBody;
    }
  }

  /// 格式化耗时
  String get durationText {
    if (durationMs == null) return '-';
    if (durationMs! < 1000) return '${durationMs}ms';
    return '${(durationMs! / 1000).toStringAsFixed(1)}s';
  }

  LlmCallRecord copyWith({
    String? responseBody,
    int? durationMs,
    bool? isSuccess,
    String? errorMessage,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
  }) {
    return LlmCallRecord(
      id: id,
      timestamp: timestamp,
      endpoint: endpoint,
      model: model,
      isStreaming: isStreaming,
      requestBody: requestBody,
      responseBody: responseBody ?? this.responseBody,
      durationMs: durationMs ?? this.durationMs,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      totalTokens: totalTokens ?? this.totalTokens,
    );
  }
}

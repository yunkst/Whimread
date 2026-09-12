/// 用户反馈提交服务
///
/// 把用户在 [FeedbackSubmitScreen] 填写的问题报告(可选附带近期日志 + LLM
/// 调用日志)提交到 feedback 云函数(`POST /api/v1/feedback/submit`)。
/// native 崩溃上报 ([NativeCrashReporter]) 也走本服务(kind=nativeCrash)。
///
/// 职责边界:
/// - 只负责「一次性提交」;持续批量上报是 [LogReporterService] 的事
/// - 应用日志采集来自 [LoggerService.instance.getLogs()] 内存环形队列,
///   cap 300 条 + 单条 message 截断 500 字符,与 feedback 云函数入参上限对齐
/// - LLM 调用日志采集来自 [LlmLogger.instance.getRecent()],
///   上限 10 条 + 单条 response 截断 20K 字符 + 总字符预算 128KB(防 body 越 512KB)。
///   SSE 流式请求在 LlmLogger 侧已聚合为单条 chat.completion 形态 JSON(见
///   IoLlmHttpClient._reconstructStreamedJson),无需客户端再拼接。
/// - host 解析 / JWT 鉴权 / Dio 超时与 [LogReporterService] 完全同源
///
/// 失败语义:抛 [FeedbackSubmitException],UI 层捕获后 inline 展示,
/// 表单内容不丢。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        visibleForTesting;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/backend/backend_config.dart';
import 'device/device_auth_service.dart';
import 'llm_logger/llm_call_record.dart';
import 'llm_logger/llm_logger.dart';
import 'logger_service.dart';

/// 反馈来源(与服务端 feedback_reports.kind 枚举对齐)
enum FeedbackKind {
  userReport('user_report'),
  nativeCrash('native_crash');

  final String wire;
  const FeedbackKind(this.wire);
}

/// 反馈类别(UI 分类,与服务端 category 枚举对齐)
enum FeedbackCategory {
  bug('bug', 'Bug 报告'),
  feature('feature', '功能建议'),
  usage('usage', '使用问题');

  final String wire;
  final String label;
  const FeedbackCategory(this.wire, this.label);
}

/// 提交成功结果
class FeedbackSubmitResult {
  final int reportId;
  final int logCount;

  /// LLM 调用日志落库条数(未勾选或落库失败为 0)
  final int llmLogCount;
  final DateTime? createdAt;

  const FeedbackSubmitResult({
    required this.reportId,
    required this.logCount,
    this.llmLogCount = 0,
    this.createdAt,
  });

  factory FeedbackSubmitResult.fromJson(Map<String, dynamic> json) {
    return FeedbackSubmitResult(
      reportId: (json['report_id'] as num).toInt(),
      logCount: (json['log_count'] as num?)?.toInt() ?? 0,
      llmLogCount: (json['llm_log_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

/// 提交失败([code] 为服务端错误码或本地错误码,如 NO_BACKEND / NETWORK)
class FeedbackSubmitException implements Exception {
  final String code;
  final String message;

  const FeedbackSubmitException(this.code, this.message);

  @override
  String toString() => 'FeedbackSubmitException($code): $message';
}

class FeedbackService {
  static final FeedbackService instance = FeedbackService._internal();
  FeedbackService._internal();

  /// 测试专用构造器:供测试 fake 继承时 super() 调用。
  @visibleForTesting
  FeedbackService.forTest();

  Dio? _dio;

  /// 外部注入的 Dio（通常来自 ApiServiceWrapper.dio，共享连接池与
  /// 401 续签拦截器）。null 时 `submit` 会用精简配置自建兜底。
  ///
  /// 由 APP 启动时注入，避免日志风暴：共享 Dio 的 QuietLogInterceptor
  /// 会尊重本服务提交请求里的 `quiet` 标记。
  Dio? _dioOverride;

  /// 注入共享 Dio（APP 启动时由 main.dart 调用一次）
  ///
  /// 若此前的 `submit` 已自建兜底 Dio，这里替换为共享实例并关闭旧实例。
  void useDio(Dio dio) {
    final old = _dio;
    _dioOverride = dio;
    if (old != null && !identical(old, dio)) {
      old.close(force: true);
      _dio = dio;
    }
  }

  /// 日志附加上限(与云函数 MAX_LOG_ENTRIES_PER_REPORT 对齐)
  static const int maxAttachedLogs = 300;

  /// 单条日志 message 截断长度(与云函数 MAX_LOG_MESSAGE 对齐)
  static const int maxLogMessageChars = 500;

  /// LLM 调用日志附加上限(与云函数 MAX_LLM_ENTRIES_PER_REPORT 对齐)
  static const int maxAttachedLlmLogs = 10;

  /// LLM 单条 response_body 截断长度(与云函数 MAX_LLM_RESPONSE_CHARS 对齐)
  ///
  /// LlmLogger 落盘的 responseBody 单条上限 5MB,反馈携带必须大幅截断;
  /// SSE 聚合后大多在 2-10KB 区间,20KB 能覆盖完整 chat.completion JSON。
  static const int maxLlmResponseChars = 20000;

  /// LLM 日志总字符预算(防止 body 越 512KB 上限)。
  ///
  /// 计算依据:512KB body - 5KB 描述/标题/步骤 - 150KB 应用日志(300×500)
  /// - 50KB 其它余量 ≈ 300KB 可用;这里限定 128KB 更安全(LLM 日志可单独
  /// 提交,不需要把全部记录塞进去)。
  static const int maxLlmTotalChars = 128 * 1024;

  /// 提交用户反馈
  ///
  /// [includeLogs] 为 true 时从 [LoggerService] 内存队列采集近期日志一并上传;
  /// 采集为空时按服务端约定自动降级为不附带(不会失败)。
  /// [includeLlmLogs] 同理,采集 [LlmLogger] 最近 N 条 LLM 调用记录(SSE 已聚合);
  /// 总字符预算 [maxLlmTotalChars],超限条目按时间倒序丢弃并标 `truncated=true`。
  Future<FeedbackSubmitResult> submit({
    required String title,
    required String description,
    FeedbackCategory category = FeedbackCategory.bug,
    String? steps,
    String? contact,
    bool includeLogs = false,
    bool includeLlmLogs = false,
    FeedbackKind kind = FeedbackKind.userReport,
  }) async {
    final host = await resolveBackendHost();
    if (host.isEmpty) {
      throw const FeedbackSubmitException(
          'NO_BACKEND', '未配置后端地址,无法提交反馈');
    }

    Map<String, String> authHeaders;
    try {
      authHeaders = await DeviceAuthService.instance.authedHeaders();
    } catch (e) {
      throw FeedbackSubmitException('AUTH_FAILED', '设备鉴权失败: $e');
    }

    final logs = includeLogs ? collectRecentLogs() : const <LogEntry>[];
    final llmLogs = includeLlmLogs
        ? await collectRecentLlmLogs()
        : const <Map<String, dynamic>>[];
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceModel = await _collectDeviceModel();

    final payload = buildPayload(
      title: title,
      description: description,
      category: category,
      steps: steps,
      contact: contact,
      kind: kind,
      logs: logs,
      llmLogs: llmLogs,
      packageInfo: packageInfo,
      deviceModel: deviceModel,
    );

    _dio ??= _dioOverride ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json'},
        ));

    final Response response;
    try {
      response = await _dio!.post(
        '$host/api/v1/feedback/submit',
        data: payload,
        // quiet: 共享 Dio 的 QuietLogInterceptor 跳过本请求的日志打印，
        // 避免反馈附带日志再触发一轮上报
        options: Options(
          headers: authHeaders,
          extra: {'quiet': true},
        ),
      );
    } on DioException catch (e) {
      // 服务端业务错误(4xx 带 code/message)透出给 UI
      final data = e.response?.data;
      if (data is Map && data['code'] is String) {
        throw FeedbackSubmitException(
          data['code'] as String,
          (data['message'] as String?) ?? '提交被拒绝(${e.response?.statusCode})',
        );
      }
      throw FeedbackSubmitException(
          'NETWORK', '网络错误: ${e.message ?? e.type.name}');
    }

    final data = response.data;
    if (data is! Map<String, dynamic> || data['report_id'] == null) {
      throw const FeedbackSubmitException('BAD_RESPONSE', '响应格式异常');
    }
    return FeedbackSubmitResult.fromJson(data);
  }

  /// 从 LoggerService 内存队列采集近期日志
  ///
  /// 策略:优先保留全部 error/warning,再按时间补最近的 info/debug,
  /// 总量 cap [maxAttachedLogs]。产物已按时间升序(日志原始顺序)。
  /// 反馈表单用它在开关打开时预览「将附带 N 条」。
  static List<LogEntry> collectRecentLogs({int maxEntries = maxAttachedLogs}) {
    final all = LoggerService.instance.getLogs();
    if (all.length <= maxEntries) return List.unmodifiable(all);

    final olderWarnings = all
        .take(all.length - maxEntries)
        .where((e) => e.level.index >= LogLevel.warning.index)
        .toList();
    final tail = all.sublist(all.length - maxEntries);
    return [...olderWarnings, ...tail];
  }

  /// 从 LlmLogger 采集最近 LLM 调用记录(已聚合 SSE),按字符预算截断。
  ///
  /// 策略(配合服务端 MAX_LLM_TOTAL_CHARS):
  /// - 先按时间倒序取最近 [maxEntries] 条
  /// - 单条 response_body > [responseCharLimit] 时截断到上限并打 `truncated=true`
  /// - 累计 JSON 序列化字节 > [totalCharBudget] 时,从最早的条目开始丢弃
  ///   (保留最近的)
  ///
  /// 返回 map 列表(序列化后形态,与 buildPayload 直接对接)。
  /// async 是因为 [LlmLogger.getRecent] 可能需要从 JSONL 文件补齐冷启动缓存。
  static Future<List<Map<String, dynamic>>> collectRecentLlmLogs({
    int maxEntries = maxAttachedLlmLogs,
    int responseCharLimit = maxLlmResponseChars,
    int totalCharBudget = maxLlmTotalChars,
  }) async {
    final records = await LlmLogger.instance.getRecent(limit: maxEntries);
    if (records.isEmpty) return const <Map<String, dynamic>>[];

    // 按时间倒序(最近的在前)→ 累计字节超预算时丢最早
    final kept = <Map<String, dynamic>>[];
    var totalChars = 0;
    for (final r in records) {
      final map = _llmRecordToMap(r, responseCharLimit: responseCharLimit);
      // 用 toJson 的字节长度估算(更准确)
      final approx = jsonEncode(map).length;
      if (totalChars + approx > totalCharBudget && kept.isNotEmpty) {
        continue;
      }
      totalChars += approx;
      kept.add(map);
    }
    return List.unmodifiable(kept);
  }

  /// LlmCallRecord → 服务端入参 map
  ///
  /// requestBody 在 LlmLogger 侧已经脱敏为 `model/messages 条数/bytes` 摘要,
  /// 这里直接转发即可(隐私设计:用户小说正文不落盘)。
  /// responseBody 单条截断到 [responseCharLimit] 并打 `truncated=true`,
  /// server 端 [MAX_LLM_RESPONSE_CHARS] 也会做二次截断兜底。
  static Map<String, dynamic> _llmRecordToMap(
    LlmCallRecord r, {
    int responseCharLimit = maxLlmResponseChars,
  }) {
    final rawResponse = r.responseBody;
    String? response;
    var truncated = false;
    if (rawResponse != null) {
      if (rawResponse.length > responseCharLimit) {
        response =
            '${rawResponse.substring(0, responseCharLimit)}\n...[truncated to $responseCharLimit chars, original=${rawResponse.length}]';
        truncated = true;
      } else {
        response = rawResponse;
      }
    }
    return {
      'id': r.id,
      'timestamp': r.timestamp.toUtc().toIso8601String(),
      'endpoint': r.endpoint,
      'model': r.model,
      'is_streaming': r.isStreaming,
      // 已经是脱敏摘要(见 LlmLogger.logRequest 注释)
      'request_summary': r.requestBody,
      'response_body': response,
      'duration_ms': r.durationMs,
      'is_success': r.isSuccess,
      'error_message': r.errorMessage,
      'prompt_tokens': r.promptTokens,
      'completion_tokens': r.completionTokens,
      'total_tokens': r.totalTokens,
      'truncated': truncated,
    };
  }

  /// 构造提交 payload(纯函数,便于单测)
  @visibleForTesting
  static Map<String, dynamic> buildPayload({
    required String title,
    required String description,
    FeedbackCategory category = FeedbackCategory.bug,
    String? steps,
    String? contact,
    FeedbackKind kind = FeedbackKind.userReport,
    required List<LogEntry> logs,
    List<Map<String, dynamic>> llmLogs = const <Map<String, dynamic>>[],
    required PackageInfo packageInfo,
    String? deviceModel,
  }) {
    final attached = logs
        .take(maxAttachedLogs)
        .map((e) => _entryToMap(e))
        .toList();
    return {
      'kind': kind.wire,
      'category': category.wire,
      'title': title,
      'description': description,
      if (steps != null && steps.isNotEmpty) 'steps': steps,
      if (contact != null && contact.isNotEmpty) 'contact': contact,
      'app_version': '${packageInfo.version}+${packageInfo.buildNumber}',
      'platform': defaultTargetPlatform == TargetPlatform.android
          ? 'android'
          : defaultTargetPlatform.name.toLowerCase(),
      if (deviceModel != null) 'device_model': deviceModel,
      'include_logs': attached.isNotEmpty,
      if (attached.isNotEmpty) 'attached_logs': attached,
      'include_llm_logs': llmLogs.isNotEmpty,
      if (llmLogs.isNotEmpty) 'attached_llm_logs': llmLogs,
    };
  }

  /// LogEntry → 服务端入参格式
  ///
  /// level 用枚举 name(debug/info/warning/error),与 feedback 云函数
  /// VALID_LEVELS 白名单对齐;不能用 [LogLevel.label](它是 WARN/ERROR 缩写,
  /// 会被服务端回落成 info)。
  static Map<String, dynamic> _entryToMap(LogEntry entry) {
    var message = entry.message;
    if (message.length > maxLogMessageChars) {
      message = '${message.substring(0, maxLogMessageChars)}…[truncated]';
    }
    return {
      'timestamp': entry.timestamp.toUtc().toIso8601String(),
      'level': entry.level.name,
      'message': message,
      if (entry.stackTrace != null) 'stack_trace': entry.stackTrace,
      'category': entry.category.key,
      'tags': entry.tags,
    };
  }

  /// 设备型号摘要(与 NativeCrashReporter._collectDeviceInfo 同构)
  static Future<String?> _collectDeviceModel() async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return null;
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.model} '
          '(Android ${info.version.release}, SDK ${info.version.sdkInt})';
    } catch (_) {
      return null;
    }
  }
}
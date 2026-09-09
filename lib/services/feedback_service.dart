/// 用户反馈提交服务
///
/// 把用户在 [FeedbackSubmitScreen] 填写的问题报告(可选附带近期日志)提交到
/// feedback 云函数(`POST /api/v1/feedback/submit`)。native 崩溃上报
/// ([NativeCrashReporter]) 也走本服务(kind=nativeCrash)。
///
/// 职责边界:
/// - 只负责「一次性提交」;持续批量上报是 [LogReporterService] 的事
/// - 日志采集来自 [LoggerService.instance.getLogs()] 内存环形队列,
///   cap 300 条 + 单条 message 截断 500 字符,与 feedback 云函数入参上限对齐
/// - host 解析 / JWT 鉴权 / Dio 超时与 [LogReporterService] 完全同源
///
/// 失败语义:抛 [FeedbackSubmitException],UI 层捕获后 inline 展示,
/// 表单内容不丢。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        visibleForTesting;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/constants/build_config.dart';
import 'device/device_auth_service.dart';
import 'logger_service.dart';
import 'preferences_service.dart';

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
  final DateTime? createdAt;

  const FeedbackSubmitResult({
    required this.reportId,
    required this.logCount,
    this.createdAt,
  });

  factory FeedbackSubmitResult.fromJson(Map<String, dynamic> json) {
    return FeedbackSubmitResult(
      reportId: (json['report_id'] as num).toInt(),
      logCount: (json['log_count'] as num?)?.toInt() ?? 0,
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

  /// 日志附加上限(与云函数 MAX_LOG_ENTRIES_PER_REPORT 对齐)
  static const int maxAttachedLogs = 300;

  /// 单条日志 message 截断长度(与云函数 MAX_LOG_MESSAGE 对齐)
  static const int maxLogMessageChars = 500;

  /// 提交用户反馈
  ///
  /// [includeLogs] 为 true 时从 [LoggerService] 内存队列采集近期日志一并上传;
  /// 采集为空时按服务端约定自动降级为不附带(不会失败)。
  Future<FeedbackSubmitResult> submit({
    required String title,
    required String description,
    FeedbackCategory category = FeedbackCategory.bug,
    String? steps,
    String? contact,
    bool includeLogs = false,
    FeedbackKind kind = FeedbackKind.userReport,
  }) async {
    final host = await _resolveHost();
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
      packageInfo: packageInfo,
      deviceModel: deviceModel,
    );

    _dio ??= Dio(BaseOptions(
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
        options: Options(headers: authHeaders),
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

  /// 解析后端 host(与 LogReporterService 同源)
  Future<String> _resolveHost() async {
    if (kHasBundledBackend) return kBackendBaseUrl;
    return await PreferencesService.instance.getString('backend_host');
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
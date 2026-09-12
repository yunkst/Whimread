/// FeedbackService 单元测试 — 仅测纯函数 / 静态助手,不发起真实网络。
///
/// 覆盖:
/// - [FeedbackService.buildPayload] 字段裁剪 / 类别映射 / 日志附带开关
/// - [FeedbackService.collectRecentLogs] error/warning 优先保留策略
/// - [FeedbackService.collectRecentLlmLogs] 单条截断 + 总字符预算 + LLM 日志序列化
/// - [LogEntry] → JSON 序列化 message 截断 + UTC ISO + level name 映射
///
/// 风格参考 `test/unit/services/log_reporter_service_test.dart`,
/// 不引入 mockito(网络层依赖 Dio,留 widget test 覆盖)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/services/feedback_service.dart';
import 'package:novel_app/services/llm_logger/llm_call_record.dart';
import 'package:novel_app/services/llm_logger/llm_logger.dart';
import 'package:novel_app/services/logger_service.dart';

PackageInfo _packageInfo() => PackageInfo(
      appName: 'novel_app',
      packageName: 'com.example.novel_app',
      version: '2.0.2-test',
      buildNumber: '999',
      buildSignature: '',
      installerStore: null,
    );

LogEntry _entry({
  required String message,
  LogLevel level = LogLevel.info,
  LogCategory category = LogCategory.general,
  List<String> tags = const [],
  DateTime? ts,
  String? stackTrace,
}) {
  return LogEntry(
    timestamp: ts ?? DateTime.utc(2026, 9, 9, 10),
    level: level,
    message: message,
    stackTrace: stackTrace,
    category: category,
    tags: tags,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 让下一个 LoggerService.instance 拿到全新空队列
    LoggerService.resetForTesting();
  });

  group('buildPayload - 基础字段', () {
    test('必填字段 + 默认 kind/category 映射正确', () {
      final p = FeedbackService.buildPayload(
        title: '标题',
        description: '描述内容',
        logs: const [],
        packageInfo: _packageInfo(),
        deviceModel: 'Pixel 7 (Android 14, SDK 34)',
      );
      expect(p['kind'], 'user_report');
      expect(p['category'], 'bug');
      expect(p['title'], '标题');
      expect(p['description'], '描述内容');
      expect(p['app_version'], '2.0.2-test+999');
      expect(p['platform'], 'android');
      expect(p['device_model'], 'Pixel 7 (Android 14, SDK 34)');
      expect(p['include_logs'], false);
      expect(p.containsKey('attached_logs'), false);
      expect(p.containsKey('steps'), false);
      expect(p.containsKey('contact'), false);
    });

    test('kind/category 枚举映射到 wire 字符串', () {
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        kind: FeedbackKind.nativeCrash,
        category: FeedbackCategory.feature,
        logs: const [],
        packageInfo: _packageInfo(),
      );
      expect(p['kind'], 'native_crash');
      expect(p['category'], 'feature');
    });

    test('日志数组非空 → 附带(include_logs 由日志非空推导)', () {
      final logs = [
        _entry(message: 'm1'),
        _entry(message: 'm2', level: LogLevel.warning),
      ];
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: logs,
        packageInfo: _packageInfo(),
      );
      expect(p['include_logs'], true);
      final attached = p['attached_logs'] as List;
      expect(attached.length, 2);
      expect((attached[0] as Map)['message'], 'm1');
      expect((attached[1] as Map)['level'], 'warning');
    });

    test('日志数组为空 → include_logs=false 且不带 attached_logs', () {
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: const [],
        packageInfo: _packageInfo(),
      );
      expect(p['include_logs'], false);
      expect(p.containsKey('attached_logs'), false);
    });

    test('steps / contact 空字符串视为未传', () {
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        steps: '',
        contact: '',
        logs: const [],
        packageInfo: _packageInfo(),
      );
      expect(p.containsKey('steps'), false);
      expect(p.containsKey('contact'), false);
    });
  });

  group('buildPayload - 日志条目裁剪', () {
    test('message 超过 500 字符截断 + 标注', () {
      final long = 'A' * 800;
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: [_entry(message: long)],
        packageInfo: _packageInfo(),
      );
      final entry = (p['attached_logs'] as List).first as Map;
      expect((entry['message'] as String).length,
          lessThanOrEqualTo(512)); // 500 + '…[truncated]'(12 字符)
      expect(entry['message'], endsWith('…[truncated]'));
    });

    test('日志条目 cap 在 maxAttachedLogs', () {
      final logs = List.generate(400, (i) => _entry(message: 'm$i'));
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: logs,
        packageInfo: _packageInfo(),
      );
      expect((p['attached_logs'] as List).length,
          FeedbackService.maxAttachedLogs);
    });

    test('timestamp 序列化为 UTC ISO8601 字符串', () {
      final entry = _entry(message: 'm', ts: DateTime(2026, 9, 9, 18));
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: [entry],
        packageInfo: _packageInfo(),
      );
      final out = (p['attached_logs'] as List).first as Map;
      final ts = out['timestamp'] as String;
      expect(ts, endsWith('Z'));
      expect(DateTime.parse(ts).isUtc, true);
    });

    test('level 用枚举 name(与云函数 VALID_LEVELS 白名单对齐,非 label 缩写)',
        () {
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: [
          _entry(message: 'd', level: LogLevel.debug),
          _entry(message: 'i', level: LogLevel.info),
          _entry(message: 'w', level: LogLevel.warning),
          _entry(message: 'e', level: LogLevel.error),
        ],
        packageInfo: _packageInfo(),
      );
      final levels =
          (p['attached_logs'] as List).map((e) => (e as Map)['level']).toList();
      expect(levels, ['debug', 'info', 'warning', 'error']);
    });
  });

  group('collectRecentLogs - 裁剪策略', () {
    test('总数不超过 cap 时原样返回', () {
      LoggerService.instance..i('a')..i('b')..i('c');
      final all = LoggerService.instance.getLogs();
      expect(all.length, 3);
      final got = FeedbackService.collectRecentLogs();
      expect(got.length, 3);
      expect(got.last.message, 'c');
    });

    test('溢出时按自定义 cap 截尾', () {
      LoggerService.instance..i('m1')..i('m2')..i('m3')..i('m4')..i('m5');
      final got = FeedbackService.collectRecentLogs(maxEntries: 2);
      expect(got.length, 2);
      expect(got[0].message, 'm4');
      expect(got[1].message, 'm5');
    });

    test('溢出时 warning+error 优先保留(可能超出 cap)', () {
      LoggerService.instance
        ..e('err_early')
        ..i('i1')
        ..i('i2')
        ..i('i3')
        ..i('i4');
      final got = FeedbackService.collectRecentLogs(maxEntries: 2);
      // 早期 error 被保留 + 最近 2 条 info
      expect(got.length, 3);
      expect(got[0].message, 'err_early');
      expect(got[0].level, LogLevel.error);
      expect(got[1].message, 'i3');
      expect(got[2].message, 'i4');
    });
  });

  group('collectRecentLlmLogs - 截断 / 预算', () {
    LlmCallRecord _record({
      required String id,
      required String response,
      bool isStreaming = true,
      bool isSuccess = true,
      int durationMs = 1000,
      int? promptTokens = 1000,
      int? completionTokens = 200,
      int? totalTokens = 1200,
    }) {
      return LlmCallRecord(
        id: id,
        timestamp: DateTime.utc(2026, 9, 12, 21, 19, 4),
        endpoint: 'https://llm-proxy.example.com/chat/completions',
        model: 'deepseek-ai/DeepSeek-V4-Flash',
        isStreaming: isStreaming,
        // 已脱敏摘要(由 LlmLogger.logRequest 写入)
        requestBody:
            '{"_redacted":"请求正文不落盘（含用户内容）","model":"deepseek-ai/DeepSeek-V4-Flash","messages":7,"bytes":12345}',
        responseBody: response,
        durationMs: durationMs,
        isSuccess: isSuccess,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      );
    }

    setUp(() {
      // 重新初始化单例空队列 + 空 LLM 日志缓存,避免测试间污染
      LlmLogger.resetForTesting();
    });

    test('LlmLogger 未初始化 → 收集结果为空列表(不抛)', () async {
      final got = await FeedbackService.collectRecentLlmLogs();
      expect(got, isEmpty);
    });

    test('最近 N 条被完整序列化:字段命名/类型与后端 sanitize 对齐', () async {
      // token 统计由 LlmLogger.logResponse 从 responseBody.usage 提取
      const responseJson =
          '{"object":"chat.completion","choices":[{"message":{"content":"已替换"}}],'
          '"usage":{"prompt_tokens":4500,"completion_tokens":1200,"total_tokens":5700}}';
      LlmLogger.instance.logResponse(
        id: 'llm_1700000000000_0001',
        responseBody: responseJson,
        durationMs: 1800,
        isSuccess: true,
      );
      final got = await FeedbackService.collectRecentLlmLogs();
      expect(got.length, 1);
      final r = got.first;
      // 字段命名对齐后端 sanitizeLlmLogEntry 入参
      expect(r['id'], 'llm_1700000000000_0001');
      expect(r['model'], isNull); // logResponse 未带 model 时为 null
      expect(r['is_streaming'], false);
      expect(r['is_success'], true);
      expect(r['duration_ms'], 1800);
      expect(r['prompt_tokens'], 4500);
      expect(r['total_tokens'], 5700);
      expect(r['truncated'], false);
      // request_summary 是脱敏的 requestBody,这里为空字符串(只调了 logResponse)
      expect(r['request_summary'], '');
      // response_body 完整保留(原长 < maxLlmResponseChars)
      expect(r['response_body'], contains('已替换'));
      expect((r['response_body'] as String).length,
          lessThan(FeedbackService.maxLlmResponseChars));
      // timestamp 是 ISO8601 UTC
      expect(r['timestamp'], isA<String>());
      expect((r['timestamp'] as String).endsWith('Z'), true);
    });

    test('单条 response_body 超 maxLlmResponseChars → 截断 + truncated=true', () async {
      final big = 'x' * (FeedbackService.maxLlmResponseChars + 5000);
      LlmLogger.instance.logResponse(
        id: 'llm_big', responseBody: big, durationMs: 100,
      );
      final got = await FeedbackService.collectRecentLlmLogs();
      expect(got.length, 1);
      final r = got.first;
      expect(r['truncated'], true);
      final body = r['response_body'] as String;
      // 内容 = 截断段(≤ limit) + marker(to $limit chars, original=$origLen)
      expect(body.length, greaterThan(FeedbackService.maxLlmResponseChars));
      expect(body.length,
          lessThanOrEqualTo(FeedbackService.maxLlmResponseChars + 200));
      expect(body, contains('...[truncated to'));
      expect(body, contains('original=${big.length}'));
    });

    test('多条记录超出总字符预算 maxLlmTotalChars → 丢弃最早,保留最近', () async {
      // getRecent 按 timestamp DESC 返回(insert(0) → 后写的在前)
      // 每条 response 25KB → 截断到 20000+marker ≈ 20.1KB 序列化
      // 自定义预算 50KB → 只能装 2 条(llm_3、llm_2... 按 id 倒序即最新 2 条)
      final big = 'x' * (25 * 1024);
      for (var i = 1; i <= 3; i++) {
        LlmLogger.instance.logResponse(
          id: 'llm_$i',
          responseBody: '$big#$i',
          durationMs: 1000 + i,
        );
      }
      final got = await FeedbackService.collectRecentLlmLogs(
        responseCharLimit: 20000,
        totalCharBudget: 50 * 1024,
      );
      expect(got.length, 2);
      final ids = got.map((m) => m['id']).toList();
      // 保留最新的两条
      expect(ids, ['llm_3', 'llm_2']);
      // 最早的 llm_1 被丢弃
      expect(ids.contains('llm_1'), false);
    });
  });

  group('buildPayload - LLM 日志附带字段', () {
    test('llmLogs 空 → include_llm_logs=false 且不带 attached_llm_logs', () {
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: const [],
        packageInfo: _packageInfo(),
      );
      expect(p['include_llm_logs'], false);
      expect(p.containsKey('attached_llm_logs'), false);
    });

    test('llmLogs 非空 → include_llm_logs=true + 完整字段', () {
      final llmLogs = [
        {
          'id': 'llm_x',
          'timestamp': '2026-09-12T21:19:04.000Z',
          'endpoint': 'https://llm-proxy.example.com/chat/completions',
          'model': 'deepseek-ai/DeepSeek-V4-Flash',
          'is_streaming': true,
          'request_summary': '{"_redacted":"请求正文不落盘（含用户内容）","model":"deepseek-ai/DeepSeek-V4-Flash","messages":7,"bytes":12345}',
          'response_body': '{"object":"chat.completion"}',
          'duration_ms': 1800,
          'is_success': true,
          'error_message': null,
          'prompt_tokens': 4500,
          'completion_tokens': 1200,
          'total_tokens': 5700,
          'truncated': false,
        },
      ];
      final p = FeedbackService.buildPayload(
        title: 't',
        description: 'd',
        logs: const [],
        llmLogs: llmLogs,
        packageInfo: _packageInfo(),
      );
      expect(p['include_llm_logs'], true);
      final attached = p['attached_llm_logs'] as List;
      expect(attached.length, 1);
      expect((attached.first as Map)['id'], 'llm_x');
      expect((attached.first as Map)['is_streaming'], true);
      expect((attached.first as Map)['request_summary'], contains('_redacted'));
    });
  });
}
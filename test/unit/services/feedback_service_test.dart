/// FeedbackService 单元测试 — 仅测纯函数 / 静态助手,不发起真实网络。
///
/// 覆盖:
/// - [FeedbackService.buildPayload] 字段裁剪 / 类别映射 / 日志附带开关
/// - [FeedbackService.collectRecentLogs] error/warning 优先保留策略
/// - [LogEntry] → JSON 序列化 message 截断 + UTC ISO + level name 映射
///
/// 风格参考 `test/unit/services/log_reporter_service_test.dart`,
/// 不引入 mockito(网络层依赖 Dio,留 widget test 覆盖)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/services/feedback_service.dart';
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
}
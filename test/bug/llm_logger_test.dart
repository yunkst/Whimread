import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/llm_logger/llm_logger.dart';
import 'package:novel_app/services/llm_logger/llm_call_record.dart';

import '../test_bootstrap.dart';

/// LlmLogger 单元测试
///
/// 验证核心行为：
/// - logRequest/logResponse 写入内存缓存
/// - getRecent / getById 查询
/// - clear 清空
/// - changeNotifier 在写入/清空后递增（UI 实时刷新依赖）
void main() {
  initTests();

  setUp(() {
    // 不调用 initialize()：保持 _logDir 为 null，使测试只走内存缓存路径，
    // 完全隔离文件系统（避免跨测试历史记录污染 + Windows 文件锁问题）。
    // logResponse 的 _enqueueWrite 在 _logDir==null 时会跳过写文件，不影响内存逻辑。
    LlmLogger.resetForTesting();
  });

  tearDown(() {
    LlmLogger.resetForTesting();
  });

  group('LlmLogger - 写入与查询', () {
    test('logRequest/logResponse 后 getRecent 能读到记录', () async {
      final logger = LlmLogger.instance;
      logger.logRequest(
        id: 'rec-1',
        endpoint: 'https://example.com/v1/chat/completions',
        requestBody: '{"model":"test-model","messages":[{"role":"user",'
            '"content":"hello"}]}',
        isStreaming: false,
      );
      logger.logResponse(
        id: 'rec-1',
        responseBody: '{"id":"resp-1","usage":{"prompt_tokens":5,'
            '"completion_tokens":8,"total_tokens":13}}',
        durationMs: 500,
      );

      final recent = await logger.getRecent(limit: 50);
      expect(recent, hasLength(1));
      expect(recent.first.id, 'rec-1');
      expect(recent.first.model, 'test-model');
      expect(recent.first.totalTokens, 13);
      expect(recent.first.durationMs, 500);
      expect(recent.first.isSuccess, isTrue);
    });

    test('getById 命中已写入记录', () async {
      final logger = LlmLogger.instance;
      logger.logRequest(
        id: 'rec-2',
        endpoint: 'ep',
        requestBody: '{"model":"m"}',
      );
      logger.logResponse(
        id: 'rec-2',
        responseBody: '{"usage":{"total_tokens":42}}',
        durationMs: 100,
      );

      final detail = await logger.getById('rec-2');
      expect(detail, isNotNull);
      expect(detail!.id, 'rec-2');
      expect(detail.totalTokens, 42);
    });

    test('getById 对不存在的 id 返回 null（内存未命中且无文件）', () async {
      final logger = LlmLogger.instance;
      final detail = await logger.getById('not-exist');
      expect(detail, isNull);
    });

    test('logError 标记失败并记录错误信息', () async {
      final logger = LlmLogger.instance;
      logger.logRequest(
        id: 'rec-err',
        endpoint: 'ep',
        requestBody: '{"model":"m"}',
      );
      logger.logError(id: 'rec-err', errorMessage: 'connection timeout');

      final detail = await logger.getById('rec-err');
      expect(detail, isNotNull);
      expect(detail!.isSuccess, isFalse);
      expect(detail.errorMessage, 'connection timeout');
    });

    test('getRecent 按时间倒序返回（最新在前）', () async {
      final logger = LlmLogger.instance;
      for (var i = 0; i < 3; i++) {
        final id = 'order-$i';
        logger.logRequest(id: id, endpoint: 'ep', requestBody: '{}');
        logger.logResponse(
          id: id,
          responseBody: '{}',
          durationMs: i,
        );
      }

      final recent = await logger.getRecent(limit: 50);
      expect(recent, hasLength(3));
      // 最新写入的应在最前
      expect(recent.first.id, 'order-2');
      expect(recent.last.id, 'order-0');
    });
  });

  group('LlmLogger - 清空', () {
    test('clear 清空内存缓存', () async {
      final logger = LlmLogger.instance;
      logger.logRequest(id: 'c-1', endpoint: 'ep', requestBody: '{}');
      logger.logResponse(id: 'c-1', responseBody: '{}', durationMs: 1);

      expect(await logger.getRecent(limit: 50), hasLength(1));

      await logger.clear();
      expect(await logger.getRecent(limit: 50), isEmpty);
    });
  });

  group('LlmLogger - changeNotifier', () {
    test('logResponse 后 changeNotifier.value 递增', () {
      final logger = LlmLogger.instance;
      final before = LlmLogger.changeNotifier.value;

      logger.logRequest(id: 'n-1', endpoint: 'ep', requestBody: '{}');
      logger.logResponse(id: 'n-1', responseBody: '{}', durationMs: 1);

      expect(LlmLogger.changeNotifier.value, greaterThan(before));
    });

    test('logError 后 changeNotifier.value 递增', () {
      final logger = LlmLogger.instance;
      final before = LlmLogger.changeNotifier.value;
      logger.logRequest(id: 'n-2', endpoint: 'ep', requestBody: '{}');
      logger.logError(id: 'n-2', errorMessage: 'err');
      expect(LlmLogger.changeNotifier.value, greaterThan(before));
    });

    test('clear 后 changeNotifier.value 递增', () async {
      final logger = LlmLogger.instance;
      final before = LlmLogger.changeNotifier.value;
      await logger.clear();
      expect(LlmLogger.changeNotifier.value, greaterThan(before));
    });

    test('changeNotifier 是 ValueNotifier，可被 addListener 监听', () {
      expect(LlmLogger.changeNotifier, isA<ValueNotifier<int>>());

      var notifyCount = 0;
      void listener() => notifyCount++;
      LlmLogger.changeNotifier.addListener(listener);
      try {
        final logger = LlmLogger.instance;
        logger.logRequest(id: 'l-1', endpoint: 'ep', requestBody: '{}');
        logger.logResponse(id: 'l-1', responseBody: '{}', durationMs: 1);
        expect(notifyCount, greaterThan(0));
      } finally {
        LlmLogger.changeNotifier.removeListener(listener);
      }
    });
  });

  group('LlmCallRecord - previewText / durationText', () {
    LlmCallRecord makeRecord({
      String id = 'p-1',
      int? durationMs = 1234,
    }) {
      return LlmCallRecord(
        id: id,
        timestamp: DateTime.utc(2026, 7, 2, 10, 0, 0),
        endpoint: 'https://example.com/v1/chat/completions',
        model: 'test-model',
        isStreaming: false,
        requestBody: '{"model":"test-model","messages":[{"role":"user",'
            '"content":"hello world"}]}',
        responseBody: '{"id":"resp-$id","usage":{"prompt_tokens":10,'
            '"completion_tokens":20,"total_tokens":30}}',
        durationMs: durationMs,
        isSuccess: true,
        promptTokens: 10,
        completionTokens: 20,
        totalTokens: 30,
      );
    }

    test('previewText 提取最后一条 content', () {
      // requestBody 最后一条 content 为 "hello world"
      expect(makeRecord().previewText, contains('hello world'));
    });

    test('durationText 格式化毫秒与秒与空值', () {
      expect(makeRecord(durationMs: 800).durationText, '800ms');
      expect(makeRecord(durationMs: 1500).durationText, '1.5s');
      expect(makeRecord(durationMs: null).durationText, '-');
    });
  });
}

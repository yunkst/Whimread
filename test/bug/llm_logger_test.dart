import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/llm_logger/llm_logger.dart';
import 'package:novel_app/services/llm_logger/llm_call_record.dart';

import '../test_bootstrap.dart';

/// LlmLogger 单元测试
///
/// 验证核心行为：
/// - logRequest/logResponse 写入内存缓存
/// - getRecent 查询（倒序）
/// - logError 失败标记
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

    test('logError 标记失败并记录错误信息', () async {
      final logger = LlmLogger.instance;
      logger.logRequest(
        id: 'rec-err',
        endpoint: 'ep',
        requestBody: '{"model":"m"}',
      );
      logger.logError(id: 'rec-err', errorMessage: 'connection timeout');

      final recent = await logger.getRecent(limit: 50);
      final detail = recent.where((r) => r.id == 'rec-err').firstOrNull;
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

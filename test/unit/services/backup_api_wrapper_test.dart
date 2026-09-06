import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量级 Dio HTTP 适配器 Mock
///
/// 用于拦截 Dio 的所有 HTTP 请求，返回预设响应。
class _MockAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody> _routes = {};
  String? lastUrl;
  String? lastMethod;

  void addRoute(String method, String path, ResponseBody body) {
    _routes['$method $path'] = body;
  }

  /// 创建 JSON 响应（自动设置 Content-Type 让 Dio 解码）
  ResponseBody jsonRoute(String json, int status) {
    return ResponseBody.fromString(
      json,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUrl = options.path;
    lastMethod = options.method;
    final key = '${options.method} ${options.path}';
    if (_routes.containsKey(key)) {
      return _routes[key]!;
    }
    // 默认返回 200 OK（用于 init() 中的 health check 等）
    return jsonRoute('{"status":"ok"}', 200);
  }

  @override
  void close({bool force = false}) {}
}

/// ApiServiceWrapper 备份方法单元测试
///
/// 验证 getBackupList / downloadBackup / deleteBackupOnServer
/// 三个方法的正确行为。
void main() {
  late _MockAdapter mockAdapter;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'backend_host': 'http://localhost:3800',
      'backend_token': 'test-token',
    });
    mockAdapter = _MockAdapter();
  });

  group('getBackupList', () {
    test('正常列表返回 - 有数据', () async {
      final api = ApiServiceWrapper();
      await api.init();
      // init() 重建了 dio，需要替换 adapter
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'GET',
        '/api/backup/list',
        mockAdapter.jsonRoute(
          '{"backups":['
              '{"filename":"novel_app_backup.db","file_size":2048,'
              '"stored_name":"novel_app_backup.db",'
              '"backup_id":"2026-06-15/novel_app_backup.db",'
              '"uploaded_at":"2026-06-15T10:30:00"},'
              '{"filename":"novel_app_backup_120000.db","file_size":4096,'
              '"stored_name":"novel_app_backup_120000.db",'
              '"backup_id":"2026-06-15/novel_app_backup_120000.db",'
              '"uploaded_at":"2026-06-15T12:00:00"}'
              ']}',
          200,
        ),
      );

      final result = await api.getBackupList();

      expect(result, isA<List<Map<String, dynamic>>>());
      expect(result.length, 2);
      expect(result[0]['filename'], 'novel_app_backup.db');
      expect(result[0]['backup_id'], contains('/'));
    });

    test('空备份列表', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'GET',
        '/api/backup/list',
        mockAdapter.jsonRoute('{"backups":[]}', 200),
      );

      final result = await api.getBackupList();
      expect(result, isEmpty);
    });

    test('网络错误应抛出异常', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'GET',
        '/api/backup/list',
        mockAdapter.jsonRoute('{"detail":"Server Error"}', 500),
      );

      expect(
        () => api.getBackupList(),
        throwsA(isA<Exception>()),
      );
    });

    test('未初始化应抛出异常', () async {
      final api = ApiServiceWrapper();
      // 不调用 init()

      expect(
        () => api.getBackupList(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('未初始化'),
        )),
      );
    });
  });

  group('downloadBackup', () {
    test('正常下载返回保存路径', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      final fakeDbBytes = Uint8List.fromList([
        ...'SQLite format 3\x00'.codeUnits,
        ...List.filled(100, 0),
      ]);

      mockAdapter.addRoute(
        'GET',
        '/api/backup/download/2026-06-15%2Ftest.db',
        ResponseBody(Stream.value(fakeDbBytes), 200),
      );

      final result = await api.downloadBackup(
        backupId: '2026-06-15/test.db',
        savePath: '/tmp/test_restore.db',
      );

      expect(result, '/tmp/test_restore.db');
    });

    test('backupId 含 / 应正确编码', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'GET',
        '/api/backup/download/2026-06-15%2Ftest.db',
        mockAdapter.jsonRoute('ok', 200),
      );

      await api.downloadBackup(
        backupId: '2026-06-15/test.db',
        savePath: '/tmp/test.db',
      );

      // 验证 URL 被正确编码
      expect(mockAdapter.lastUrl, contains('%2F'));
    });

    test('下载失败应抛出异常', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'GET',
        '/api/backup/download/nonexistent.db',
        mockAdapter.jsonRoute('{"detail":"Not Found"}', 404),
      );

      expect(
        () => api.downloadBackup(
          backupId: 'nonexistent.db',
          savePath: '/tmp/test.db',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('deleteBackupOnServer', () {
    test('正常删除应成功', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'DELETE',
        '/api/backup/delete/2026-06-15%2Ftest.db',
        mockAdapter.jsonRoute('{"message":"备份已删除"}', 200),
      );

      // 不应抛异常
      await api.deleteBackupOnServer(
        backupId: '2026-06-15/test.db',
      );
    });

    test('删除不存在备份应抛出异常', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'DELETE',
        '/api/backup/delete/nonexistent.db',
        mockAdapter.jsonRoute('{"detail":"Not Found"}', 404),
      );

      expect(
        () => api.deleteBackupOnServer(
          backupId: 'nonexistent.db',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('backupId 含 / 应正确编码', () async {
      final api = ApiServiceWrapper();
      await api.init();
      api.dio.httpClientAdapter = mockAdapter;

      mockAdapter.addRoute(
        'DELETE',
        '/api/backup/delete/2026-06-15%2Ftest.db',
        mockAdapter.jsonRoute('{"message":"备份已删除"}', 200),
      );

      await api.deleteBackupOnServer(
        backupId: '2026-06-15/test.db',
      );

      expect(mockAdapter.lastUrl, contains('%2F'));
    });
  });
}

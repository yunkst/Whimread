/// ApiServiceWrapper 401 自动续签拦截器单测（issue #48）
///
/// 场景：设备 JWT 是 30 天期会话凭证，过期后所有鉴权请求集体 401。
/// 拦截器经 unauthorizedRecoveryProvider 换新凭证后重放原请求一次。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程 fake adapter：记录每次请求的 Authorization 头，按脚本回包
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options, int call) handler;

  int calls = 0;
  final List<String?> authHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    authHeaders.add(options.headers['Authorization'] as String?);
    return handler(options, calls);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// init() 会重置 adapter（IOHttpClientAdapter），因此 fake 在 init 之后再装
  Future<ApiServiceWrapper> makeWrapper(_ScriptedAdapter adapter) async {
    SharedPreferences.setMockInitialValues({
      'backend_host': 'https://backend.example.com',
    });
    final wrapper = ApiServiceWrapper();
    await wrapper.init();
    wrapper.dio.httpClientAdapter = adapter;
    return wrapper;
  }

  test('401 → 刷新凭证 → 携带新头重放成功（对调用方透明）', () async {
    final adapter = _ScriptedAdapter((options, call) async {
      if (call == 1) {
        return ResponseBody.fromString('{"detail":"token expired"}', 401);
      }
      return ResponseBody.fromString(
        '{"backups":[]}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });
    final wrapper = await makeWrapper(adapter);
    var recoveries = 0;
    wrapper.unauthorizedRecoveryProvider = () async {
      recoveries++;
      return {'Authorization': 'Bearer fresh-jwt'};
    };

    final resp = await wrapper.dio.get('/api/backup/list');

    expect(resp.statusCode, 200);
    expect(recoveries, 1);
    expect(adapter.calls, 2, reason: '原始请求 + 1 次重放');
    expect(adapter.authHeaders[0], isNull);
    expect(adapter.authHeaders[1], 'Bearer fresh-jwt');
  });

  test('恢复失败（返回 null）时原始 401 照常上抛，不再重试', () async {
    final adapter = _ScriptedAdapter(
      (options, call) async => ResponseBody.fromString('{"detail":"x"}', 401),
    );
    final wrapper = await makeWrapper(adapter);
    wrapper.unauthorizedRecoveryProvider = () async => null;

    await expectLater(
      wrapper.dio.get('/api/backup/list'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(adapter.calls, 1);
  });

  test('重放后仍 401 不再续试（防循环）', () async {
    final adapter = _ScriptedAdapter(
      (options, call) async => ResponseBody.fromString('{"detail":"x"}', 401),
    );
    final wrapper = await makeWrapper(adapter);
    var recoveries = 0;
    wrapper.unauthorizedRecoveryProvider = () async {
      recoveries++;
      return {'Authorization': 'Bearer still-bad'};
    };

    await expectLater(
      wrapper.dio.get('/api/backup/list'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(adapter.calls, 2, reason: '原始 + 1 次重试，不能更多');
    expect(recoveries, 1);
  });

  test('注册链路端点（challenge/register）401 不触发恢复', () async {
    final adapter = _ScriptedAdapter(
      (options, call) async => ResponseBody.fromString('{"detail":"x"}', 401),
    );
    final wrapper = await makeWrapper(adapter);
    var recoveries = 0;
    wrapper.unauthorizedRecoveryProvider = () async {
      recoveries++;
      return {'Authorization': 'Bearer x'};
    };

    await expectLater(
      wrapper.dio.post('/api/v1/devices/register', data: {}),
      throwsA(isA<DioException>()),
    );
    expect(recoveries, 0, reason: '这些端点不带凭证，恢复流程会自激');
    expect(adapter.calls, 1);
  });

  test('未注入恢复回调时 401 直接上抛', () async {
    final adapter = _ScriptedAdapter(
      (options, call) async => ResponseBody.fromString('{"detail":"x"}', 401),
    );
    final wrapper = await makeWrapper(adapter);
    // 不设置 unauthorizedRecoveryProvider

    await expectLater(
      wrapper.dio.get('/api/backup/list'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(adapter.calls, 1);
  });
}

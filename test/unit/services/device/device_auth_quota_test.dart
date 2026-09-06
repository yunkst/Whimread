/// DeviceAuthService 额度自查（GET /api/v1/devices/me）单测
///
/// 覆盖三条路径：
/// 1. parseMeResponse 纯解析（合法/缺失/类型异常/null）
/// 2. fetchMeWithToken 网络路径（成功/401/非 JSON），fake HttpClientAdapter 拦截
/// 3. fetchQuota 守卫（kHasBundledBackend 编译期 false → 不发请求直接 null）
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/device/device_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可编程 fake adapter：断言收到请求或按给定响应回包
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

/// 任何请求都视为测试失败的 adapter（守卫路径不应发网络请求）
HttpClientAdapter failIfCalled() => _FakeAdapter((options) async {
      fail('不应发起网络请求: ${options.uri}');
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = DeviceAuthService.instance;

  group('parseMeResponse（响应解析契约）', () {
    test('合法响应解析出余额与状态', () {
      final info = DeviceAuthService.parseMeResponse({
        'device_id': 'dev-1',
        'quota_balance': 482,
        'status': 'active',
        'attestation_verified': true,
      });
      expect(info, isNotNull);
      expect(info!.deviceId, 'dev-1');
      expect(info.quotaBalance, 482);
      expect(info.status, 'active');
      expect(info.attestationVerified, isTrue);
    });

    test('device_id 为数字类型时兼容（toString）', () {
      final info = DeviceAuthService.parseMeResponse({
        'device_id': 42,
        'quota_balance': 0,
      });
      expect(info!.deviceId, '42');
      expect(info.quotaBalance, 0);
    });

    test('data 非 Map / null 返回 null', () {
      expect(DeviceAuthService.parseMeResponse(null), isNull);
      expect(DeviceAuthService.parseMeResponse('oops'), isNull);
      expect(DeviceAuthService.parseMeResponse([1, 2]), isNull);
    });

    test('quota_balance 缺失或非 int 返回 null（防脏数据崩 UI）', () {
      expect(
        DeviceAuthService.parseMeResponse({'device_id': 'd'}),
        isNull,
        reason: '余额缺失不应产出快照',
      );
      expect(
        DeviceAuthService.parseMeResponse({'quota_balance': '482'}),
        isNull,
        reason: '余额为字符串是后端契约破坏，宁可返回 null 隐藏展示',
      );
      expect(
        DeviceAuthService.parseMeResponse({'quota_balance': 1.5}),
        isNull,
      );
    });
  });

  group('fetchMeWithToken（网络路径）', () {
    test('携带 Bearer 头请求 /api/v1/devices/me 并解析成功', () async {
      RequestOptions? captured;
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          captured = options;
          return ResponseBody.fromString(
            '{"device_id":"dev-9","quota_balance":500,'
            '"status":"active","attestation_verified":true}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
      service.useWrapper(ApiServiceWrapper(dio));

      final info = await service.fetchMeWithToken('tok-abc');

      expect(info, isNotNull);
      expect(info!.quotaBalance, 500);
      expect(captured!.path, '/api/v1/devices/me');
      expect(captured!.headers['Authorization'], 'Bearer tok-abc');
    });

    test('401（token 过期/设备被封）返回 null 而非抛异常', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          return ResponseBody.fromString('{"detail":"设备不可用"}', 401);
        });
      service.useWrapper(ApiServiceWrapper(dio));

      final info = await service.fetchMeWithToken('expired');
      expect(info, isNull, reason: '额度是尽力而为的展示，401 必须静默');
    });

    test('200 但 body 非 JSON 返回 null', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          return ResponseBody.fromString('<html>gateway</html>', 200);
        });
      service.useWrapper(ApiServiceWrapper(dio));

      final info = await service.fetchMeWithToken('tok');
      expect(info, isNull);
    });

    test('连接失败（DioException）返回 null', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'refused',
          );
        });
      service.useWrapper(ApiServiceWrapper(dio));

      final info = await service.fetchMeWithToken('tok');
      expect(info, isNull);
    });
  });

  group('fetchQuota（守卫）', () {
    test('未配置托管后端时直接返回 null 且不发请求', () async {
      SharedPreferences.setMockInitialValues({});
      service.useWrapper(ApiServiceWrapper(Dio()..httpClientAdapter = failIfCalled()));
      await service.loadCached();

      expect(await service.fetchQuota(), isNull);
    });

    test('已配置但未注册（无缓存 token）不发请求返回 null', () async {
      // kHasBundledBackend 为编译期常量 false，此用例锁定：
      // 即便将来开关翻转，无 token 也必须先注册而不是裸查 /me
      SharedPreferences.setMockInitialValues({});
      service.useWrapper(ApiServiceWrapper(Dio()..httpClientAdapter = failIfCalled()));
      await service.loadCached();

      expect(await service.fetchQuota(), isNull,
          reason: '无缓存 token 时 fetchQuota 不应触发注册副作用');
    });
  });
}

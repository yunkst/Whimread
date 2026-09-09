/// GitHub Star 兑换服务的纯函数单测。
///
/// 仅覆盖 [DeviceAuthService.parseStarRedeemResponse] 与
/// [DeviceAuthService.mapRedeemDioError]：这两个函数是网络层的边界解析，
/// 不依赖设备注册 / Dio 真实请求，便于快速回归。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/device/device_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseStarRedeemResponse', () {
    test('完整字段 → 正确解析', () {
      final r = DeviceAuthService.parseStarRedeemResponse({
        'granted': 500,
        'quota_balance': 1000,
        'github_login': 'yunkst',
        'message': '已补充 500 点免费额度',
      });
      expect(r.granted, 500);
      expect(r.quotaBalance, 1000);
      expect(r.githubLogin, 'yunkst');
      expect(r.message, '已补充 500 点免费额度');
    });

    test('字段类型错（granted 是 String）→ 抛 ArgumentError', () {
      expect(
        () => DeviceAuthService.parseStarRedeemResponse({
          'granted': '500',
          'quota_balance': 1000,
        }),
        throwsArgumentError,
      );
    });

    test('非 Map 类型 → 抛 ArgumentError', () {
      expect(
        () => DeviceAuthService.parseStarRedeemResponse([1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('message/github_login 缺失 → 用默认占位', () {
      final r = DeviceAuthService.parseStarRedeemResponse({
        'granted': 100,
        'quota_balance': 100,
      });
      expect(r.message, '兑换成功');
      expect(r.githubLogin, '');
    });
  });

  group('mapRedeemDioError', () {
    DioException err(int? status, dynamic data) => DioException(
          requestOptions: RequestOptions(path: '/star/redeem'),
          response: status == null
              ? null
              : Response(
                  requestOptions: RequestOptions(path: '/star/redeem'),
                  statusCode: status,
                  data: data,
                ),
          type: DioExceptionType.badResponse,
        );

    test('无 response（网络异常）→ NETWORK', () {
      final e = DeviceAuthService.mapRedeemDioError(
          DioException(requestOptions: RequestOptions(path: '/x')));
      expect(e.code, 'NETWORK');
    });

    test('NOT_STARRED → 中文提示去 Star', () {
      final e = DeviceAuthService.mapRedeemDioError(err(
        404,
        {'code': 'NOT_STARRED', 'message': '未在项目 Star 列表中找到'},
      ));
      expect(e.code, 'NOT_STARRED');
      expect(e.message, contains('Star'));
    });

    test('ALREADY_REDEEMED → 中文提示已兑换', () {
      final e = DeviceAuthService.mapRedeemDioError(err(
        409,
        {'code': 'ALREADY_REDEEMED', 'message': '已兑换过免费额度'},
      ));
      expect(e.code, 'ALREADY_REDEEMED');
      expect(e.message, contains('已兑换'));
    });

    test('INVALID_GITHUB_LOGIN → 提示格式说明', () {
      final e = DeviceAuthService.mapRedeemDioError(err(
        400,
        {'code': 'INVALID_GITHUB_LOGIN', 'message': '用户名格式不正确'},
      ));
      expect(e.code, 'INVALID_GITHUB_LOGIN');
      expect(e.message, contains('字母'));
    });

    test('STAR_REDEEM_RATE_LIMITED → 提示稍后再试', () {
      final e = DeviceAuthService.mapRedeemDioError(err(
        429,
        {'code': 'STAR_REDEEM_RATE_LIMITED', 'message': 'too many'},
      ));
      expect(e.code, 'STAR_REDEEM_RATE_LIMITED');
      expect(e.message, contains('稍后'));
    });

    test('GITHUB_CHECK_FAILED → 提示 GitHub 暂不可用', () {
      final e = DeviceAuthService.mapRedeemDioError(err(
        502,
        {'code': 'GITHUB_CHECK_FAILED', 'message': '502'},
      ));
      expect(e.code, 'GITHUB_CHECK_FAILED');
      expect(e.message, contains('GitHub'));
    });

    test('错误体用 code 键(errors.js 规范)也能映射', () {
      final e = DeviceAuthService.mapRedeemDioError(err(
        400,
        {'code': 'NOT_STARRED', 'message': '未检测到 Star'},
      ));
      expect(e.code, 'NOT_STARRED');
    });

    test('未知 code → 用 HTTP_<status> 作为 code + 透传 message', () {
      final e = DeviceAuthService.mapRedeemDioError(err(
        500,
        {'code': 'INTERNAL_ERROR', 'message': '服务器爆炸'},
      ));
      expect(e.code, 'INTERNAL_ERROR');
      expect(e.message, '服务器爆炸');
    });

    test('响应体不是 Map（异常网关返回）→ 用 HTTP_500 作为 code', () {
      final e = DeviceAuthService.mapRedeemDioError(err(500, 'html 页面'));
      expect(e.code, 'HTTP_500');
      expect(e.message, contains('500'));
    });
  });
}
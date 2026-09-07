/// BackendReleaseService 契约测试
///
/// 验证:
/// - stable / preview 通道映射为 channel 查询参数
/// - 200 正常解析（含 files/abi/url）
/// - 404（通道无 release）返回 null
/// - 429 → AppUpdateCheckException(rate_limited)
/// - 网络错误 → AppUpdateCheckException(network_error)
/// - BackendRelease.apkFileFor 架构选择兜底链
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/backend_release.dart';
import 'package:novel_app/services/app_update_check_exception.dart';
import 'package:novel_app/services/backend_release_service.dart';

/// 最小化 Dio 桩：记录 channel 查询参数，按配置返回数据或异常。
class _StubDio implements Dio {
  final Map<String, dynamic>? data;
  final DioException? error;
  final List<String?> capturedChannels = [];

  _StubDio({this.data, this.error});

  @override
  Future<Response<T>> get<T>(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress}) async {
    capturedChannels.add(queryParameters?['channel'] as String?);

    if (error != null) throw error!;
    if (error == null && this.data == null) {
      // 未配置响应：模拟「通道无 release」404
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          statusCode: 404,
          requestOptions: RequestOptions(path: path),
        ),
      );
    }
    return Response<T>(
      data: this.data as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _releaseJson({
  String version = '1.7.21',
  String channel = 'stable',
}) =>
    {
      'version': version,
      'version_code': 70,
      'channel': channel,
      'changelog': '修复若干问题',
      'published_at': '2026-09-06T12:00:00Z',
      'files': [
        {
          'abi': 'arm64-v8a',
          'filename': 'app-arm64-v8a-release.apk',
          'size': 45678901,
          'sha256': 'a' * 64,
          'url': 'https://backend.example.com/api/v1/app/releases/$version/'
              'app-arm64-v8a-release.apk',
        },
        {
          'abi': 'armeabi-v7a',
          'filename': 'app-armeabi-v7a-release.apk',
          'size': 42123456,
          'sha256': 'b' * 64,
          'url': 'https://backend.example.com/api/v1/app/releases/$version/'
              'app-armeabi-v7a-release.apk',
        },
      ],
    };

BackendReleaseService _service(Dio stub) =>
    BackendReleaseService(dio: stub, baseUrl: 'https://backend.example.com');

void main() {
  test('stable 通道带 channel=stable 查询参数并正常解析', () async {
    final stub = _StubDio(data: _releaseJson());
    final release =
        await _service(stub).fetchLatestRelease(includePrerelease: false);

    expect(stub.capturedChannels, ['stable']);
    expect(release, isNotNull);
    expect(release!.version, '1.7.21');
    expect(release.versionCode, 70);
    expect(release.changelog, '修复若干问题');
    expect(release.files, hasLength(2));
    expect(release.files.first.abi, 'arm64-v8a');
    expect(release.files.first.url, contains('backend.example.com'));
  });

  test('preview 通道请求 channel=preview', () async {
    final stub = _StubDio(
      data: _releaseJson(version: '2.0.0-preview.1', channel: 'preview'),
    );
    final release =
        await _service(stub).fetchLatestRelease(includePrerelease: true);

    expect(stub.capturedChannels, ['preview']);
    expect(release!.version, '2.0.0-preview.1');
    expect(release.channel, 'preview');
  });

  test('404（通道无 release）返回 null 而不抛异常', () async {
    final release =
        await _service(_StubDio()).fetchLatestRelease(includePrerelease: false);
    expect(release, isNull);
  });

  test('429 映射为 rate_limited 异常', () async {
    final service = _service(_StubDio(
      error: DioException(
        requestOptions: RequestOptions(path: '/latest'),
        response: Response(
          statusCode: 429,
          requestOptions: RequestOptions(path: '/latest'),
        ),
      ),
    ));
    await expectLater(
      service.fetchLatestRelease(includePrerelease: false),
      throwsA(isA<AppUpdateCheckException>()
          .having((e) => e.cause, 'cause', 'rate_limited')),
    );
  });

  test('其他 HTTP 错误映射为 http_xxx 异常', () async {
    final service = _service(_StubDio(
      error: DioException(
        requestOptions: RequestOptions(path: '/latest'),
        response: Response(
          statusCode: 500,
          requestOptions: RequestOptions(path: '/latest'),
        ),
      ),
    ));
    await expectLater(
      service.fetchLatestRelease(includePrerelease: false),
      throwsA(isA<AppUpdateCheckException>()
          .having((e) => e.cause, 'cause', 'http_500')),
    );
  });

  test('网络错误映射为 network_error 异常', () async {
    final service = _service(_StubDio(
      error: DioException(
        requestOptions: RequestOptions(path: '/latest'),
        error: 'connection reset',
      ),
    ));
    await expectLater(
      service.fetchLatestRelease(includePrerelease: false),
      throwsA(isA<AppUpdateCheckException>()
          .having((e) => e.cause, 'cause', 'network_error')),
    );
  });

  group('BackendRelease.apkFileFor 架构选择兜底链', () {
    BackendRelease build(List<Map<String, dynamic>> files) =>
        BackendRelease.fromJson({'version': '1.0.0', 'files': files});

    test('精确匹配 abi / 文件名', () {
      final release = build([
        {'abi': 'armeabi-v7a', 'filename': 'app-armeabi-v7a-release.apk'},
        {'abi': 'arm64-v8a', 'filename': 'app-arm64-v8a-release.apk'},
      ]);
      expect(release.apkFileFor('arm64-v8a')!.filename,
          'app-arm64-v8a-release.apk');
    });

    test('无精确匹配时兜底通用 fat APK', () {
      final release = build([
        {'abi': 'x86_64', 'filename': 'app-x86_64-release.apk'},
        {'abi': '', 'filename': 'app-release.apk'},
      ]);
      expect(release.apkFileFor('arm64-v8a')!.filename, 'app-release.apk');
    });

    test('最后兜底任意 APK；无 APK 返回 null', () {
      final any = build([
        {'abi': 'x86_64', 'filename': 'app-x86_64-release.apk'},
      ]);
      expect(any.apkFileFor('arm64-v8a')!.filename, 'app-x86_64-release.apk');

      final empty = build([
        {'abi': '', 'filename': 'SHA256SUMS.txt'},
      ]);
      expect(empty.apkFileFor('arm64-v8a'), isNull);
    });
  });
}

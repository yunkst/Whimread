/// AppUpdateService 更新源双链测试
///
/// 验证:
/// - 配置了 BACKEND_BASE_URL 时后端优先，GitHub 不被请求
/// - 后端失败 / 无 release / 无匹配 APK → 回退 GitHub
/// - 后端失败且 GitHub 也无结果 → CheckFailed（不误报「已是最新」）
/// - 未配置后端 → 仅走 GitHub（未注入后端的构建行为不变）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:novel_app/models/backend_release.dart';
import 'package:novel_app/models/github_release.dart';
import 'package:novel_app/services/app_update_check_exception.dart';
import 'package:novel_app/services/app_update_result.dart';
import 'package:novel_app/services/app_update_service.dart';
import 'package:novel_app/services/backend_release_service.dart';
import 'package:novel_app/services/github_release_service.dart';

class _FakeGithubService implements GithubReleaseService {
  GithubRelease? release;
  bool fetchCalled = false;

  @override
  Future<GithubRelease?> fetchLatestRelease({
    bool includePrerelease = false,
  }) async {
    fetchCalled = true;
    return release;
  }

  @override
  Future<bool> shouldCheck({bool forceCheck = false}) async => true;

  @override
  Future<void> recordCheckTime() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBackendService implements BackendReleaseService {
  BackendRelease? release;
  Object? throwOnFetch;
  bool fetchCalled = false;

  @override
  Future<BackendRelease?> fetchLatestRelease({
    required bool includePrerelease,
  }) async {
    fetchCalled = true;
    if (throwOnFetch != null) throw throwOnFetch!;
    return release;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GithubRelease _githubRelease(String version) => GithubRelease(
      tagName: 'v$version',
      name: 'v$version',
      body: 'body',
      publishedAt: '2026-09-01T00:00:00Z',
      prerelease: false,
      draft: false,
      assets: [
        GithubAsset(
          name: 'app-arm64-v8a-release.apk',
          size: 1024,
          browserDownloadUrl: 'https://github.com/download/app-arm64-v8a.apk',
          contentType: 'application/vnd.android.package-archive',
        ),
      ],
    );

BackendRelease _backendRelease(String version) => BackendRelease.fromJson({
      'version': version,
      'version_code': 70,
      'channel': 'stable',
      'changelog': '后端更新说明',
      'published_at': '2026-09-06T12:00:00Z',
      'files': [
        {
          'abi': 'arm64-v8a',
          'filename': 'app-arm64-v8a-release.apk',
          'size': 2048,
          'sha256': 'a' * 64,
          'url': 'https://backend.example.com/download/$version/'
              'app-arm64-v8a-release.apk',
        },
      ],
    });

Future<AppUpdateService> _service(
  _FakeGithubService github,
  _FakeBackendService backend, {
  String backendBaseUrl = 'https://backend.example.com',
}) async {
  return AppUpdateService(
    githubService: github,
    backendReleaseService: backend,
    backendBaseUrl: backendBaseUrl,
    packageInfoGetter: () async => PackageInfo(
      appName: 'test',
      packageName: 'com.test.app',
      version: '1.0.0',
      buildNumber: '1',
    ),
  );
}

void main() {
  test('后端配置且正常时采用后端结果，不请求 GitHub', () async {
    final github = _FakeGithubService()..release = _githubRelease('1.8.0');
    final backend = _FakeBackendService()..release = _backendRelease('1.9.0');

    final result = (await _service(github, backend))
        .checkForUpdateDetailed(forceCheck: true);

    expect(await result, isA<AppUpdateAvailable>());
    final available = await result as AppUpdateAvailable;
    expect(available.version.downloadUrl, contains('backend.example.com'));
    expect(available.version.changelog, '后端更新说明');
    expect(github.fetchCalled, isFalse);
  });

  test('后端失败时回退 GitHub', () async {
    final github = _FakeGithubService()..release = _githubRelease('1.8.0');
    final backend = _FakeBackendService()
      ..throwOnFetch =
          AppUpdateCheckException('后端检查更新失败', cause: 'network_error');

    final result = (await _service(github, backend))
        .checkForUpdateDetailed(forceCheck: true);

    expect(await result, isA<AppUpdateAvailable>());
    expect((await result as AppUpdateAvailable).version.downloadUrl,
        contains('github.com'));
    expect(github.fetchCalled, isTrue);
  });

  test('后端失败且 GitHub 无结果时归为 CheckFailed', () async {
    final github = _FakeGithubService();
    final backend = _FakeBackendService()
      ..throwOnFetch =
          AppUpdateCheckException('后端检查更新失败', cause: 'network_error');

    final result = (await _service(github, backend))
        .checkForUpdateDetailed(forceCheck: true);

    expect(await result, isA<AppUpdateCheckFailed>());
    expect(github.fetchCalled, isTrue);
  });

  test('后端正常但无 release 时回退 GitHub', () async {
    final github = _FakeGithubService()..release = _githubRelease('1.8.0');
    final backend = _FakeBackendService();

    final result = (await _service(github, backend))
        .checkForUpdateDetailed(forceCheck: true);

    expect(await result, isA<AppUpdateAvailable>());
    expect((await result as AppUpdateAvailable).version.downloadUrl,
        contains('github.com'));
  });

  test('后端 release 无匹配 APK 时回退 GitHub', () async {
    final github = _FakeGithubService()..release = _githubRelease('1.8.0');
    final backend = _FakeBackendService()
      ..release = BackendRelease.fromJson({
        'version': '1.9.0',
        'files': [],
      });

    final result = (await _service(github, backend))
        .checkForUpdateDetailed(forceCheck: true);

    expect(await result, isA<AppUpdateAvailable>());
    expect((await result as AppUpdateAvailable).version.downloadUrl,
        contains('github.com'));
  });

  test('未配置后端时仅走 GitHub（不注入后端的构建行为不变）', () async {
    final github = _FakeGithubService()..release = _githubRelease('1.8.0');
    final backend = _FakeBackendService()..release = _backendRelease('1.9.0');

    final result = (await _service(github, backend, backendBaseUrl: ''))
        .checkForUpdateDetailed(forceCheck: true);

    expect(await result, isA<AppUpdateAvailable>());
    expect((await result as AppUpdateAvailable).version.downloadUrl,
        contains('github.com'));
    expect(backend.fetchCalled, isFalse);
  });

  test('两源均无新版本时返回 UpToDate', () async {
    final github = _FakeGithubService()..release = _githubRelease('1.0.0');
    final backend = _FakeBackendService()..release = _backendRelease('1.0.0');

    // 不传 forceCheck：强制检查时即使无新版本也返回 Available（历史契约）
    final result =
        (await _service(github, backend)).checkForUpdateDetailed();

    expect(await result, isA<AppUpdateUpToDate>());
  });
}

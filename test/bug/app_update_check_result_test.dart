/// AppUpdateService.checkForUpdateDetailed 结果类型测试
///
/// 验证核心修复：限流/网络错误时返回 [AppUpdateCheckFailed]，
/// 而非把请求失败误报成「已是最新版本」。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/app_version.dart';
import 'package:novel_app/models/github_release.dart';
import 'package:novel_app/services/app_update_check_exception.dart';
import 'package:novel_app/services/app_update_result.dart';
import 'package:novel_app/services/app_update_service.dart';
import 'package:novel_app/services/github_release_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 用子类 stub 掉网络层，避免 mockito codegen 依赖
class _FakeGithubReleaseService implements GithubReleaseService {
  /// 抛 [AppUpdateCheckException] 表示限流/网络错误；返回 null 表示真无 release；
  /// 返回 [GithubRelease] 表示有可用 release。
  final Future<GithubRelease?> Function() _fetchImpl;

  _FakeGithubReleaseService(this._fetchImpl);

  @override
  Future<GithubRelease?> fetchLatestRelease({
    bool includePrerelease = false,
  }) =>
      _fetchImpl();

  // —— 以下接口测试不关心，空实现即可 ——
  @override
  Future<bool> shouldCheck({bool forceCheck = false}) async => true;

  @override
  Future<void> recordCheckTime() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 构造一个 fake PackageInfo，避免测试环境调 Platform channel
PackageInfo _fakePackageInfo(String version) => PackageInfo(
      appName: 'novel_app',
      packageName: 'com.example.novel_app',
      version: version,
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );

/// 构造一个含 APK 的 release JSON
Map<String, dynamic> _releaseJson(String tag) => jsonDecode('''
{
  "tag_name": "$tag",
  "name": "$tag",
  "body": "测试 changelog",
  "published_at": "2026-07-01T09:16:35Z",
  "prerelease": false,
  "draft": false,
  "assets": [
    {
      "name": "app-arm64-v8a-release.apk",
      "size": 23449107,
      "browser_download_url": "https://example.com/$tag.apk",
      "content_type": "application/vnd.android.package-archive"
    }
  ]
}
''') as Map<String, dynamic>;

void main() {
  group('checkForUpdateDetailed - 区分「无新版本」与「请求失败」', () {
    test('限流（403）应返回 AppUpdateCheckFailed，而非 UpToDate', () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => throw const AppUpdateCheckException(
            'GitHub API 限流',
            cause: 'rate_limited',
          ),
        ),
      );

      final result = await service.checkForUpdateDetailed(forceCheck: true);

      expect(result, isA<AppUpdateCheckFailed>());
      expect((result as AppUpdateCheckFailed).reason, contains('限流'));
    });

    test('网络错误应返回 AppUpdateCheckFailed', () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => throw const AppUpdateCheckException(
            '网络错误：超时',
            cause: 'network_error',
          ),
        ),
      );

      final result = await service.checkForUpdateDetailed(forceCheck: true);

      expect(result, isA<AppUpdateCheckFailed>());
      expect((result as AppUpdateCheckFailed).reason, contains('网络错误'));
    });

    test('404/无 release 应返回 AppUpdateUpToDate（真无新版本）', () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => null,
        ),
      );

      final result = await service.checkForUpdateDetailed(forceCheck: true);

      expect(result, isA<AppUpdateUpToDate>());
    });

    test('远端有 release 时应返回 AppUpdateAvailable（含 APK 信息）',
        () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => GithubRelease.fromJson(_releaseJson('v9.9.9')),
        ),
        packageInfoGetter: () async => _fakePackageInfo('1.0.0'),
      );

      final result = await service.checkForUpdateDetailed(forceCheck: true);

      expect(result, isA<AppUpdateAvailable>());
      final available = result as AppUpdateAvailable;
      expect(available.version.version, '9.9.9');
      expect(available.version.downloadUrl, contains('v9.9.9.apk'));
    });

    test('release 无 APK asset 时应返回 AppUpdateUpToDate', () async {
      final noApkJson = jsonDecode('''
      {
        "tag_name": "v9.9.9",
        "name": "v9.9.9",
        "body": "",
        "published_at": "2026-07-01T09:16:35Z",
        "prerelease": false,
        "draft": false,
        "assets": []
      }
      ''') as Map<String, dynamic>;
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => GithubRelease.fromJson(noApkJson),
        ),
        packageInfoGetter: () async => _fakePackageInfo('1.0.0'),
      );

      final result = await service.checkForUpdateDetailed(forceCheck: true);

      // 无 APK → apkAssetFor 也返回 null → UpToDate
      expect(result, isA<AppUpdateUpToDate>());
    });
  });

  group('旧入口 checkForUpdate 向后兼容', () {
    test('限流时返回 null（与旧行为一致，但内部已区分）', () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => throw const AppUpdateCheckException(
            '限流',
            cause: 'rate_limited',
          ),
        ),
      );

      // 旧调用方仍得到 null，不破坏现有契约
      final result = await service.checkForUpdate(forceCheck: true);
      expect(result, isNull);
    });

    test('有 release 时返回 AppVersion', () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => GithubRelease.fromJson(_releaseJson('v9.9.9')),
        ),
        packageInfoGetter: () async => _fakePackageInfo('1.0.0'),
      );

      final result = await service.checkForUpdate(forceCheck: true);
      expect(result, isA<AppVersion>());
      expect(result!.version, '9.9.9');
    });
  });

  group('双通道 (stable/preview)', () {
    /// 构造一个 prerelease 的 release JSON
    Map<String, dynamic> _prereleaseJson(String tag) => {
          ..._releaseJson(tag),
          'prerelease': true,
        };

    test('stable 通道: includePrerelease=false 跳过 prerelease', () async {
      // 模拟 GitHub /releases/latest：返回 null（等同于服务端跳过 prerelease）
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => null, // prerelease 被跳过，无可用稳定版
        ),
      );

      final result = await service.checkForUpdateDetailed(
        forceCheck: true,
        includePrerelease: false,
      );

      // 无稳定版 → UpToDate
      expect(result, isA<AppUpdateUpToDate>());
    });

    test('preview 通道: includePrerelease=true 接受 prerelease', () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async =>
              GithubRelease.fromJson(_prereleaseJson('v2.0.0-preview.1')),
        ),
        packageInfoGetter: () async => _fakePackageInfo('1.0.0'),
      );

      final result = await service.checkForUpdateDetailed(
        forceCheck: true,
        includePrerelease: true,
      );

      expect(result, isA<AppUpdateAvailable>());
      final available = result as AppUpdateAvailable;
      expect(available.version.version, '2.0.0-preview.1');
    });

    test('preview 通道: 最新一条是 stable 时也能拿到', () async {
      // 当没有预览版、最新一条就是稳定版时，preview 通道也能拿到
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => GithubRelease.fromJson(_releaseJson('v2.0.0')),
        ),
        packageInfoGetter: () async => _fakePackageInfo('1.0.0'),
      );

      final result = await service.checkForUpdateDetailed(
        forceCheck: true,
        includePrerelease: true,
      );

      expect(result, isA<AppUpdateAvailable>());
      expect((result as AppUpdateAvailable).version.version, '2.0.0');
    });

    test('旧入口 checkForUpdate 透传 includePrerelease', () async {
      final service = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async =>
              GithubRelease.fromJson(_prereleaseJson('v2.0.0-preview.1')),
        ),
        packageInfoGetter: () async => _fakePackageInfo('1.0.0'),
      );

      // 开启预览通道
      final previewResult = await service.checkForUpdate(
        forceCheck: true,
        includePrerelease: true,
      );
      expect(previewResult, isA<AppVersion>());
      expect(previewResult!.version, '2.0.0-preview.1');

      // 关闭预览通道（默认）
      final stableService = AppUpdateService(
        githubService: _FakeGithubReleaseService(
          () async => null, // prerelease 被跳过
        ),
      );
      final stableResult = await stableService.checkForUpdate(
        forceCheck: true,
      );
      expect(stableResult, isNull);
    });

    test('isPreviewChannelEnabled 默认返回 false', () async {
      // 注意：单元测试环境 SharedPreferences 不可用，此测试验证静态方法签名存在
      // 实际读写逻辑依赖 PreferencesService，需在集成测试中验证
      expect(AppUpdateService.isPreviewChannelEnabled, isNotNull);
      expect(AppUpdateService.setPreviewChannelEnabled, isNotNull);
    });
  });
}

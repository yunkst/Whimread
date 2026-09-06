import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/build_config.dart';
import '../models/app_version.dart';
import '../utils/device_arch.dart';
import 'app_update_check_exception.dart';
import 'app_update_result.dart';
import 'backend_release_service.dart';
import 'github_release_service.dart';
import 'logger_service.dart';
import 'preferences_service.dart';

/// APP更新服务
///
/// 更新源双链：打包注入了 `BACKEND_BASE_URL` 时首选托管后端
/// （[BackendReleaseService]），失败或未注入则回退 GitHub Releases
/// （[GithubReleaseService]）。两条源的通道语义对齐（stable 跳过预览版，
/// preview 取含预览版的最新一条）。
class AppUpdateService {
  static const String _ignoreVersionKey = 'app_update_ignore_version';
  static const String _previewChannelKey = 'app_update_preview_channel';
  static const _platformChannel =
      MethodChannel('com.example.novel_app/app_install');

  final GithubReleaseService _githubService;
  final BackendReleaseService? _backendService;
  final String _backendBaseUrl;
  final Future<PackageInfo> Function()? _packageInfoGetter;

  AppUpdateService({
    GithubReleaseService? githubService,
    BackendReleaseService? backendReleaseService,
    String? backendBaseUrl,
    Future<PackageInfo> Function()? packageInfoGetter,
  })  : _githubService = githubService ?? GithubReleaseService(),
        _backendService = backendReleaseService,
        _backendBaseUrl = backendBaseUrl ?? kBackendBaseUrl,
        _packageInfoGetter = packageInfoGetter;

  /// 获取当前APP版本信息
  Future<PackageInfo> getCurrentVersion() async {
    if (_packageInfoGetter != null) {
      return await _packageInfoGetter!();
    }
    return await PackageInfo.fromPlatform();
  }

  /// 检查是否有新版本（详细结果，区分「无新版本」与「请求失败」）
  ///
  /// - [AppUpdateAvailable]：远端存在可用 release（含至少一个匹配架构的 APK）
  /// - [AppUpdateUpToDate]：请求成功，但远端无可用 release（404 / draft / prerelease / 无 APK）
  /// - [AppUpdateCheckFailed]：请求失败（限流 / 网络错误 / 解析异常），用户应重试
  ///
  /// - [includePrerelease]：是否包含 prerelease（preview 通道）。
  ///   默认 false（stable 通道），GitHub API 会跳过 prerelease 版本。
  ///
  /// 与 [checkForUpdate] 的区别：后者把所有失败都归为 null（误报「无新版本」），
  /// 本方法把失败单独返回，调用方可据此提示用户「检查失败，请重试」。
  Future<AppUpdateResult> checkForUpdateDetailed({
    bool forceCheck = false,
    bool includePrerelease = false,
  }) async {
    try {
      // 频率控制
      if (!await _githubService.shouldCheck(forceCheck: forceCheck)) {
        LoggerService.instance.d(
          '1 小时内已检查过，跳过',
          category: LogCategory.general,
          tags: ['update'],
        );
        return const AppUpdateUpToDate();
      }

      // 记录检查时间
      await _githubService.recordCheckTime();

      // 后端优先，失败回退 GitHub；两源都失败时若后端错误在先，
      // 归类为 CheckFailed（避免把网络故障误报成「已是最新」）
      final appVersion = await _resolveLatestVersion(
        includePrerelease: includePrerelease,
      );
      if (appVersion == null) {
        return const AppUpdateUpToDate();
      }

      // 获取当前版本（延后到确认有可用 release 之后，避免无 release 时也依赖平台）
      final currentInfo = await getCurrentVersion();

      // 比较版本号
      final hasNew =
          hasNewVersion(currentInfo.version, appVersion.version);

      LoggerService.instance.d(
        '版本比较: ${currentInfo.version} vs ${appVersion.version}, hasNew: $hasNew, forceCheck: $forceCheck',
        category: LogCategory.general,
        tags: ['update', 'debug'],
      );

      // 有新版本或强制检查时都返回 Available（调用方自行按 hasNew 决定是否提示）
      if (forceCheck || hasNew) {
        return AppUpdateAvailable(appVersion);
      }

      return const AppUpdateUpToDate();
    } on AppUpdateCheckException catch (e) {
      // 限流 / 网络错误 / 服务器错误 → 区分为 CheckFailed，不再误报「无新版本」
      LoggerService.instance.w(
        '检查更新失败（可恢复）: ${e.cause} - ${e.message}',
        category: LogCategory.general,
        tags: ['update', 'check', 'failed', e.cause],
      );
      return AppUpdateCheckFailed(e.message);
    } catch (e) {
      LoggerService.instance.e(
        '检查更新失败: $e',
        category: LogCategory.general,
        tags: ['update', 'check', 'error'],
      );
      return AppUpdateCheckFailed('检查更新失败，请稍后重试');
    }
  }

  /// 解析最新可用版本：后端优先，失败或未配置回退 GitHub
  ///
  /// 返回 null 表示两源都正常但均无可用 release；后端曾失败且 GitHub 也
  /// 无结果时，重抛后端异常让调用方归为 [AppUpdateCheckFailed]。
  Future<AppVersion?> _resolveLatestVersion({
    required bool includePrerelease,
  }) async {
    Object? backendError;
    if (_backendBaseUrl.isNotEmpty) {
      try {
        final service =
            _backendService ?? BackendReleaseService(baseUrl: _backendBaseUrl);
        final fromBackend = await _appVersionFromBackend(
          service,
          includePrerelease: includePrerelease,
        );
        if (fromBackend != null) return fromBackend;
        // 后端正常但无 release（新部署 / 未同步）：继续走 GitHub 兜底
      } on AppUpdateCheckException catch (e) {
        backendError = e;
      }
    }

    final fromGithub = await _appVersionFromGithub(
      includePrerelease: includePrerelease,
    );
    if (fromGithub != null) return fromGithub;
    if (backendError is AppUpdateCheckException) throw backendError;
    return null;
  }

  /// 从托管后端构造 AppVersion（downloadUrl 指向后端 / CDN）
  Future<AppVersion?> _appVersionFromBackend(
    BackendReleaseService service, {
    required bool includePrerelease,
  }) async {
    final release = await service.fetchLatestRelease(
      includePrerelease: includePrerelease,
    );
    if (release == null) return null;

    final arch = await DeviceArchDetector.getCurrent();
    final file = release.apkFileFor(arch.apkNameSegment);
    if (file == null) {
      LoggerService.instance.w(
        '后端 release ${release.version} 无可用 APK (arch=${arch.apkNameSegment})',
        category: LogCategory.general,
        tags: ['update', 'arch', 'noapk'],
      );
      return null;
    }

    return AppVersion(
      version: release.version,
      downloadUrl: file.url,
      fileSize: file.size,
      changelog: release.changelog,
      createdAt: release.publishedAt,
    );
  }

  /// 从 GitHub Releases 构造 AppVersion（兜底路径，行为与历史版本一致）
  Future<AppVersion?> _appVersionFromGithub({
    required bool includePrerelease,
  }) async {
    final release = await _githubService.fetchLatestRelease(
      includePrerelease: includePrerelease,
    );
    if (release == null) return null;

    final arch = await DeviceArchDetector.getCurrent();
    final archSegment = arch.apkNameSegment;

    LoggerService.instance.d(
      '设备架构: ${arch.name} (segment=$archSegment)',
      category: LogCategory.general,
      tags: ['update', 'arch'],
    );

    final asset = release.apkAssetFor(archSegment);
    if (asset == null) {
      LoggerService.instance.w(
        'Release ${release.tagName} 无可用 APK asset (arch=$archSegment)',
        category: LogCategory.general,
        tags: ['update', 'arch', 'noapk'],
      );
      return null;
    }

    return AppVersion(
      version: release.versionNumber,
      downloadUrl: asset.browserDownloadUrl,
      fileSize: asset.size,
      changelog: _extractChangelog(release.body),
      createdAt: release.publishedAt,
    );
  }

  /// 检查是否有新版本（向后兼容入口）
  ///
  /// 返回 null 表示没有新版本（或 API 错误/无可用 release）。
  /// 内部委托给 [checkForUpdateDetailed]：Available → 返回 AppVersion；
  /// UpToDate / CheckFailed → 返回 null（保持旧契约不破坏调用方）。
  Future<AppVersion?> checkForUpdate({
    bool forceCheck = false,
    bool includePrerelease = false,
  }) async {
    final result = await checkForUpdateDetailed(
      forceCheck: forceCheck,
      includePrerelease: includePrerelease,
    );
    if (result is AppUpdateAvailable) {
      return result.version;
    }
    return null;
  }

  /// 比较版本号
  ///
  /// 返回 true 表示有新版本
  bool hasNewVersion(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      // 补齐版本号位数
      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (latestParts.length < 3) {
        latestParts.add(0);
      }

      // 比较主版本号
      if (latestParts[0] > currentParts[0]) return true;
      if (latestParts[0] < currentParts[0]) return false;

      // 比较次版本号
      if (latestParts[1] > currentParts[1]) return true;
      if (latestParts[1] < currentParts[1]) return false;

      // 比较修订号
      if (latestParts[2] > currentParts[2]) return true;

      return false;
    } catch (e) {
      LoggerService.instance.e(
        '版本号比较失败: $e',
        category: LogCategory.general,
        tags: ['update', 'version', 'compare'],
      );
      return false;
    }
  }

  /// 请求安装权限
  Future<bool> requestInstallPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final status = await Permission.requestInstallPackages.request();
    return status.isGranted;
  }

  /// 下载更新
  ///
  /// [version.downloadUrl] 可以来自托管后端 / CDN 或 GitHub 直链，
  /// 下载流程相同（dio 流式下载 + 进度回调）。
  ///
  /// [onProgress] 进度回调 0.0-1.0
  /// [onStatus] 状态文本回调
  Future<bool> downloadUpdate({
    required AppVersion version,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final fileName = 'novel_app_v${version.version}.apk';
    return await _githubService.downloadApk(
      downloadUrl: version.downloadUrl,
      fileName: fileName,
      onProgress: onProgress,
      onStatus: onStatus,
    );
  }

  /// 安装 APK
  Future<bool> installUpdate(String version) async {
    try {
      LoggerService.instance.i(
        '开始安装APK',
        category: LogCategory.general,
        tags: ['update', 'install', 'start'],
      );
      final hasPermission = await requestInstallPermission();
      if (!hasPermission) {
        LoggerService.instance.w(
          '没有安装权限',
          category: LogCategory.general,
          tags: ['update', 'install', 'permission'],
        );
        return false;
      }

      final fileName = 'novel_app_v$version.apk';
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/updates/$fileName';

      final file = File(filePath);
      if (!await file.exists()) {
        LoggerService.instance.e(
          'APK文件不存在: $filePath',
          category: LogCategory.general,
          tags: ['update', 'install', 'notfound'],
        );
        return false;
      }

      LoggerService.instance.i(
        '调用原生安装方法',
        category: LogCategory.general,
        tags: ['update', 'install', 'native'],
      );
      final result = await _platformChannel.invokeMethod('installApk', {
        'filePath': filePath,
      });

      return result == true;
    } on PlatformException catch (e) {
      LoggerService.instance.e(
        '安装失败: ${e.code}',
        category: LogCategory.general,
        tags: ['update', 'install', 'error'],
      );
      return false;
    } catch (e) {
      LoggerService.instance.e(
        '安装APK失败: $e',
        category: LogCategory.general,
        tags: ['update', 'install', 'exception'],
      );
      return false;
    }
  }

  /// 忽略此版本更新
  Future<void> ignoreVersion(String version) async {
    await PreferencesService.instance.setString(_ignoreVersionKey, version);
  }

  /// 从 GitHub Release body 中提取 changelog
  ///
  /// release body 格式约定：包含 `<!--CHANGELOG_START-->` 和 `<!--CHANGELOG_END-->`
  /// 标记包围的段落。如果标记不存在，回退到标题 `## 📝 更新日志` 之后的内容。
  /// 如果都匹配不到，返回完整 body 原始值。
  static String _extractChangelog(String? body) {
    if (body == null || body.isEmpty) return '';

    // 优先匹配 HTML 注释标记
    final startMarker = '<!--CHANGELOG_START-->';
    final endMarker = '<!--CHANGELOG_END-->';
    final startIdx = body.indexOf(startMarker);
    final endIdx = body.indexOf(endMarker);

    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      final content = body
          .substring(startIdx + startMarker.length, endIdx)
          .trim();
      if (content.isNotEmpty) return content;
    }

    // 回退：匹配 ## 📝 更新日志 标题之后的内容
    final headerMarker = '## 📝 更新日志';
    final headerIdx = body.indexOf(headerMarker);
    if (headerIdx != -1) {
      final afterHeader = body.substring(headerIdx + headerMarker.length).trim();
      if (afterHeader.isNotEmpty) return afterHeader;
    }

    // 最终回退：直接返回 body 原始值
    return body;
  }

  /// 检查版本是否被忽略
  Future<bool> isVersionIgnored(String version) async {
    final ignored =
        await PreferencesService.instance.getString(_ignoreVersionKey);
    return ignored == version;
  }

  /// 清除忽略的版本
  Future<void> clearIgnoredVersion() async {
    await PreferencesService.instance.remove(_ignoreVersionKey);
  }

  /// 预览版通道开关是否启用
  static Future<bool> isPreviewChannelEnabled() async {
    return await PreferencesService.instance.getBool(
      _previewChannelKey,
      defaultValue: false,
    );
  }

  /// 设置预览版通道开关
  static Future<void> setPreviewChannelEnabled(bool enabled) async {
    await PreferencesService.instance.setBool(_previewChannelKey, enabled);
  }
}

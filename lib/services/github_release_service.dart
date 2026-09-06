import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/github_release.dart';
import 'logger_service.dart';
import 'preferences_service.dart';

/// GitHub Releases API 服务
///
/// 从 GitHub Releases 获取最新版本信息并下载 APK
class GithubReleaseService {
  static const String _apiBase = 'https://api.github.com';
  static const String _repoOwner = 'yunkst';
  static const String _repoName = 'Whimread';

  static const String _lastCheckKey = 'app_update_last_check';

  final Dio _dio;

  GithubReleaseService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 15)));

  /// 获取最新 Release 信息
  ///
  /// - [includePrerelease] 为 false（默认，stable 通道）时，调用
  ///   `/repos/{owner}/{repo}/releases/latest`：GitHub API 原生会跳过所有
  ///   prerelease，永远只返回最新的稳定版。
  /// - [includePrerelease] 为 true（preview 通道）时，调用
  ///   `/repos/{owner}/{repo}/releases?per_page=10` 拉取最近 10 条，
  ///   然后客户端按 `created_at` 降序取最新一条（排除 draft）。
  ///   GitHub API 默认排序在 prerelease 存在时不可靠（讨论 #21901），
  ///   所以客户端显式排序确保拿到发布时间最新的版本。
  ///
  /// 返回 null 表示无可用 release 或网络错误。
  Future<GithubRelease?> fetchLatestRelease({
    bool includePrerelease = false,
  }) async {
    try {
      final path = includePrerelease
          ? '/repos/$_repoOwner/$_repoName/releases?per_page=10'
          : '/repos/$_repoOwner/$_repoName/releases/latest';
      final url = '$_apiBase$path';
      LoggerService.instance.d(
        'GitHub API: $url',
        category: LogCategory.network,
        tags: ['update', 'github', includePrerelease ? 'preview' : 'stable'],
      );

      final response = await _dio.get<dynamic>(url);

      if (response.statusCode == 200 && response.data != null) {
        // latest 接口返回单个对象；列表接口返回数组。
        // preview 通道需要客户端按 created_at desc 排序取最新一条，
        // 因为 GitHub API 默认排序在 prerelease 存在时不可靠。
        final dynamic data = response.data;
        final GithubRelease release;
        if (data is List) {
          if (data.isEmpty) return null;
          final releases = data
              .map((e) => GithubRelease.fromJson(e as Map<String, dynamic>))
              .where((r) => !r.draft) // draft 永远跳过
              .toList();
          if (releases.isEmpty) return null;
          // 按 created_at 降序取最新一条
          // （publishedAt 是 String 类型，ISO 8601 格式直接按字符串排序即可）
          releases.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
          release = releases.first;
        } else {
          release = GithubRelease.fromJson(data as Map<String, dynamic>);
        }

        // draft 永远跳过（preview 通道已在列表筛选时跳过，
        // stable 通道 /latest 不返回 draft，此处双保险）
        if (release.draft) {
          LoggerService.instance.d(
            '跳过 draft: ${release.tagName}',
            category: LogCategory.network,
            tags: ['update', 'github'],
          );
          return null;
        }

        // prerelease：stable 通道跳过，preview 通道接受
        if (release.prerelease && !includePrerelease) {
          LoggerService.instance.d(
            'stable 通道跳过 prerelease: ${release.tagName}',
            category: LogCategory.network,
            tags: ['update', 'github'],
          );
          return null;
        }

        // 确认有 APK asset
        if (release.apkAsset == null) {
          LoggerService.instance.w(
            'Release ${release.tagName} 无 APK asset',
            category: LogCategory.network,
            tags: ['update', 'github'],
          );
          return null;
        }

        return release;
      }

      return null;
    } on DioException catch (e) {
      // 404 = 没有 release，静默处理
      if (e.response?.statusCode == 404) {
        LoggerService.instance.d(
          'GitHub: 无 latest release (404)',
          category: LogCategory.network,
          tags: ['update', 'github'],
        );
        return null;
      }

      LoggerService.instance.e(
        'GitHub API 请求失败: ${e.message}',
        category: LogCategory.network,
        tags: ['update', 'github', 'error'],
      );
      return null;
    } catch (e) {
      LoggerService.instance.e(
        '获取 GitHub Release 失败: $e',
        category: LogCategory.network,
        tags: ['update', 'github', 'error'],
      );
      return null;
    }
  }

  /// 检查是否应执行更新检查（频率控制）
  ///
  /// 非强制检查时，距离上次检查不足 1 小时则跳过
  Future<bool> shouldCheck({bool forceCheck = false}) async {
    if (forceCheck) return true;

    final lastCheck = await PreferencesService.instance.getInt(_lastCheckKey);
    final now = DateTime.now().millisecondsSinceEpoch;

    if ((now - lastCheck) < 3600000) {
      return false;
    }

    return true;
  }

  /// 记录检查时间
  Future<void> recordCheckTime() async {
    await PreferencesService.instance
        .setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// 下载 APK 文件
  ///
  /// [downloadUrl] GitHub asset 的 browser_download_url（完整 URL）
  /// [fileName] 保存的文件名（如 novel_app_v1.7.7.apk）
  /// [onProgress] 进度回调 0.0-1.0
  /// [onStatus] 状态文本回调
  Future<bool> downloadApk({
    required String downloadUrl,
    required String fileName,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    try {
      onStatus?.call('准备下载...');

      // 请求存储权限
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        final manageStatus =
            await Permission.manageExternalStorage.request();
        if (!manageStatus.isGranted) {
          onStatus?.call('需要存储权限');
          return false;
        }
      }

      // 获取下载目录
      final directory = await getApplicationDocumentsDirectory();
      final updatesDir = Directory('${directory.path}/updates');
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      final filePath = '${updatesDir.path}/$fileName';

      // 如果已存在同名文件，先删除
      final existingFile = File(filePath);
      if (await existingFile.exists()) {
        await existingFile.delete();
      }

      onStatus?.call('开始下载...');

      LoggerService.instance.i(
        '从 GitHub 下载 APK: $downloadUrl',
        category: LogCategory.network,
        tags: ['update', 'download'],
      );

      await _dio.download(
        downloadUrl,
        filePath,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress?.call(progress);
          }
        },
      );

      onStatus?.call('下载完成');
      onProgress?.call(1.0);

      LoggerService.instance.i(
        'APK 下载完成: $filePath',
        category: LogCategory.network,
        tags: ['update', 'download', 'success'],
      );

      return true;
    } on DioException catch (e) {
      LoggerService.instance.e(
        'APK 下载失败: ${e.message}',
        category: LogCategory.network,
        tags: ['update', 'download', 'error'],
      );

      if (e.response != null) {
        onStatus?.call('下载失败: 服务器错误 ${e.response?.statusCode}');
      } else {
        onStatus?.call('下载失败: ${e.message ?? "网络错误"}');
      }

      return false;
    } catch (e) {
      LoggerService.instance.e(
        'APK 下载异常: $e',
        category: LogCategory.network,
        tags: ['update', 'download', 'error'],
      );
      onStatus?.call('下载出错: $e');
      return false;
    }
  }
}

import 'package:dio/dio.dart';

import '../models/backend_release.dart';
import 'app_update_check_exception.dart';
import 'logger_service.dart';

/// 托管后端更新分发服务
///
/// 从 whimread-backend 获取最新版本信息（`/api/v1/app/releases/latest`），
/// 通道语义与 GitHub 对齐：stable 只返回正式版，preview 返回全通道最新。
/// APK 下载复用 [AppUpdateService] 的通用下载流程（URL 可指向后端或 CDN）。
///
/// 与 [GithubReleaseService] 的差异：网络 / 服务错误不吞掉，而是抛出
/// [AppUpdateCheckException]（cause: `network_error` / `rate_limited` /
/// `http_xxx`），由 [AppUpdateService] 决定兜底或归类为「检查失败」；
/// 404（通道无 release）返回 null。
class BackendReleaseService {
  static const String _latestPath = '/api/v1/app/releases/latest';

  final Dio _dio;
  final String _baseUrl;

  /// [baseUrl] 后端地址（由调用方经 `resolveBackendHost()` 解析后传入）；
  /// 末尾斜杠在此统一裁剪。
  BackendReleaseService({Dio? dio, required String baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// 获取最新 Release 信息
  ///
  /// - [includePrerelease] false（stable 通道）→ `channel=stable`
  /// - [includePrerelease] true（preview 通道）→ `channel=preview`
  ///
  /// 返回 null 表示后端正常但该通道无可用 release。
  Future<BackendRelease?> fetchLatestRelease({
    required bool includePrerelease,
  }) async {
    final channel = includePrerelease ? 'preview' : 'stable';
    final url = '$_baseUrl$_latestPath';
    LoggerService.instance.d(
      'Backend API: $url (channel=$channel)',
      category: LogCategory.network,
      tags: ['update', 'backend', channel],
    );

    try {
      final response = await _dio.get<dynamic>(
        url,
        queryParameters: {'channel': channel},
      );

      if (response.statusCode == 200 && response.data != null) {
        return BackendRelease.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      // 404 = 通道无可用 release，静默处理
      if (e.response?.statusCode == 404) {
        LoggerService.instance.d(
          'Backend: 通道无可用 release (404)',
          category: LogCategory.network,
          tags: ['update', 'backend'],
        );
        return null;
      }

      final cause = e.response?.statusCode == 429
          ? 'rate_limited'
          : e.response != null
              ? 'http_${e.response?.statusCode}'
              : 'network_error';
      LoggerService.instance.w(
        '后端更新检查失败($cause): ${e.message}',
        category: LogCategory.network,
        tags: ['update', 'backend', cause],
      );
      throw AppUpdateCheckException(
        '后端检查更新失败',
        cause: cause,
      );
    }
  }
}

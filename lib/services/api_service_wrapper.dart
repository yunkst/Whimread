import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:novel_api/novel_api.dart';
import 'package:built_value/serializer.dart';
import 'dart:io';
import '../core/backend/backend_config.dart';
import '../models/remote_script.dart';
import 'logger_service.dart';
import 'preferences_service.dart';

/// API 服务封装层
///
/// 提供统一的 Dio HTTP 客户端配置、后端地址管理、错误处理与重试。
/// 直接调用 backend REST API（不走 OpenAPI 生成的 DefaultApi），
/// 部分方法使用 novel_api 包定义的类型做反序列化（如 BackupUploadResponse）。
///
/// ## 核心职责
/// 1. **配置管理**：统一管理后端 Host（托管模式以打包注入地址优先）
/// 2. **设备鉴权**：经 [authHeaderProvider] 注入设备 JWT 请求头
/// 3. **凭证自愈**：401 时经 [unauthorizedRecoveryProvider] 换新凭证重放一次
/// 4. **错误处理**：网络异常的统一处理和重试机制
/// 5. **连接管理**：自动检测连接健康状态，必要时重新初始化
///
/// ## 使用示例
/// ```dart
/// final apiService = ref.watch(apiServiceWrapperProvider);
/// ```
class ApiServiceWrapper {
  /// 公共构造函数 - 通过依赖注入创建实例
  ///
  /// [dio] Dio HTTP 客户端实例（可选，用于自定义配置）
  /// 若未提供,则构造一个全新的 [Dio] 实例（一次性创建,后续 [init] 复用同一实例,避免泄漏）。
  ApiServiceWrapper([Dio? dio]) : _dio = dio ?? Dio();

  /// 内部 Dio 实例（一次性创建,init() 复用而非重建,避免连接池/拦截器泄漏）
  final Dio _dio;

  /// 只读暴露内部 Dio 实例
  ///
  /// 供单元测试注入 [HttpClientAdapter] 拦截 HTTP 请求，也可用于调试。
  Dio get dio => _dio;

  /// 设备 JWT 请求头提供者（`Authorization: Bearer <设备JWT>`）。
  ///
  /// AI 托管模式下所有后端请求以匿名设备身份鉴权（原 X-API-TOKEN 已移除）。
  /// 由 APP 启动时注入 `DeviceAuthService.authedHeaders`，避免本文件与
  /// 设备服务形成循环 import；未注入时需要鉴权的请求直接抛错。
  Future<Map<String, String>> Function()? authHeaderProvider;

  /// 401 自动恢复回调：刷新设备凭证并返回新请求头，返回 null 表示无法恢复。
  ///
  /// 由 APP 启动时注入 `DeviceAuthService.renewAuthHeaders`（与
  /// [authHeaderProvider] 同理避免循环 import）；[_AuthRetryInterceptor]
  /// 在收到 401 时调用它换新凭证重放请求（每个请求至多重试一次）。
  Future<Map<String, String>?> Function()? unauthorizedRecoveryProvider;

  /// 进行中的凭证恢复（并发 401 共享同一次刷新，避免重复注册）
  Future<Map<String, String>?>? _recoveryInFlight;

  Future<Map<String, String>?> _recoverAuthHeaders() {
    final provider = unauthorizedRecoveryProvider;
    if (provider == null) return Future.value(null);
    return _recoveryInFlight ??=
        provider().whenComplete(() => _recoveryInFlight = null);
  }

  /// 取设备鉴权请求头
  Future<Map<String, String>> _authHeaders() async {
    final provider = authHeaderProvider;
    if (provider == null) {
      throw Exception('设备凭证未就绪（authHeaderProvider 未注入）');
    }
    return await provider();
  }

  bool _initialized = false;

  /// 是否已完成 [init]
  bool get isInitialized => _initialized;

  /// 初始化 API 客户端
  ///
  /// 必须在使用前调用一次。复用构造时一次性创建的 [Dio] 实例（不再重建）,
  /// 仅更新其配置 / Adapter / 拦截器,避免连接池与 LogInterceptor 泄漏。
  Future<void> init() async {
    final host = await getHost();

    LoggerService.instance.d(
      '=== ApiServiceWrapper 初始化 ===',
      category: LogCategory.network,
      tags: ['debug', 'lifecycle'],
    );
    LoggerService.instance.i(
      'Host: $host',
      category: LogCategory.network,
      tags: ['api'],
    );

    if (host == null || host.isEmpty) {
      throw Exception('后端 HOST 未配置');
    }

    // 复用构造时一次性创建的 _dio,只更新配置 / adapter / 拦截器
    _dio.options.baseUrl = host;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 90);
    _dio.options.sendTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      // 注：CORS 响应头（Access-Control-Allow-*）由后端返回，客户端请求头
      // 不应携带（2026-09 审查修复：原误写在请求头里，无效且污染日志）。
    };

    // 重置 httpClientAdapter（关闭旧 client,创建新的）
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        // 优化连接池配置：减少连接数避免资源耗尽
        client.maxConnectionsPerHost = 20;
        // 设置连接空闲超时，避免长时间占用连接
        client.idleTimeout = const Duration(seconds: 60);
        // 设置连接超时
        client.connectionTimeout = const Duration(seconds: 15);
        return client;
      },
    );

    LoggerService.instance.i(
      '✅ Dio连接池配置已优化: 20个并发连接/主机，60秒空闲超时',
      category: LogCategory.network,
      tags: ['success', 'api'],
    );

    // 清理已有日志拦截器（防止重复 add 累积），再添加新的。
    // 同时清理 dio 自带 LogInterceptor 与 QuietLogInterceptor——防御性，
    // 应对旧版本残留或测试重复注入同一 Dio 实例。
    // 使用 QuietLogInterceptor 而非 dio 自带 LogInterceptor：
    // 上报型请求（日志上报 / 反馈提交）在 Options.extra 里带 `quiet: true`
    // 时跳过打印，避免「打日志 → 触发上报 → 上报又打日志」的日志风暴。
    _dio.interceptors
        .whereType<LogInterceptor>()
        .toList()
        .forEach(_dio.interceptors.remove);
    _dio.interceptors
        .whereType<QuietLogInterceptor>()
        .toList()
        .forEach(_dio.interceptors.remove);
    _dio.interceptors.add(QuietLogInterceptor(
      requestBody: false, // 请求体含凭证/证书链/用户日志，不打印（2026-09 审查）
      responseBody: false, // 减少日志输出
      logPrint: (obj) => LoggerService.instance.d(
        '[API] $obj',
        category: LogCategory.network,
        tags: ['interceptor'],
      ),
    ));

    // 401 自动续签拦截器（与 LogInterceptor 同理去重，防止 init 重复累积）
    _dio.interceptors
        .whereType<_AuthRetryInterceptor>()
        .toList()
        .forEach(_dio.interceptors.remove);
    _dio.interceptors.add(_AuthRetryInterceptor(this));

    _initialized = true;
    LoggerService.instance.d(
      '✓ ApiServiceWrapper 初始化完成',
      category: LogCategory.network,
      tags: ['debug', 'lifecycle'],
    );
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw Exception('ApiServiceWrapper 未初始化，请先调用 init()');
    }
  }

  // ========================================================================
// 统一错误处理
// ========================================================================

  /// 获取配置的 Host（统一走 [resolveBackendHost]，不要直接读 prefs key）
  Future<String?> getHost() => resolveBackendHost();

  /// 设置后端配置（本地开发自定义 Host 用；托管模式 Host 以打包注入为准）
  Future<void> setConfig({required String host}) async {
    await PreferencesService.instance
        .setString(kPrefsBackendHostKey, host.trim());
    await init();
  }

  /// 统一错误处理
  Exception _handleError(dynamic error) {
    if (error is DioException) {
      if (error.response != null) {
        return Exception(
            'API 错误: ${error.response?.statusCode} - ${error.response?.data}');
      } else {
        return Exception('网络错误: ${error.message}');
      }
    }
    return Exception('未知错误: $error');
  }

  /// 统一异常包装器
  ///
  /// 把各业务方法的 try / catch / log / rethrow 收敛到这里:
  /// - 内部 `body()` 抛出 → 走 [LoggerService] 记录,再通过 [_handleError] 转为
  ///   统一 [Exception] 类型后抛给上层;
  /// - 上层只需专注于业务实现,不再重复错误处理样板代码。
  ///
  /// [opTag] 用于日志的「操作名」标签,定位是哪一类业务失败。
  Future<T> _guard<T>(String opTag, Future<T> Function() body) async {
    try {
      return await body();
    } catch (e, st) {
      LoggerService.instance.e(
        opTag,
        stackTrace: st.toString(),
        category: LogCategory.network,
        tags: ['error', 'api', 'failed'],
      );
      throw _handleError(e);
    }
  }

  /// 释放资源
  ///
  /// 真正关闭内部 [Dio]（含其 [HttpClientAdapter] 与连接池）并标记未初始化。
  /// 由 Provider 在 dispose 阶段调用,也可手动调用。
  void dispose() {
    LoggerService.instance.i(
      'ApiServiceWrapper.dispose() called, closing Dio',
      category: LogCategory.network,
      tags: ['lifecycle', 'dispose'],
    );
    _dio.close(force: true);
    _initialized = false;
  }

  // ========================================================================
  // 备份相关 API
  // ========================================================================

  /// 上传数据库备份
  ///
  /// [dbFile] 数据库文件
  /// [onProgress] 上传进度回调
  ///
  /// 返回BackupUploadResponse，包含上传结果信息
  Future<BackupUploadResponse> uploadBackup({
    required File dbFile,
    ProgressCallback? onProgress,
  }) async {
    _ensureInitialized();
    return _guard('备份上传失败', () async {
      final authHeaders = await _authHeaders();

      // 直接用 Dio 构造 multipart 请求，绕过生成的 BackupApi
      // （生成的 BackupApi 的 encodeFormParameter 处理文件路径时格式不正确，导致 422）
      final fileName = dbFile.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          dbFile.path,
          filename: fileName,
        ),
      });

      final response = await _dio.post(
        '/api/backup/upload',
        data: formData,
        options: Options(
          headers: authHeaders,
          contentType: 'multipart/form-data',
        ),
        onSendProgress: onProgress,
      );

      if (response.statusCode == 200 && response.data != null) {
        final result = standardSerializers.deserialize(
          response.data,
          specifiedType: const FullType(BackupUploadResponse),
        ) as BackupUploadResponse;

        LoggerService.instance.i(
          '备份上传成功: ${result.storedPath}',
          category: LogCategory.network,
          tags: ['backup', 'success'],
        );
        return result;
      } else {
        throw Exception('备份上传失败：${response.statusCode}');
      }
    });
  }

  /// 获取服务器备份列表
  ///
  /// 返回服务器上所有备份文件的信息（按时间倒序）
  /// 直接使用 _dio 绕过 OpenAPI 生成代码
  Future<List<Map<String, dynamic>>> getBackupList() async {
    _ensureInitialized();
    return _guard('获取备份列表失败', () async {
      final authHeaders = await _authHeaders();

      final response = await _dio.get(
        '/api/backup/list',
        options: Options(
          headers: authHeaders,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final backups = (data['backups'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];

        LoggerService.instance.i(
          '获取备份列表成功: ${backups.length} 条',
          category: LogCategory.network,
          tags: ['backup', 'list', 'success'],
        );
        return backups;
      } else {
        throw Exception('获取备份列表失败：${response.statusCode}');
      }
    });
  }

  /// 下载备份到本地文件
  ///
  /// [backupId] 备份唯一标识（如 "2025-07-15/novel_app_backup.db"）
  /// [savePath] 本地保存路径
  /// [onProgress] 下载进度回调（可选）
  ///
  /// 返回本地保存的文件路径
  Future<String> downloadBackup({
    required String backupId,
    required String savePath,
    ProgressCallback? onProgress,
  }) async {
    _ensureInitialized();
    return _guard('备份下载失败: $backupId', () async {
      final authHeaders = await _authHeaders();

      // 对 backupId 进行 URL 编码（路径含 /）
      final encodedId = Uri.encodeComponent(backupId);

      await _dio.download(
        '/api/backup/download/$encodedId',
        savePath,
        options: Options(
          headers: authHeaders,
        ),
        onReceiveProgress: onProgress,
      );

      LoggerService.instance.i(
        '备份下载成功: $backupId -> $savePath',
        category: LogCategory.network,
        tags: ['backup', 'download', 'success'],
      );
      return savePath;
    });
  }

  /// 删除服务器上的备份
  ///
  /// [backupId] 备份唯一标识（如 "2025-07-15/novel_app_backup.db"）
  Future<void> deleteBackupOnServer({required String backupId}) async {
    _ensureInitialized();
    return _guard('备份删除失败: $backupId', () async {
      final authHeaders = await _authHeaders();

      final encodedId = Uri.encodeComponent(backupId);

      final response = await _dio.delete(
        '/api/backup/delete/$encodedId',
        options: Options(
          headers: authHeaders,
        ),
      );

      if (response.statusCode == 200) {
        LoggerService.instance.i(
          '备份删除成功: $backupId',
          category: LogCategory.network,
          tags: ['backup', 'delete', 'success'],
        );
      } else {
        throw Exception('备份删除失败：${response.statusCode}');
      }
    });
  }

  // ========================================================================
  // 云端脚本仓库 API（v47 起）
  // ========================================================================

  /// 按 host 搜索云端脚本（仅返回管理员已审核通过的最新版本）
  ///
  /// 返回空列表 = 云端无命中。网络 / 服务错误抛 [_guard] 统一异常，
  /// 由上层（RemoteScriptService）决定降级到 AI 写脚本。
  Future<List<RemoteScriptMeta>> searchRemoteScripts({
    required String host,
  }) {
    return _guard('云端脚本搜索失败: host=$host', () async {
      final headers = await _authHeaders();
      final response = await _dio.get<List<dynamic>>(
        '/api/v1/scripts/search',
        queryParameters: {'host': host},
        options: Options(headers: headers),
      );
      final data = response.data ?? const [];
      return data
          .map((e) =>
              RemoteScriptMeta.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// 拉取云端脚本完整载荷（仅 approved 可下）
  Future<RemoteScriptPayload> getRemoteScript(String remoteId) {
    return _guard('云端脚本下载失败: remoteId=$remoteId', () async {
      final headers = await _authHeaders();
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/scripts/$remoteId',
        options: Options(headers: headers),
      );
      return RemoteScriptPayload.fromJson(response.data!);
    });
  }

  /// 共享本地脚本到云端（初始状态 pending_review，待管理员审核）
  Future<RemoteShareResult> shareScriptToRemote({
    required String domain,
    required String displayName,
    required String chapterListJs,
    required String chapterContentJs,
    required String bookshelfJs,
    required String sampleUrl,
    required String urlPattern,
    required bool chapterListOcr,
    required bool chapterContentOcr,
    required int preferredMode,
    required String sha256,
  }) {
    return _guard('脚本共享提交失败: domain=$domain', () async {
      final headers = await _authHeaders();
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/scripts',
        data: {
          'domain': domain,
          'display_name': displayName,
          'chapter_list_js': chapterListJs,
          'chapter_content_js': chapterContentJs,
          'bookshelf_js': bookshelfJs,
          'sample_url': sampleUrl,
          'url_pattern': urlPattern,
          'chapter_list_ocr': chapterListOcr,
          'chapter_content_ocr': chapterContentOcr,
          'preferred_mode': preferredMode,
          'sha256': sha256,
        },
        options: Options(headers: headers),
      );
      return RemoteShareResult.fromJson(response.data!);
    });
  }

  /// 取消共享（仅作者本人有效）
  Future<void> unshareRemoteScript(String remoteId) {
    return _guard('取消共享失败: remoteId=$remoteId', () async {
      final headers = await _authHeaders();
      await _dio.delete<void>(
        '/api/v1/scripts/$remoteId',
        options: Options(headers: headers),
      );
    });
  }

  /// 批量检查更新：返回 (remoteId, localVersion) 中云端版本更高的条目
  Future<List<RemoteScriptUpdate>> checkRemoteScriptUpdates({
    required List<({String remoteId, int version})> items,
  }) {
    return _guard('云端脚本更新检查失败', () async {
      if (items.isEmpty) return const [];
      final headers = await _authHeaders();
      final response = await _dio.post<List<dynamic>>(
        '/api/v1/scripts/updates',
        data: {
          'items': items
              .map((e) => {'remote_id': e.remoteId, 'version': e.version})
              .toList(),
        },
        options: Options(headers: headers),
      );
      final data = response.data ?? const [];
      return data
          .map((e) =>
              RemoteScriptUpdate.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}

/// 401 时刷新设备凭证并重放请求一次的拦截器。
///
/// 设备 JWT 是 30 天期会话凭证，过期后所有鉴权请求会集体 401；
/// 这里经 [ApiServiceWrapper.unauthorizedRecoveryProvider] 换新凭证后
/// 重放原请求，对调用方透明。挑战/注册端点本身不携带凭证，其 401
/// 与 token 无关，不进入重试（否则恢复流程会自激）。
class _AuthRetryInterceptor extends Interceptor {
  _AuthRetryInterceptor(this._wrapper);

  static const String _retriedKey = 'auth_retry_done';

  /// 不携带设备凭证的端点（重注册链路自身）
  static const List<String> _unauthenticatedPaths = [
    '/api/v1/devices/challenge',
    '/api/v1/devices/register',
  ];

  final ApiServiceWrapper _wrapper;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final path = options.path;
    final isAuthEndpoint =
        _unauthenticatedPaths.any((p) => path.contains(p));
    if (err.response?.statusCode != 401 ||
        options.extra[_retriedKey] == true ||
        isAuthEndpoint) {
      return handler.next(err);
    }

    final freshHeaders = await _wrapper._recoverAuthHeaders();
    if (freshHeaders == null) return handler.next(err);

    options.extra[_retriedKey] = true;
    options.headers.addAll(freshHeaders);
    try {
      final response = await _wrapper.dio.fetch(options);
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    } catch (_) {
      // 重试出现非 Dio 异常（如反序列化失败）：保持原始 401 语义
      return handler.next(err);
    }
  }
}

/// 支持「按请求静默」的日志拦截器（dio 自带 [LogInterceptor] 的替代品）。
///
/// 请求在 `Options.extra` 里带 `quiet: true` 时，onRequest / onResponse /
/// onError 全程跳过日志打印。`extra` 会随请求透传到响应与错误阶段
/// （`err.requestOptions.extra` 也能取到），三处统一判断。
///
/// 背景：日志上报（LogReporterService）/ 反馈提交挂到共享 Dio 后，若沿用
/// dio 自带 LogInterceptor，每条上报请求又会打日志进 LoggerService 缓冲区、
/// 再被上报——形成日志风暴。上报型请求带 `quiet` 标记即可切断。
class QuietLogInterceptor extends Interceptor {
  QuietLogInterceptor({
    this.requestBody = false,
    this.responseBody = false,
    required this.logPrint,
  });

  /// 是否打印请求体（默认关，避免上传内容刷屏）
  final bool requestBody;

  /// 是否打印响应体（默认关，减少日志输出）
  final bool responseBody;

  final void Function(Object object) logPrint;

  static const String _quietKey = 'quiet';

  bool _isQuiet(RequestOptions options) => options.extra[_quietKey] == true;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (!_isQuiet(options)) {
      logPrint('*** Request ***');
      logPrint('uri: ${options.uri}');
      logPrint('method: ${options.method}');
      if (requestBody && options.data != null) {
        logPrint('data: ${options.data}');
      }
      logPrint('');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!_isQuiet(response.requestOptions)) {
      logPrint('*** Response ***');
      logPrint('uri: ${response.realUri}');
      logPrint('statusCode: ${response.statusCode}');
      if (responseBody) {
        logPrint('Response Text: ${response.data}');
      }
      logPrint('');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!_isQuiet(err.requestOptions)) {
      logPrint('*** DioException ***');
      logPrint('uri: ${err.requestOptions.uri}');
      logPrint('$err');
      if (err.response != null) {
        logPrint('statusCode: ${err.response?.statusCode}');
      }
      logPrint('');
    }
    handler.next(err);
  }
}

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:novel_api/novel_api.dart';
import 'package:built_value/serializer.dart';
import 'dart:io';
import 'dart:typed_data';
import '../core/constants/build_config.dart';
import 'logger_service.dart';
import 'preferences_service.dart';

/// API 服务封装层
///
/// 提供统一的 Dio HTTP 客户端配置、后端地址/Token 管理、错误处理与重试。
/// 直接调用 backend REST API（不走 OpenAPI 生成的 DefaultApi），
/// 部分方法使用 novel_api 包定义的类型做反序列化（如 BackupUploadResponse）。
///
/// ## 核心职责
/// 1. **配置管理**：统一管理后端 Host 和 API Token
/// 2. **错误处理**：网络异常的统一处理和重试机制
/// 3. **连接管理**：自动检测连接健康状态，必要时重新初始化
///
/// ## 使用示例
/// ```dart
/// final apiService = ref.watch(apiServiceWrapperProvider);
/// ```
class ApiServiceWrapper {
  static const String _prefsHostKey = 'backend_host';
  static const String _prefsTokenKey = 'backend_token';

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
      // CORS headers for web requests
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers':
          'Content-Type, Authorization, X-API-TOKEN',
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

    // 清理已有 LogInterceptor（防止重复 add 累积），再添加新的
    _dio.interceptors
        .whereType<LogInterceptor>()
        .toList()
        .forEach(_dio.interceptors.remove);
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: false, // 减少日志输出
      logPrint: (obj) => LoggerService.instance.d(
        '[API] $obj',
        category: LogCategory.network,
        tags: ['interceptor'],
      ),
    ));

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

  /// 获取配置的 Host
  Future<String?> getHost() async {
    // 打包注入的托管后端优先（Whimread AI 托管模式）
    if (kHasBundledBackend) return kBackendBaseUrl;
    return await PreferencesService.instance.getString(_prefsHostKey);
  }

  /// 获取配置的 Token
  Future<String?> getToken() async {
    return await PreferencesService.instance.getString(_prefsTokenKey);
  }

  /// 设置后端配置
  Future<void> setConfig({required String host, String? token}) async {
    await PreferencesService.instance.setString(_prefsHostKey, host.trim());
    if (token != null) {
      await PreferencesService.instance.setString(_prefsTokenKey, token.trim());
    }

    // 重新初始化
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
      final token = await getToken();

      if (token == null || token.isEmpty) {
        throw Exception('API Token未配置');
      }

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
          headers: {'X-API-TOKEN': token},
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
      final token = await getToken();

      if (token == null || token.isEmpty) {
        throw Exception('API Token未配置');
      }

      final response = await _dio.get(
        '/api/backup/list',
        options: Options(
          headers: {'X-API-TOKEN': token},
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
      final token = await getToken();

      if (token == null || token.isEmpty) {
        throw Exception('API Token未配置');
      }

      // 对 backupId 进行 URL 编码（路径含 /）
      final encodedId = Uri.encodeComponent(backupId);

      await _dio.download(
        '/api/backup/download/$encodedId',
        savePath,
        options: Options(
          headers: {'X-API-TOKEN': token},
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
      final token = await getToken();

      if (token == null || token.isEmpty) {
        throw Exception('API Token未配置');
      }

      final encodedId = Uri.encodeComponent(backupId);

      final response = await _dio.delete(
        '/api/backup/delete/$encodedId',
        options: Options(
          headers: {'X-API-TOKEN': token},
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

  // ======================== 文生图（ComfyUI） ========================

  /// 获取可用文生图工作流列表（GET /api/models 的 text2img 节）。
  ///
  /// 返回精简字段 [{name, description, isDefault, promptSkill}]，name 即工作流标题，
  /// 作为 create_images 的 modelName 参数；promptSkill 是该工作流的提示词写作技巧
  /// （含正向/负向 prompt 的写法建议），为 null 表示后端未配置。
  Future<List<Map<String, dynamic>>> getText2ImgModels() async {
    _ensureInitialized();
    return _guard('获取文生图模型列表失败', () async {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        throw Exception('API Token未配置');
      }
      final response = await _dio.get(
        '/api/models',
        options: Options(headers: {'X-API-TOKEN': token}),
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final list = (data['text2img'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        // 精简字段：title → name，prompt_skill → promptSkill
        return list
            .map((m) => {
                  'name': m['title'],
                  'description': m['description'],
                  'isDefault': m['is_default'] == true,
                  'promptSkill': m['prompt_skill'],
                })
            .toList();
      }
      throw Exception('获取文生图模型列表失败：${response.statusCode}');
    });
  }

  /// 提交一个文生图任务（POST /api/text2img/generate）。
  ///
  /// [prompt] 图片生成提示词；[modelName] 工作流标题（来自 getText2ImgModels），
  /// 不传则后端用默认工作流；[negativePrompt] 负向提示词（可选，仅工作流含
  /// 「负向提示词在这里替换」占位符时生效，否则静默忽略）。返回后端 task_id。
  Future<String> submitText2ImgTask({
    required String prompt,
    String? modelName,
    String? negativePrompt,
  }) async {
    _ensureInitialized();
    return _guard('提交文生图任务失败: prompt=${prompt.length}字符', () async {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        throw Exception('API Token未配置');
      }
      final response = await _dio.post(
        '/api/text2img/generate',
        data: {
          'prompt': prompt,
          if (modelName != null && modelName.isNotEmpty)
            'model_name': modelName,
          if (negativePrompt != null && negativePrompt.isNotEmpty)
            'negative_prompt': negativePrompt,
        },
        options: Options(
          headers: {'X-API-TOKEN': token},
          contentType: 'application/json',
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final taskId = (response.data as Map<String, dynamic>)['task_id'];
        if (taskId is String && taskId.isNotEmpty) return taskId;
        throw Exception('后端未返回有效的 task_id');
      }
      throw Exception('提交文生图任务失败：${response.statusCode}');
    });
  }

  /// 按 task_id 拉取文生图结果（GET /api/text2img/image/{task_id}）。
  ///
  /// 不抛异常，返回 (bytes?, statusCode)：
  /// - 200 → (bytes, 200)，bytes 为 PNG 二进制
  /// - 202 → (null, 202)，图片仍在生成
  /// - 404 → (null, 404)，任务不存在/失败
  /// - 其他/网络错误 → (null, code)
  ///
  /// 上层（_GalleryImage）靠 statusCode 决策 loading / loaded / 刷新。
  Future<(Uint8List?, int)> fetchText2ImgImage(String taskId) async {
    _ensureInitialized();
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return (null, 401);
      }
      final response = await _dio.get(
        '/api/text2img/image/$taskId',
        options: Options(
          headers: {'X-API-TOKEN': token},
          responseType: ResponseType.bytes,
          // 202/404 不当错误抛，统一靠 statusCode 判断
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        return ((response.data as Uint8List?) ?? Uint8List(0), 200);
      }
      return (null, response.statusCode ?? 0);
    } on DioException catch (e, st) {
      // validateStatus 放行的非 2xx 已在上面处理；这里仅网络层错误
      final code = e.response?.statusCode ?? 0;
      LoggerService.instance.w(
        '拉取文生图失败: taskId=$taskId code=$code - ${e.message}',
        stackTrace: st.toString(),
        category: LogCategory.network,
        tags: ['text2img', 'image', 'fetch', 'failed'],
      );
      return (null, code);
    } catch (e, st) {
      LoggerService.instance.e(
        '拉取文生图异常: taskId=$taskId - $e',
        stackTrace: st.toString(),
        category: LogCategory.network,
        tags: ['text2img', 'image', 'fetch', 'error'],
      );
      return (null, 0);
    }
  }

  /// 提交一个图生视频任务（POST /api/image-to-video/generate，multipart）。
  ///
  /// [prompt] 视频生成提示词；[imageBytes] 输入图片字节；[imageFilename] 图片
  /// 文件名（backend 用作 ComfyUI 加载名）；[modelName] 工作流标题（可选）。
  /// 返回后端 task_id。
  Future<String> submitImageToVideoTask({
    required String prompt,
    required Uint8List imageBytes,
    required String imageFilename,
    String? modelName,
  }) async {
    _ensureInitialized();
    return _guard('提交图生视频任务失败: prompt=${prompt.length}字符', () async {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        throw Exception('API Token未配置');
      }
      final formData = FormData.fromMap({
        'prompt': prompt,
        if (modelName != null && modelName.isNotEmpty) 'model_name': modelName,
        'image': MultipartFile.fromBytes(imageBytes, filename: imageFilename),
      });
      final response = await _dio.post(
        '/api/image-to-video/generate',
        data: formData,
        options: Options(
          headers: {'X-API-TOKEN': token},
          contentType: 'multipart/form-data',
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final taskId = (response.data as Map<String, dynamic>)['task_id'];
        if (taskId is String && taskId.isNotEmpty) return taskId;
        throw Exception('后端未返回有效的 task_id');
      }
      throw Exception('提交图生视频任务失败：${response.statusCode}');
    });
  }

  /// 按 task_id 拉取图生视频结果（GET /api/image-to-video/video/{task_id}）。
  ///
  /// 不抛异常，返回 (bytes?, statusCode)：
  /// - 200 → (bytes, 200)，bytes 为 mp4 二进制
  /// - 202 → (null, 202)，视频仍在生成
  /// - 404 → (null, 404)，任务不存在/失败
  /// - 其他/网络错误 → (null, code)
  ///
  /// 上层靠 statusCode 决策 loading / loaded / 刷新，与文生图取图同构。
  Future<(Uint8List?, int)> fetchImageToVideoVideo(String taskId) async {
    _ensureInitialized();
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return (null, 401);
      }
      final response = await _dio.get(
        '/api/image-to-video/video/$taskId',
        options: Options(
          headers: {'X-API-TOKEN': token},
          responseType: ResponseType.bytes,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        return ((response.data as Uint8List?) ?? Uint8List(0), 200);
      }
      return (null, response.statusCode ?? 0);
    } on DioException catch (e, st) {
      final code = e.response?.statusCode ?? 0;
      LoggerService.instance.w(
        '拉取图生视频失败: taskId=$taskId code=$code - ${e.message}',
        stackTrace: st.toString(),
        category: LogCategory.network,
        tags: ['image_to_video', 'video', 'fetch', 'failed'],
      );
      return (null, code);
    } catch (e, st) {
      LoggerService.instance.e(
        '拉取图生视频异常: taskId=$taskId - $e',
        stackTrace: st.toString(),
        category: LogCategory.network,
        tags: ['image_to_video', 'video', 'fetch', 'error'],
      );
      return (null, 0);
    }
  }
}

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:novel_api/src/api_util.dart';
import 'package:novel_api/src/model/backup_upload_response.dart';
import 'package:novel_api/src/model/http_validation_error.dart';

class BackupApi {

  final Dio _dio;

  final Serializers _serializers;

  const BackupApi(this._dio, this._serializers);

  /// Upload Backup
  /// 上传数据库备份文件  - **file**: 数据库备份文件(.db格式) - 返回: 文件上传结果，包含存储路径、文件大小、上传时间等信息  **功能特性**: - 支持.db格式文件 - 按日期组织存储目录 (YYYY-MM-DD/) - 保留所有历史文件（不覆盖） - 使用原文件名，同名文件时追加时间戳避免冲突  **认证**: 需要X-API-TOKEN header  **示例请求**: &#x60;&#x60;&#x60;bash curl -X POST \&quot;http://localhost:3800/api/backup/upload\&quot;          -H \&quot;X-API-TOKEN: your-token\&quot;          -F \&quot;file&#x3D;@novel_app_backup.db\&quot; &#x60;&#x60;&#x60;  **示例响应**: &#x60;&#x60;&#x60;json {   \&quot;filename\&quot;: \&quot;novel_app_backup.db\&quot;,   \&quot;stored_path\&quot;: \&quot;backups/2025-01-28/novel_app_backup.db\&quot;,   \&quot;file_size\&quot;: 1048576,   \&quot;uploaded_at\&quot;: \&quot;2025-01-28T12:34:56\&quot;,   \&quot;stored_name\&quot;: \&quot;novel_app_backup.db\&quot; } &#x60;&#x60;&#x60;
  ///
  /// Parameters:
  /// * [file] - 数据库备份文件(.db)
  /// * [X_API_TOKEN] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [BackupUploadResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<BackupUploadResponse>> uploadBackupApiBackupUploadPost({ 
    required String file,
    String? X_API_TOKEN,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/backup/upload';
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        r'X-API-TOKEN': X_API_TOKEN,
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'HTTPBearer',
          },
        ],
        ...?extra,
      },
      contentType: 'multipart/form-data',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      _bodyData = FormData.fromMap(<String, dynamic>{
        r'file': encodeFormParameter(_serializers, file, const FullType(String)),
      });

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    BackupUploadResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(BackupUploadResponse),
      ) as BackupUploadResponse;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<BackupUploadResponse>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

}

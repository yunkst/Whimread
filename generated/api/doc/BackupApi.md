# novel_api.api.BackupApi

## Load the API package
```dart
import 'package:novel_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**uploadBackupApiBackupUploadPost**](BackupApi.md#uploadbackupapibackupuploadpost) | **POST** /api/backup/upload | Upload Backup


# **uploadBackupApiBackupUploadPost**
> BackupUploadResponse uploadBackupApiBackupUploadPost(file, X_API_TOKEN)

Upload Backup

上传数据库备份文件  - **file**: 数据库备份文件(.db格式) - 返回: 文件上传结果，包含存储路径、文件大小、上传时间等信息  **功能特性**: - 支持.db格式文件 - 按日期组织存储目录 (YYYY-MM-DD/) - 保留所有历史文件（不覆盖） - 使用原文件名，同名文件时追加时间戳避免冲突  **认证**: 需要X-API-TOKEN header  **示例请求**: ```bash curl -X POST \"http://localhost:3800/api/backup/upload\"          -H \"X-API-TOKEN: your-token\"          -F \"file=@novel_app_backup.db\" ```  **示例响应**: ```json {   \"filename\": \"novel_app_backup.db\",   \"stored_path\": \"backups/2025-01-28/novel_app_backup.db\",   \"file_size\": 1048576,   \"uploaded_at\": \"2025-01-28T12:34:56\",   \"stored_name\": \"novel_app_backup.db\" } ```

### Example
```dart
import 'package:novel_api/api.dart';

final api = NovelApi().getBackupApi();
final String file = file_example; // String | 数据库备份文件(.db)
final String X_API_TOKEN = X_API_TOKEN_example; // String | 

try {
    final response = api.uploadBackupApiBackupUploadPost(file, X_API_TOKEN);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BackupApi->uploadBackupApiBackupUploadPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **file** | **String**| 数据库备份文件(.db) | 
 **X_API_TOKEN** | **String**|  | [optional] 

### Return type

[**BackupUploadResponse**](BackupUploadResponse.md)

### Authorization

[HTTPBearer](../README.md#HTTPBearer)

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


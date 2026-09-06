# novel_api.model.RoleCardTaskStatusResponse

## Load the model package
```dart
import 'package:novel_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**taskId** | **int** | 任务ID | 
**roleId** | **String** | 人物卡ID | 
**status** | **String** | 任务状态: pending/running/completed/failed | 
**totalPrompts** | **int** | 生成的提示词数量 | 
**generatedImages** | **int** | 成功生成的图片数量 | 
**resultMessage** | **String** |  | [optional] 
**errorMessage** | **String** |  | [optional] 
**createdAt** | **String** | 创建时间 | 
**startedAt** | **String** |  | [optional] 
**completedAt** | **String** |  | [optional] 
**progressPercentage** | **num** | 进度百分比 | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)



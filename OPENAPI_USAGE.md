# OpenAPI 代码生成使用文档

## 架构说明

本项目使用 openapi-generator 自动生成类型安全的 API 客户端代码。

### 目录结构
```
novel_app/
├── lib/
│   ├── generated/api/           # 自动生成（不提交到 Git）
│   └── services/
│       └── api_service_wrapper.dart  # 封装层
├── tool/
│   └── generate_api.dart        # 生成脚本
├── openapi-config.yaml          # openapi-generator 配置
└── pubspec.yaml
```

## 使用步骤

### 1. 安装前置依赖

```bash
# 安装 openapi-generator-cli
npm install -g @openapitools/openapi-generator-cli

# 安装 Flutter 依赖
flutter pub get
```

### 2. 启动后端服务

确保后端服务运行在 `http://localhost:3800`，并且 `/openapi.json` 可访问。

### 3. 生成 API 客户端代码

```bash
# 运行生成脚本
dart run tool/generate_api.dart

# 安装生成代码的依赖
flutter pub get
```

生成的代码在 `lib/generated/api/` 目录下，包括：
- API 客户端类
- 数据模型类
- 序列化代码

### 4. 完善封装层

打开 `lib/services/api_service_wrapper.dart`，取消注释并补充业务方法：

```dart
import '../generated/api/api.dart';

class ApiServiceWrapper {
  late DefaultApi _api;  // 取消注释

  Future<void> init() async {
    // ...
    _api = DefaultApi(_dio);  // 取消注释
  }

  // 添加业务方法
  Future<List<Novel>> searchNovels(String keyword) async {
    _ensureInitialized();
    final response = await _api.searchGet(keyword: keyword);
    return response.data ?? [];
  }
}
```

### 5. 在应用中使用

```dart
// 初始化
final apiService = ApiServiceWrapper();
await apiService.init();

// 调用 API
try {
  final novels = await apiService.searchNovels('斗破苍穹');
  print('找到 ${novels.length} 本小说');
} catch (e) {
  print('搜索失败: $e');
}
```

## 优势

✅ **类型安全**：编译时检查，减少运行时错误
✅ **自动化**：API 变更后重新生成即可同步
✅ **智能提示**：IDE 完整的代码补全
✅ **易维护**：手写代码只需要维护封装层

## 常见问题

### Q: 生成代码报错？
A: 确保后端 OpenAPI 规范格式正确，可以用在线工具验证：https://editor.swagger.io/

### Q: 生成的方法名不符合预期？
A: 修改 `openapi-config.yaml` 中的 `additionalProperties` 配置

### Q: 需要自定义请求头？
A: 在 `ApiServiceWrapper.init()` 中配置 Dio 拦截器

### Q: 后端 API 更新了？
A: 重新运行 `dart run tool/generate_api.dart`

## 配置说明

`openapi-config.yaml` 主要配置项：

```yaml
generatorName: dart-dio          # 使用 Dio 客户端
inputSpec: http://localhost:3800/openapi.json
outputDir: lib/generated/api
additionalProperties:
  pubName: novel_api             # 生成的包名
  useEnumExtension: true         # 枚举扩展
  nullableFields: true           # 字段可空
```

更多配置参考：https://openapi-generator.tech/docs/generators/dart-dio

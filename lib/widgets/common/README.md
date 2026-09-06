# 通用UI组件库

本目录包含项目中常用的可复用UI组件，旨在减少代码重复并提供一致的UI体验。

## 组件列表

### 1. async_state_widget.dart
**AsyncStateWidget<T>** - 统一的异步状态处理组件
- 自动处理 FutureBuilder/StreamBuilder 的加载、错误、空数据状态
- 支持自定义错误、加载、空数据组件
- 内置默认的错误显示和加载指示器
- 可禁用等待状态显示（适用于快速加载）

**AsyncListBuilder<T>** - 列表专用异步状态处理
- 专门处理 List<T> 类型的异步数据
- 自动显示空列表提示
- 支持自定义分隔符、内边距
- 集成了 AsyncStateWidget 的所有功能

### 2. loading_widget.dart
**LoadingWidget** - 统一的加载指示器
- 圆形进度指示器（默认）
- 线性进度指示器
- 支持自定义消息、大小、颜色
- 支持居中/非居中布局

**SmallLoadingWidget** - 小型加载指示器
- 用于按钮等小空间
- 可自定义大小和颜色

**FullScreenLoadingWidget** - 全屏加载遮罩
- 用于 Dialog 或 Overlay
- 半透明背景
- 阻止用户交互

### 3. error_widget.dart
**ErrorDisplayWidget** - 统一的错误显示组件
- 三种显示模式：standalone（独立）、card（卡片）、inline（内联）
- 支持重试回调
- 可自定义图标、消息文本
- 内置错误类型识别

**专用错误组件**：
- NetworkErrorWidget - 网络错误
- TimeoutErrorWidget - 超时错误
- DataParseErrorWidget - 数据解析错误

**ErrorDetailDialog** - 错误详情对话框
- 显示完整错误信息和堆栈跟踪
- 用于调试和错误报告

**扩展方法**：
- error.isNetworkError - 判断是否为网络错误
- error.isTimeoutError - 判断是否为超时错误
- error.isParseError - 判断是否为解析错误
- error.toErrorWidget() - 自动显示对应的错误组件

### 4. loading_states.dart
**LoadingStateWidget** - 加载状态组件（旧版，建议使用 LoadingWidget）
**ErrorStateWidget** - 错误状态组件（旧版，建议使用 ErrorDisplayWidget）
**EmptyStateWidget** - 空状态组件

### 5. 其他组件
- confirm_dialog.dart - 确认对话框
- input_dialog.dart - 输入对话框
- loading_dialog.dart - 加载对话框
- title_row.dart - 标题行布局

## 快速开始

### 导入组件

```dart
import '../widgets/common/common_widgets.dart';
```

或者单独导入：

```dart
import '../widgets/common/async_state_widget.dart';
import '../widgets/common/loading_widget.dart';
import '../widgets/common/error_widget.dart';
```

### 基础用法

#### 处理异步数据

```dart
FutureBuilder<MyData>(
  future: _loadData(),
  builder: (context, snapshot) {
    return AsyncStateWidget<MyData>(
      snapshot: snapshot,
      builder: (data) => MyDataWidget(data: data),
    );
  },
)
```

#### 显示加载状态

```dart
LoadingWidget(message: '正在加载...')
```

#### 显示错误

```dart
ErrorDisplayWidget(
  error: error,
  onRetry: () => _retry(),
)
```

## 使用示例

详细的使用示例请参考：
- **USAGE_EXAMPLES.md** - 完整的使用指南和示例
- **MIGRATION_EXAMPLE.dart** - 真实的代码迁移示例

## 迁移指南

### 1. 替换 ConnectionState 检查

**旧代码**：
```dart
if (snapshot.connectionState == ConnectionState.waiting) {
  return const Center(child: CircularProgressIndicator());
}
```

**新代码**：
```dart
AsyncStateWidget<T>(snapshot: snapshot, builder: (data) => ...)
```

### 2. 替换错误检查

**旧代码**：
```dart
if (snapshot.hasError) {
  return Center(child: Text('加载失败: ${snapshot.error}'));
}
```

**新代码**：
```dart
AsyncStateWidget<T>(
  snapshot: snapshot,
  errorBuilder: (error) => ErrorDisplayWidget(error: error),
  builder: (data) => ...,
)
```

### 3. 替换空数据检查

**旧代码**：
```dart
if (!snapshot.hasData) {
  return const Center(child: Text('暂无数据'));
}
```

**新代码**：
```dart
AsyncStateWidget<T>(
  snapshot: snapshot,
  emptyWidget: EmptyStateWidget(message: '暂无数据'),
  builder: (data) => ...,
)
```

## 设计原则

1. **简单优先**：提供合理的默认值，最小化配置
2. **一致性**：所有组件使用统一的设计语言和交互模式
3. **可扩展**：支持自定义和组合使用
4. **类型安全**：使用泛型确保类型安全
5. **性能优化**：避免不必要的重建和计算

## 最佳实践

1. **对于列表数据**：优先使用 `AsyncListBuilder` 而非 `AsyncStateWidget<List<T>>`
2. **对于快速加载**：设置 `showWaiting: false` 避免闪烁
3. **对于错误处理**：使用专用错误组件（网络、超时等）提供更好的用户体验
4. **对于调试**：使用 `ErrorDetailDialog` 查看完整错误信息
5. **对于重试**：始终提供 `onRetry` 回调，允许用户恢复操作

## 维护指南

### 添加新组件

1. 在对应文件中创建组件类
2. 添加详细的文档注释
3. 在 `common_widgets.dart` 中导出
4. 在此 README 中添加说明
5. 在 `USAGE_EXAMPLES.md` 中添加使用示例

### 修改现有组件

1. 保持向后兼容性
2. 添加可选参数而非修改现有参数
3. 更新文档注释
4. 更新使用示例

### 代码风格

- 遵循 Flutter 官方代码规范
- 使用 `final` 声明变量
- 添加详细的文档注释
- 使用命名参数提高可读性
- 保持单一职责原则

## 相关文件

- **common_widgets.dart** - 统一导出所有组件
- **USAGE_EXAMPLES.md** - 使用指南和示例
- **MIGRATION_EXAMPLE.dart** - 迁移示例代码

## 贡献指南

如果您发现需要添加新的通用组件，请按照以下步骤：

1. 在 `lib/widgets/common/` 目录创建新文件
2. 实现组件，确保符合现有设计模式
3. 添加文档注释和使用示例
4. 在 `common_widgets.dart` 中导出
5. 运行 `flutter analyze` 确保没有问题
6. 更新本 README 文档

## 更新日志

### 2026-02-03
- 添加 `AsyncStateWidget` 统一异步状态处理
- 添加 `AsyncListBuilder` 列表专用组件
- 添加 `LoadingWidget` 多种加载指示器
- 添加 `ErrorDisplayWidget` 统一错误显示
- 添加专用错误组件（网络、超时、解析）
- 添加错误详情对话框和扩展方法
- 编写完整的使用文档和迁移示例

# 通用对话框组件

本目录包含统一的对话框组件，遵循 Material Design 3 风格，提供简洁易用的 API。

## 文件列表

### 核心文件

1. **base_dialog.dart** - 基础对话框抽象类
   - 提供统一的对话框样式和行为
   - 定义标准配置和工具方法
   - 所有自定义对话框的基类

2. **confirm_dialog.dart** - 通用确认对话框
   - 标准的确认/取消对话框
   - 支持危险操作模式
   - 可自定义按钮和图标

3. **input_dialog.dart** - 通用输入对话框
   - 单行/多行输入对话框
   - 支持输入验证
   - 支持数字、多行等专用输入

4. **loading_dialog.dart** - 通用加载对话框
   - 标准加载指示器
   - 支持带进度的加载
   - 自动管理异步操作

5. **dialog_factory.dart** - 对话框工厂类
   - 统一的对话框创建接口
   - 简化对话框使用
   - 提供快捷方法

## 快速开始

### 使用 DialogFactory（推荐）

最简单的方式是通过 `DialogFactory` 类来显示对话框：

```dart
import 'package:novel_app/widgets/common/dialog_factory.dart';

// 确认对话框
final confirmed = await DialogFactory.confirm(
  context,
  title: '确认删除',
  message: '删除后无法恢复，是否继续？',
);

// 输入对话框
final input = await DialogFactory.input(
  context,
  title: '输入章节标题',
  hint: '请输入章节标题',
);

// 加载对话框
DialogFactory.loading(context, message: '处理中...');
await doSomething();
DialogFactory.dismiss(context);

// 带异步操作的加载对话框
final result = await DialogFactory.loadingWithFuture(
  context,
  future: () => fetchData(),
  message: '加载数据中...',
);
```

### 直接使用对话框类

如果需要更多自定义选项，可以直接使用具体的对话框类：

```dart
import 'package:novel_app/widgets/common/confirm_dialog.dart';

final confirmed = await ConfirmDialog.show(
  context,
  title: '确认删除',
  message: '删除后无法恢复',
  confirmText: '删除',
  cancelText: '取消',
  icon: Icons.delete,
  isDangerous: true,
);
```

## 核心 API 说明

### DialogFactory

统一对话框工厂类，提供简洁的静态方法。

#### 确认对话框

```dart
// 标准确认对话框
DialogFactory.confirm(context,
  title: '确认操作',
  message: '是否继续？',
);

// 危险操作确认（红色按钮）
DialogFactory.confirmDangerous(context,
  title: '确认删除',
  message: '此操作不可撤销',
);

// 信息确认
DialogFactory.confirmInfo(context,
  title: '提示',
  message: '是否继续操作？',
);
```

#### 输入对话框

```dart
// 单行输入
DialogFactory.input(context,
  title: '输入标题',
  hint: '请输入标题',
);

// 多行输入
DialogFactory.multilineInput(context,
  title: '输入描述',
  hint: '请输入详细描述',
  maxLines: 5,
);

// 数字输入
DialogFactory.numberInput(context,
  title: '输入数量',
  minValue: 1,
  maxValue: 100,
);
```

#### 加载对话框

```dart
// 显示/隐藏加载对话框
DialogFactory.loading(context, message: '处理中...');
await operation();
DialogFactory.dismiss(context);

// 带异步操作的加载对话框
final result = await DialogFactory.loadingWithFuture(
  context,
  future: () => fetchData(),
  message: '加载中...',
);

// 带进度的加载对话框
await DialogFactory.loadingWithProgress(
  context,
  task: (progress) async {
    for (int i = 0; i <= 100; i++) {
      progress(i / 100);
      await Future.delayed(Duration(milliseconds: 50));
    }
  },
  message: '下载中...',
);
```

#### 提示对话框

```dart
// 成功提示
DialogFactory.success(context,
  title: '成功',
  message: '操作完成',
);

// 错误提示
DialogFactory.error(context,
  title: '错误',
  message: '操作失败',
);

// 警告提示
DialogFactory.warning(context,
  title: '警告',
  message: '请注意',
);

// 信息提示
DialogFactory.info(context,
  title: '提示',
  message: '请注意',
  icon: Icons.info,
);
```

#### 底部动作面板

```dart
final selected = await DialogFactory.showActionSheet(
  context,
  items: [
    ActionSheetItem(
      label: '编辑',
      icon: Icons.edit,
      value: 'edit',
    ),
    ActionSheetItem(
      label: '删除',
      icon: Icons.delete,
      isDangerous: true,
      value: 'delete',
    ),
  ],
  cancelText: '取消',
  title: '选择操作',
);
```

### ConfirmDialog

通用确认对话框，继承自 `BaseDialog`。

```dart
await ConfirmDialog.show(
  context,
  title: '确认删除',
  message: '删除后无法恢复',
  confirmText: '删除',
  cancelText: '取消',
  icon: Icons.delete,
  isDangerous: true,
  showIconInTitle: true,
);
```

#### 参数说明

- `title` - 对话框标题（必需）
- `message` - 对话框内容（必需）
- `confirmText` - 确认按钮文本，默认"确认"
- `cancelText` - 取消按钮文本，默认"取消"
- `icon` - 对话框图标
- `confirmColor` - 确认按钮颜色
- `isDangerous` - 是否为危险操作（红色高亮）
- `showIconInTitle` - 是否在标题中显示图标
- `messageStyle` - 消息文本样式
- `textAlign` - 文本对齐方式

### InputDialog

通用输入对话框，支持单行和多行输入。

```dart
await InputDialog.show(
  context,
  title: '输入章节标题',
  hint: '请输入章节标题',
  initialValue: currentTitle,
  maxLines: 1,
  validator: (value) {
    if (value.isEmpty) return '标题不能为空';
    return null;
  },
);
```

#### 参数说明

- `title` - 对话框标题（必需）
- `hint` - 输入框提示文本
- `initialValue` - 输入框初始值
- `helperText` - 输入框帮助文本
- `maxLines` - 最大行数，默认1
- `minLines` - 最小行数
- `validator` - 输入验证函数
- `keyboardType` - 键盘类型
- `inputFormatters` - 文本输入格式
- `confirmText` - 确认按钮文本
- `cancelText` - 取消按钮文本
- `prefixIcon` - 输入框前缀图标
- `suffixIcon` - 输入框后缀图标
- `autofocus` - 是否自动聚焦
- `showCounter` - 是否显示字数统计
- `maxLength` - 最大字符数限制
- `border` - 输入框边框样式

#### 专用输入类

```dart
// 多行输入
MultilineInputDialog.show(context,
  title: '输入描述',
  maxLines: 5,
);

// 数字输入
NumberInputDialog.show(context,
  title: '输入数量',
  isDecimal: false,
  minValue: 1,
  maxValue: 100,
);
```

### LoadingDialog

通用加载对话框，支持多种进度指示器样式。

```dart
// 显示加载对话框
LoadingDialog.show(context,
  message: '处理中...',
  indicatorType: LoadingIndicatorType.circular,
);

// 隐藏加载对话框
LoadingDialog.hide(context);

// 带异步操作的加载对话框
final result = await LoadingDialog.withFuture(
  context,
  future: () => fetchData(),
  message: '加载中...',
);
```

#### 进度指示器类型

- `LoadingIndicatorType.circular` - 标准圆形进度条
- `LoadingIndicatorType.circularSmall` - 小型圆形进度条
- `LoadingIndicatorType.linear` - 线性进度条

#### 带进度的加载对话框

```dart
await ProgressLoadingDialog.withProgress(
  context,
  task: (progress) async {
    // progress 是 0.0 到 1.0 的值
    for (int i = 0; i <= 100; i++) {
      progress(i / 100);
      await Future.delayed(Duration(milliseconds: 50));
    }
  },
  message: '下载中...',
);
```

### BaseDialog

基础对话框抽象类，提供统一的样式和行为。

#### 核心方法

```dart
// 获取标准内边距
BaseDialog.standardPadding

// 获取标准间距
BaseDialog.standardSpacing
BaseDialog.smallSpacing

// 构建分隔线
buildDivider(context)

// 构建信息提示卡片
buildInfoCard(
  context: context,
  message: '提示信息',
  type: InfoCardType.info,
)

// 构建带图标的标题
buildTitleWithIcon(
  context: context,
  icon: Icons.info,
  title: '标题',
)
```

#### 自定义对话框示例

```dart
class MyCustomDialog extends BaseDialog {
  const MyCustomDialog({
    super.key,
    required super.title,
  });

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('自定义内容'),
        buildInfoCard(
          context: context,
          message: '这是一个提示',
          type: InfoCardType.info,
        ),
      ],
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('关闭'),
      ),
    ];
  }
}
```

## 设计规范

### Material Design 3

所有对话框遵循 Material Design 3 规范：

- 圆角：16px
- 阴影：8px
- 内边距：24px
- 标准间距：16px
- 小间距：8px

### 颜色使用

- **主要操作**：使用主题色 `colorScheme.primary`
- **危险操作**：使用错误色 `colorScheme.error`
- **信息提示**：使用主题色半透明背景
- **警告提示**：使用错误色半透明背景

### 动画

默认使用统一的动画配置：

- 进入动画：200ms，easeOutCubic
- 退出动画：200ms，easeInCubic
- 缩放效果：0.8 → 1.0

## 最佳实践

### 1. 优先使用 DialogFactory

对于常见场景，优先使用 `DialogFactory` 的静态方法：

```dart
// ✅ 推荐
await DialogFactory.confirm(context, title: '确认', message: '确定？');

// ❌ 不推荐（除非需要更多自定义）
await ConfirmDialog.show(context, title: '确认', message: '确定？');
```

### 2. 异步操作使用 LoadingDialog.withFuture

使用 `withFuture` 方法自动管理加载对话框：

```dart
// ✅ 推荐
final result = await DialogFactory.loadingWithFuture(
  context,
  future: () => fetchData(),
  message: '加载中...',
);

// ❌ 不推荐
DialogFactory.loading(context);
try {
  final result = await fetchData();
  DialogFactory.dismiss(context);
} catch (e) {
  DialogFactory.dismiss(context);
  rethrow;
}
```

### 3. 输入验证

使用 `validator` 参数进行输入验证：

```dart
await InputDialog.show(
  context,
  title: '输入URL',
  validator: (value) {
    if (value.isEmpty) return 'URL不能为空';
    if (!Uri.tryParse(value).hasAbsolutePath) return 'URL格式不正确';
    return null;
  },
);
```

### 4. 危险操作标识

对于删除等危险操作，使用 `isDangerous` 参数：

```dart
await ConfirmDialog.show(
  context,
  title: '确认删除',
  message: '删除后无法恢复',
  isDangerous: true,
);
```

### 5. 对话框状态管理

确保正确处理对话框的生命周期：

```dart
if (!context.mounted) return; // 检查上下文
DialogFactory.loading(context);
final result = await operation();
if (!context.mounted) return; // 再次检查
DialogFactory.dismiss(context);
```

## 迁移指南

### 从旧对话框迁移

如果你有现有的对话框实现，可以这样迁移：

#### 旧代码

```dart
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('确认'),
    content: Text('确定删除？'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('确定'),
      ),
    ],
  ),
);
```

#### 新代码

```dart
await DialogFactory.confirm(
  context,
  title: '确认',
  message: '确定删除？',
);
```

## 注意事项

1. **上下文安全**：在使用对话框前检查 `context.mounted`
2. **异步操作**：使用 `withFuture` 方法自动管理加载状态
3. **验证逻辑**：提供清晰的用户友好的验证消息
4. **国际化**：所有默认文本都应支持国际化
5. **测试**：确保对话框在不同屏幕尺寸下正常显示

## 相关文件

- `lib/widgets/common/` - 通用组件目录
- `lib/widgets/reader/` - 阅读器相关对话框
- `lib/widgets/character_input_dialog.dart` - 角色输入对话框示例

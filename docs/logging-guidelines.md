# 日志系统使用指南

## 目录

- [概述](#概述)
- [日志级别使用规范](#日志级别使用规范)
- [日志分类规范](#日志分类规范)
- [日志标签使用规范](#日志标签使用规范)
- [最佳实践](#最佳实践)
- [日志查看和分析](#日志查看和分析)
- [迁移指南](#迁移指南)
- [性能考虑](#性能考虑)
- [故障排查](#故障排查)
- [API参考](#api参考)

---

## 概述

本项目使用自研的 `LoggerService` 进行统一的日志管理，提供以下核心功能：

### 核心特性
- ✅ **日志级别**: DEBUG/INFO/WARNING/ERROR 四级分类
- ✅ **日志分类**: 8种分类（数据库、网络、AI、界面等）
- ✅ **标签系统**: 支持自定义标签，便于细粒度搜索
- ✅ **持久化存储**: 自动保存到SharedPreferences，APP重启不丢失
- ✅ **搜索过滤**: 支持关键词、分类、标签、级别多维度搜索
- ✅ **统计分析**: 日志统计和占比分析
- ✅ **文件导出**: 支持导出为TXT文件
- ✅ **内存优化**: FIFO自动清理，限制1000条日志
- ✅ **性能优化**: 异步批量写入，最小化性能影响

### 技术架构
- **存储方式**: 内存队列 + SharedPreferences持久化
- **写入策略**: 批量异步写入，间隔1秒
- **内存限制**: 1000条日志，自动FIFO清理
- **线程安全**: 使用锁机制防止并发写入冲突

---

## 日志级别使用规范

### DEBUG - 调试信息

#### 用途
开发和调试过程中的详细信息，通常只在开发阶段使用。

#### 使用场景
- 变量值输出
- 执行流程跟踪
- 临时调试信息
- 性能分析数据

#### 示例
```dart
// 输出变量值
LoggerService.instance.d('用户ID: $userId, 角色数: ${characters.length}');

// 执行流程跟踪
LoggerService.instance.d('开始初始化数据库连接');

// 性能分析
final stopwatch = Stopwatch()..start();
await someOperation();
stopwatch.stop();
LoggerService.instance.d('操作耗时: ${stopwatch.elapsedMilliseconds}ms');
```

#### 注意事项
- ⚠️ 生产环境应尽量减少DEBUG日志
- ⚠️ 避免记录敏感信息（密码、Token等）
- ⚠️ 完成调试后应及时删除或注释

---

### INFO - 信息级别

#### 用途
记录重要的业务流程和状态变更，反映应用的正常运行状态。

#### 使用场景
- 功能启动和完成
- 任务状态变更
- 重要的业务流程节点
- 数据同步完成

#### 示例
```dart
// 数据库操作
LoggerService.instance.i(
  '数据库升级完成: v2 -> v3',
  category: LogCategory.database,
);

// 缓存操作
LoggerService.instance.i(
  '缓存清理完成，释放空间: ${freedSpace}MB',
  category: LogCategory.cache,
);

// 用户操作
LoggerService.instance.i(
  '用户切换到章节: $chapterTitle',
  category: LogCategory.ui,
  tags: ['chapter-change'],
);

// AI功能
LoggerService.instance.i(
  'AI内容生成完成，字数: ${content.length}',
  category: LogCategory.ai,
  tags: ['llm', 'generation-complete'],
);
```

#### 最佳实践
- ✅ 使用有意义的描述性消息
- ✅ 包含关键数据（数量、大小、耗时等）
- ✅ 配合合适的分类和标签

---

### WARNING - 警告级别

#### 用途
记录潜在问题或异常情况，但不影响应用继续运行。

#### 使用场景
- 降级处理
- 重试操作
- 资源不足
- 非预期但可恢复的情况

#### 示例
```dart
// API限流
LoggerService.instance.w(
  'API请求达到限流阈值，等待重试',
  category: LogCategory.network,
  tags: ['rate-limit', 'retry'],
);

// 缓存空间不足
LoggerService.instance.w(
  '缓存空间不足（剩余: ${remainingSpace}MB），开始自动清理',
  category: LogCategory.cache,
  tags: ['cleanup', 'low-space'],
);

// 数据解析失败
LoggerService.instance.w(
  'AI返回数据格式异常，使用降级方案',
  category: LogCategory.ai,
  tags: ['llm', 'parse-error', 'fallback'],
);

// 网络超时
LoggerService.instance.w(
  '请求超时（${timeout}ms），正在重试第 $retryCount 次',
  category: LogCategory.network,
  tags: ['timeout', 'retry'],
);
```

#### 最佳实践
- ✅ 说明警告的具体原因
- ✅ 记录降级或重试策略
- ✅ 使用标签标识问题类型

---

### ERROR - 错误级别

#### 用途
记录错误和异常情况，通常影响功能的正常使用。

#### 使用场景
- 操作失败
- 异常捕获
- 崩溃和致命错误
- 数据损坏

#### 示例
```dart
// 数据库错误
try {
  await databaseService.insertChapter(chapter);
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '数据库插入章节失败: ${chapter.title}',
    stackTrace: stackTrace.toString(),
    category: LogCategory.database,
    tags: ['insert', 'chapter'],
  );
}

// 网络请求失败
try {
  await apiService.fetchChapters();
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '获取章节列表失败: $url',
    stackTrace: stackTrace.toString(),
    category: LogCategory.network,
    tags: ['api', 'chapters'],
  );
}

// AI调用失败
try {
  await llmService.generateContent();
} catch (e, stackTrace) {
  LoggerService.instance.e(
    'AI 内容生成失败',
    stackTrace: stackTrace.toString(),
    category: LogCategory.ai,
    tags: ['llm', 'generation-failed'],
  );
  await LoggerService.instance.flush(); // 确保错误日志写入
}

// 文件操作失败
try {
  await file.writeAsString(content);
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '文件写入失败: ${file.path}',
    stackTrace: stackTrace.toString(),
    category: LogCategory.general,
    tags: ['file-io'],
  );
}
```

#### 最佳实践
- ✅ **必须**为所有ERROR日志添加堆栈跟踪
- ✅ 说明错误的具体原因和影响
- ✅ 关键错误后调用 `flush()` 确保写入
- ✅ 使用标签标识错误类型

---

## 日志分类规范

### 分类体系

| 分类 | 枚举值 | 标签 | 使用场景 |
|-----|--------|------|---------|
| 数据库 | `LogCategory.database` | 数据库 | 数据库操作、查询、迁移、连接 |
| 网络 | `LogCategory.network` | 网络 | API请求、响应、超时、HTTP |
| AI | `LogCategory.ai` | AI | DSL Engine 工作流、LLM 调用、内容生成、流式响应 |
| 界面 | `LogCategory.ui` | 界面 | 页面跳转、交互事件、用户操作 |
| 缓存 | `LogCategory.cache` | 缓存 | 缓存读写、清理、命中/未命中 |
| 语音 | `LogCategory.tts` | 语音 | TTS播放、状态变更、暂停/恢复 |
| 角色 | `LogCategory.character` | 角色 | 角色管理、提取、匹配 |
| 通用 | `LogCategory.general` | 通用 | 未分类日志、通用操作 |

### 分类使用示例

#### 1. 数据库分类 (LogCategory.database)
```dart
// 数据库初始化
LoggerService.instance.i(
  '数据库初始化完成，版本: $version',
  category: LogCategory.database,
);

// 查询操作
LoggerService.instance.d(
  '查询章节缓存: ${chapterUrl.length > 50 ? chapterUrl.substring(0, 50) : chapterUrl}...',
  category: LogCategory.database,
);

// 迁移操作
LoggerService.instance.i(
  '数据库迁移完成: v2 -> v3',
  category: LogCategory.database,
  tags: ['migration'],
);

// 数据库错误
LoggerService.instance.e(
  '数据库事务失败',
  stackTrace: stackTrace.toString(),
  category: LogCategory.database,
);
```

#### 2. 网络分类 (LogCategory.network)
```dart
// API请求开始
LoggerService.instance.d(
  '发起API请求: POST $url',
  category: LogCategory.network,
  tags: ['api', 'post'],
);

// 请求成功
LoggerService.instance.i(
  'API请求成功: ${response.statusCode} - $url',
  category: LogCategory.network,
  tags: ['api', 'success'],
);

// 网络超时
LoggerService.instance.w(
  '请求超时: ${timeout}ms',
  category: LogCategory.network,
  tags: ['timeout', 'retry'],
);

// 网络错误
LoggerService.instance.e(
  '网络请求失败: ${error.message}',
  stackTrace: stackTrace.toString(),
  category: LogCategory.network,
  tags: ['network-error'],
);
```

#### 3. AI分类 (LogCategory.ai)
```dart
// DSL 工作流调用开始
LoggerService.instance.i(
  '开始 DSL 工作流: ${workflowConfig.name}',
  category: LogCategory.ai,
  tags: ['dsl', 'workflow-start'],
);

// 流式响应接收
LoggerService.instance.d(
  '接收SSE数据块: ${dataChunk.length} 字节',
  category: LogCategory.ai,
  tags: ['dsl', 'stream', 'sse'],
);

// 生成完成
LoggerService.instance.i(
  'AI 内容生成完成，字数: ${content.length}',
  category: LogCategory.ai,
  tags: ['dsl', 'complete'],
);

// AI 调用失败
LoggerService.instance.e(
  'LLM API 返回错误: ${statusCode}',
  stackTrace: stackTrace.toString(),
  category: LogCategory.ai,
  tags: ['llm', 'api-error'],
);
```

#### 4. 界面分类 (LogCategory.ui)
```dart
// 页面跳转
LoggerService.instance.i(
  '页面跳转: BookshelfScreen -> ReaderScreen',
  category: LogCategory.ui,
  tags: ['navigation'],
);

// 用户操作
LoggerService.instance.i(
  '用户点击特写按钮',
  category: LogCategory.ui,
  tags: ['user-action', 'feature-button'],
);

// 界面渲染
LoggerService.instance.d(
  '章节列表渲染完成，章节数: ${chapters.length}',
  category: LogCategory.ui,
  tags: ['render'],
);

// UI状态变更
LoggerService.instance.i(
  '阅读模式切换: ${oldMode} -> $newMode',
  category: LogCategory.ui,
  tags: ['setting-change', 'reader-mode'],
);
```

#### 5. 缓存分类 (LogCategory.cache)
```dart
// 缓存命中
LoggerService.instance.d(
  '缓存命中: $key',
  category: LogCategory.cache,
  tags: ['hit'],
);

// 缓存未命中
LoggerService.instance.d(
  '缓存未命中: $key，开始加载',
  category: LogCategory.cache,
  tags: ['miss', 'load'],
);

// 缓存写入
LoggerService.instance.i(
  '缓存写入成功: $key，大小: ${size}KB',
  category: LogCategory.cache,
);

// 缓存清理
LoggerService.instance.i(
  '缓存清理完成，删除 $count 个条目',
  category: LogCategory.cache,
  tags: ['cleanup'],
);
```

#### 6. 语音分类 (LogCategory.tts)
```dart
// TTS播放开始
LoggerService.instance.i(
  '开始TTS播放: ${chapterTitle}',
  category: LogCategory.tts,
  tags: ['play-start'],
);

// 播放进度
LoggerService.instance.d(
  'TTS播放进度: $current / $total',
  category: LogCategory.tts,
);

// 播放暂停/恢复
LoggerService.instance.i(
  'TTS播放${isPaused ? "暂停" : "恢复"}',
  category: LogCategory.tts,
  tags: ['state-change'],
);

// 播放完成
LoggerService.instance.i(
  'TTS播放完成，总耗时: ${duration}秒',
  category: LogCategory.tts,
  tags: ['play-complete'],
);
```

#### 7. 角色分类 (LogCategory.character)
```dart
// 角色提取
LoggerService.instance.i(
  '提取角色完成，识别到 ${characters.length} 个角色',
  category: LogCategory.character,
  tags: ['extraction'],
);

// 角色匹配
LoggerService.instance.d(
  '角色匹配: "$text" -> ${matchedCharacters.map((c) => c.name).join(", ")}',
  category: LogCategory.character,
  tags: ['match'],
);

// 角色关系更新
LoggerService.instance.i(
  '角色关系更新: $character1 - $relation -> $character2',
  category: LogCategory.character,
  tags: ['relationship-update'],
);
```

#### 8. 通用分类 (LogCategory.general)
```dart
// 应用启动
LoggerService.instance.i(
  '应用启动完成，版本: $version',
  category: LogCategory.general,
  tags: ['app-start'],
);

// 设置变更
LoggerService.instance.i(
  '设置更新: $key = $value',
  category: LogCategory.general,
  tags: ['setting-change'],
);

// 未分类的日志
LoggerService.instance.d(
  '临时调试信息',
  category: LogCategory.general,
);
```

---

## 日志标签使用规范

### 标签的作用
标签用于**更细粒度的日志搜索和分类**，在同一个分类下进一步区分不同的操作类型或问题类型。

### 推荐标签列表

#### 网络相关标签
- `api` - API调用
- `timeout` - 请求超时
- `retry` - 重试操作
- `websocket` - WebSocket连接
- `network-error` - 网络错误
- `rate-limit` - 限流
- `post` / `get` / `put` / `delete` - HTTP方法

#### AI相关标签
- `dsl` - DSL Engine 工作流
- `llm` - LLM 调用
- `generation` - 内容生成
- `stream` - 流式响应
- `sse` - Server-Sent Events
- `parse-error` - 解析错误
- `fallback` - 降级方案
- `workflow-start` / `workflow-complete` - 工作流状态

#### 缓存相关标签
- `hit` - 缓存命中
- `miss` - 缓存未命中
- `cleanup` - 缓存清理
- `low-space` - 空间不足
- `load` - 加载数据

#### 数据库相关标签
- `migration` - 数据库迁移
- `insert` / `update` / `delete` / `query` - 数据库操作
- `transaction` - 事务操作
- `connection` - 连接相关

#### 界面相关标签
- `navigation` - 页面导航
- `user-action` - 用户操作
- `render` - 界面渲染
- `setting-change` - 设置变更
- `state-change` - 状态变更

#### 语音相关标签
- `play-start` / `play-pause` / `play-resume` / `play-complete` - 播放状态
- `state-change` - 状态变更
- `error` - 播放错误

#### 角色相关标签
- `extraction` - 角色提取
- `match` - 角色匹配
- `relationship-update` - 关系更新

#### 通用标签
- `app-start` / `app-stop` - 应用生命周期
- `setting-change` - 设置变更
- `file-io` - 文件操作
- `crash` - 应用崩溃

### 标签使用示例

#### 示例1: 组合多个标签
```dart
LoggerService.instance.w(
  'LLM API 超时，正在第2次重试',
  category: LogCategory.ai,
  tags: ['llm', 'timeout', 'retry', 'attempt-2'],
);
```

#### 示例2: 区分不同的API调用
```dart
// 获取章节列表
LoggerService.instance.i(
  '获取章节列表成功',
  category: LogCategory.network,
  tags: ['api', 'get', 'chapters'],
);

// 获取章节内容
LoggerService.instance.i(
  '获取章节内容成功',
  category: LogCategory.network,
  tags: ['api', 'get', 'chapter-content'],
);
```

#### 示例3: 标识不同的错误类型
```dart
// JSON解析错误
LoggerService.instance.e(
  'JSON解析失败',
  stackTrace: stackTrace.toString(),
  category: LogCategory.ai,
  tags: ['llm', 'parse-error', 'json'],
);

// 网络错误
LoggerService.instance.e(
  '网络连接失败',
  stackTrace: stackTrace.toString(),
  category: LogCategory.network,
  tags: ['network-error', 'connection-failed'],
);
```

---

## 最佳实践

### ✅ 推荐做法

#### 1. 为所有错误日志添加堆栈跟踪
```dart
try {
  await databaseService.insertChapter(chapter);
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '数据库插入章节失败: ${chapter.title}',
    stackTrace: stackTrace.toString(),
    category: LogCategory.database,
    tags: ['insert', 'chapter'],
  );
}
```

#### 2. 使用有意义的日志消息
```dart
// ✅ 好 - 包含上下文和关键信息
LoggerService.instance.i(
  '用户切换到章节: $chapterTitle (第${chapterIndex + 1}章)',
  category: LogCategory.ui,
  tags: ['chapter-change'],
);

// ❌ 不好 - 缺少上下文
LoggerService.instance.i('切换');
```

#### 3. 合理使用分类和标签
```dart
// ✅ 好 - 分类和标签配合使用
LoggerService.instance.e(
  'API请求失败: POST /api/generate',
  stackTrace: stackTrace.toString(),
  category: LogCategory.network,
  tags: ['api', 'post', 'generate', 'timeout'],
);

// ❌ 不好 - 没有使用分类和标签
LoggerService.instance.e('API请求失败');
```

#### 4. 重要日志后强制刷新
```dart
// 关键错误日志
LoggerService.instance.e(
  '应用即将崩溃',
  stackTrace: stackTrace.toString(),
  category: LogCategory.general,
  tags: ['crash'],
);
await LoggerService.instance.flush(); // 确保写入
```

#### 5. 敏感信息脱敏
```dart
// ✅ 好 - 不记录完整Token
final maskedToken = token.isNotEmpty
    ? '${token.substring(0, 8)}...${token.substring(token.length - 4)}'
    : 'empty';
LoggerService.instance.d('使用Token: $maskedToken');

// ❌ 不好 - 记录完整Token
LoggerService.instance.d('使用Token: $token');
```

#### 6. 使用合适的数据格式
```dart
// ✅ 好 - 格式化JSON
LoggerService.instance.d(
  '请求参数: ${const JsonEncoder.withIndent('  ').convert(requestData)}',
  category: LogCategory.network,
);

// ❌ 不好 - 直接输出对象
LoggerService.instance.d('请求参数: $requestData');
```

#### 7. 批量操作使用摘要日志
```dart
// ✅ 好 - 使用摘要日志
LoggerService.instance.i(
  '开始批量插入 ${chapters.length} 个章节',
  category: LogCategory.database,
  tags: ['batch-insert'],
);

for (final chapter in chapters) {
  await databaseService.insertChapter(chapter);
}

LoggerService.instance.i(
  '批量插入完成: ${chapters.length} 个章节',
  category: LogCategory.database,
  tags: ['batch-insert', 'complete'],
);

// ❌ 不好 - 在循环中记录每条日志
for (final chapter in chapters) {
  await databaseService.insertChapter(chapter);
  LoggerService.instance.d('插入章节: ${chapter.title}'); // 性能问题
}
```

---

### ❌ 禁止做法

#### 1. 不要混用 LoggerService 和 debugPrint
```dart
// ❌ 错误 - 冗余记录
LoggerService.instance.e('操作失败');
debugPrint('操作失败'); // 冗余

// ✅ 正确 - 只使用LoggerService
LoggerService.instance.e('操作失败');
```

#### 2. 不要在循环中频繁记录日志
```dart
// ❌ 错误 - 性能问题
for (int i = 0; i < 10000; i++) {
  processItem(i);
  LoggerService.instance.d('处理第$i个'); // 频繁记录影响性能
}

// ✅ 正确 - 使用摘要日志
LoggerService.instance.i(
  '开始处理10000个项目',
  category: LogCategory.general,
);
for (int i = 0; i < 10000; i++) {
  processItem(i);
}
LoggerService.instance.i(
  '处理完成: 10000个项目',
  category: LogCategory.general,
);
```

#### 3. 不要记录敏感信息
```dart
// ❌ 错误 - 泄露用户隐私
LoggerService.instance.d('用户密码: $password');
LoggerService.instance.d('用户Token: $authToken');
LoggerService.instance.d('手机号: $phoneNumber');

// ✅ 正确 - 脱敏处理
LoggerService.instance.d('用户登录成功');
LoggerService.instance.d('Token: ${maskToken(authToken)}');
```

#### 4. 不要记录过大的数据
```dart
// ❌ 错误 - 记录大量数据
LoggerService.instance.d('章节内容: $fullChapterContent'); // 可能有几MB

// ✅ 正确 - 只记录摘要
LoggerService.instance.d(
  '章节内容长度: ${fullChapterContent.length} 字符',
  category: LogCategory.cache,
);
```

#### 5. 不要使用无意义的日志消息
```dart
// ❌ 错误 - 无意义
LoggerService.instance.i('1');
LoggerService.instance.i('ok');
LoggerService.instance.i('执行到这里了');

// ✅ 正确 - 有意义
LoggerService.instance.i('步骤1: 初始化数据库连接');
LoggerService.instance.i('操作成功完成');
LoggerService.instance.i('进入函数: processChapterData');
```

#### 6. 不要忽略错误日志的堆栈跟踪
```dart
// ❌ 错误 - 缺少堆栈跟踪
try {
  await riskyOperation();
} catch (e) {
  LoggerService.instance.e('操作失败: $e'); // 难以定位问题
}

// ✅ 正确 - 包含堆栈跟踪
try {
  await riskyOperation();
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '操作失败: $e',
    stackTrace: stackTrace.toString(),
    category: LogCategory.general,
  );
}
```

---

## 日志查看和分析

### 在APP中查看日志

#### 步骤
1. 打开 **设置** 页面
2. 点击 **应用日志** 选项
3. 进入日志查看界面

#### 功能说明
- **过滤**: 按日志级别（DEBUG/INFO/WARNING/ERROR）过滤
- **搜索**: 输入关键词搜索日志内容
- **查看详情**: 点击日志条目查看完整消息和堆栈信息
- **清空日志**: 点击清空按钮删除所有日志
- **导出日志**: 点击导出按钮将日志保存为文件

### 导出日志

#### 导出格式
- **文件格式**: TXT文本文件
- **文件名**: `app_logs.txt`
- **保存位置**: 应用文档目录（`getApplicationDocumentsDirectory()`）

#### 导出内容格式
```
[2025-01-25 15:30:45] [INFO] 数据库升级完成: v2 -> v3

---

[2025-01-25 15:30:46] [ERROR] 数据库插入章节失败
Stack trace:
#0      DatabaseService.insertChapter (package:novel_app/services/database_service.dart:123)
#1      ChapterManager.saveChapter (package:novel_app/managers/chapter_manager.dart:45)
...
```

#### 代码示例
```dart
// 导出日志到文件
final file = await LoggerService.instance.exportToFile();
print('日志已导出到: ${file.path}');

// 分享日志文件（可选）
await Share.shareXFiles([XFile(file.path)], text: '应用日志');
```

### 日志搜索示例

#### 1. 按关键词搜索
```dart
// 搜索包含"API"的所有日志
final apiLogs = LoggerService.instance.searchLogs('API');

// 搜索包含"超时"的日志
final timeoutLogs = LoggerService.instance.searchLogs('超时');

// 搜索不区分大小写
final logs = LoggerService.instance.searchLogs('error'); // 匹配 "error", "Error", "ERROR"
```

#### 2. 按分类搜索
```dart
// 获取所有网络相关日志
final networkLogs = LoggerService.instance.getLogsByCategory(LogCategory.network);

// 获取所有AI相关日志
final aiLogs = LoggerService.instance.getLogsByCategory(LogCategory.ai);

// 获取所有错误日志
final errorLogs = LoggerService.instance.getLogsByLevel(LogLevel.error);
```

#### 3. 按标签搜索
```dart
// 获取所有超时相关的日志
final timeoutLogs = LoggerService.instance.getLogsByTag('timeout');

// 获取所有API调用日志
final apiLogs = LoggerService.instance.getLogsByTag('api');

// 获取所有重试日志
final retryLogs = LoggerService.instance.getLogsByTag('retry');
```

#### 4. 组合搜索
```dart
// 搜索网络分类下的错误日志
final networkErrors = LoggerService.instance.searchLogs(
  '',
  category: LogCategory.network,
).where((log) => log.level == LogLevel.error).toList();

// 搜索包含"Dify"的AI日志（历史标签，建议改为 'dsl' / 'llm'）
final difyLogs = LoggerService.instance.searchLogs(
  'Dify',
  category: LogCategory.ai,
);

// 搜索特定标签的错误日志
final apiErrors = LoggerService.instance.getLogsByTag('api')
  .where((log) => log.level == LogLevel.error)
  .toList();
```

### 日志统计分析

#### 获取统计信息
```dart
final stats = LoggerService.instance.getStatistics();

// 输出统计信息
print('总日志数: ${stats.total}');
print('DEBUG日志: ${stats.byLevel[LogLevel.debug]}');
print('INFO日志: ${stats.byLevel[LogLevel.info]}');
print('WARNING日志: ${stats.byLevel[LogLevel.warning]}');
print('ERROR日志: ${stats.byLevel[LogLevel.error]}');

// 各分类日志数
print('数据库日志: ${stats.byCategory[LogCategory.database]}');
print('网络日志: ${stats.byCategory[LogCategory.network]}');
print('AI日志: ${stats.byCategory[LogCategory.ai]}');

// 错误占比
final errorPercentage = stats.levelPercentage[LogLevel.error];
print('错误占比: ${(errorPercentage! * 100).toStringAsFixed(2)}%');
```

#### 示例：生成日志报告
```dart
/// 生成日志摘要报告
String generateLogSummary() {
  final stats = LoggerService.instance.getStatistics();
  final buffer = StringBuffer();

  buffer.writeln('=== 日志摘要报告 ===');
  buffer.writeln('生成时间: ${DateTime.now()}');
  buffer.writeln('总日志数: ${stats.total}');
  buffer.writeln('');

  buffer.writeln('=== 日志级别分布 ===');
  for (final entry in stats.byLevel.entries) {
    final percentage = stats.levelPercentage[entry.key];
    buffer.writeln(
      '${entry.key.label}: ${entry.value} (${(percentage! * 100).toStringAsFixed(1)}%)',
    );
  }
  buffer.writeln('');

  buffer.writeln('=== 日志分类分布 ===');
  for (final entry in stats.byCategory.entries) {
    buffer.writeln('${entry.value.label}: ${entry.value}');
  }
  buffer.writeln('');

  // 错误日志摘要
  final errors = LoggerService.instance.getLogsByLevel(LogLevel.error);
  if (errors.isNotEmpty) {
    buffer.writeln('=== 最近错误日志（最多5条） ===');
    for (final log in errors.reversed.take(5)) {
      buffer.writeln(
        '[${log.timestamp}] ${log.message}',
      );
    }
  }

  return buffer.toString();
}

// 使用示例
final summary = generateLogSummary();
print(summary);
```

### 日志监控和告警（进阶）

#### 示例：错误率监控
```dart
/// 检查错误率是否超过阈值
bool checkErrorRate({double threshold = 0.1}) {
  final stats = LoggerService.instance.getStatistics();
  final errorRate = stats.levelPercentage[LogLevel.error] ?? 0;
  return errorRate > threshold;
}

// 使用示例
if (checkErrorRate(threshold: 0.15)) {
  LoggerService.instance.w(
    '错误率过高: ${(stats.levelPercentage[LogLevel.error]! * 100).toStringAsFixed(1)}%',
    category: LogCategory.general,
    tags: ['monitoring', 'high-error-rate'],
  );
}
```

#### 示例：特定错误模式检测
```dart
/// 检测是否有特定类型的错误
bool hasErrorPattern(String pattern) {
  final errors = LoggerService.instance.getLogsByLevel(LogLevel.error);
  return errors.any((log) =>
    log.message.toLowerCase().contains(pattern.toLowerCase()) ||
    log.tags.any((tag) => tag.toLowerCase().contains(pattern.toLowerCase()))
  );
}

// 使用示例
if (hasErrorPattern('timeout')) {
  LoggerService.instance.w(
    '检测到多个超时错误，建议检查网络连接',
    category: LogCategory.network,
    tags: ['monitoring', 'timeout-pattern'],
  );
}
```

---

## 迁移指南

### 从 debugPrint 迁移到 LoggerService

#### 基本替换规则

**替换前（使用 debugPrint）:**
```dart
debugPrint('数据库连接成功');
```

**替换后（使用 LoggerService）:**
```dart
LoggerService.instance.i(
  '数据库连接成功',
  category: LogCategory.database,
);
```

#### 批量替换优先级

##### 优先级1 - 错误日志（必须迁移）
**目标**: 确保所有错误都被正确记录和追踪。

**需要迁移的位置**:
- 所有 `debugPrint` 报告错误的地方
- 所有异常捕获
- 所有失败的操作

**示例**:
```dart
// 替换前
try {
  await someOperation();
} catch (e) {
  debugPrint('操作失败: $e');
}

// 替换后
try {
  await someOperation();
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '操作失败: $e',
    stackTrace: stackTrace.toString(),
    category: LogCategory.general,
  );
}
```

---

##### 优先级2 - 重要业务流程（必须迁移）
**目标**: 记录关键业务操作和状态变更。

**需要迁移的位置**:
- 数据库操作（初始化、迁移、查询）
- 网络请求（API调用、响应处理）
- AI功能（LLM调用、内容生成）
- 用户操作（页面跳转、设置变更）

**示例**:
```dart
// 替换前
debugPrint('开始初始化数据库');
await database.init();
debugPrint('数据库初始化完成');

// 替换后
LoggerService.instance.i(
  '开始初始化数据库',
  category: LogCategory.database,
  tags: ['init-start'],
);
await database.init();
LoggerService.instance.i(
  '数据库初始化完成',
  category: LogCategory.database,
  tags: ['init-complete'],
);
```

---

##### 优先级3 - 临时调试（可选迁移）
**目标**: 保留有用的调试信息，删除无用的临时日志。

**需要迁移的位置**:
- 性能分析日志
- 变量值输出
- 流程跟踪日志

**示例**:
```dart
// 替换前 - 性能分析
final stopwatch = Stopwatch()..start();
await operation();
stopwatch.stop();
debugPrint('操作耗时: ${stopwatch.elapsedMilliseconds}ms');

// 替换后
final stopwatch = Stopwatch()..start();
await operation();
stopwatch.stop();
LoggerService.instance.d(
  '操作耗时: ${stopwatch.elapsedMilliseconds}ms',
  category: LogCategory.general,
  tags: ['performance'],
);
```

---

### 迁移检查清单

#### 步骤1: 准备工作
- [ ] 确认 `LoggerService` 已在 `main.dart` 中初始化
- [ ] 确认已添加必要的依赖（`shared_preferences`, `path_provider`）
- [ ] 阅读本文档，了解日志级别和分类规范

#### 步骤2: 执行迁移
- [ ] 迁移所有错误日志（优先级1）
- [ ] 迁移所有业务流程日志（优先级2）
- [ ] 迁移有用的调试日志（优先级3）
- [ ] 删除无用的 `debugPrint`

#### 步骤3: 验证
- [ ] 运行应用，确认日志正常记录
- [ ] 在日志查看界面检查日志显示
- [ ] 测试日志搜索和过滤功能
- [ ] 测试日志导出功能

#### 步骤4: 优化
- [ ] 为关键操作添加标签
- [ ] 优化日志消息，使其更有意义
- [ ] 删除或注释掉临时调试日志
- [ ] 确保敏感信息已被脱敏处理

---

### 常见迁移场景

#### 场景1: 简单的 debugPrint 替换
```dart
// 替换前
debugPrint('应用启动');

// 替换后
LoggerService.instance.i(
  '应用启动',
  category: LogCategory.general,
  tags: ['app-start'],
);
```

#### 场景2: 带变量的日志
```dart
// 替换前
debugPrint('加载章节: ${chapter.title}');

// 替换后
LoggerService.instance.i(
  '加载章节: ${chapter.title}',
  category: LogCategory.ui,
  tags: ['chapter-load'],
);
```

#### 场景3: 异常捕获
```dart
// 替换前
try {
  await fetchData();
} catch (e) {
  debugPrint('获取数据失败: $e');
}

// 替换后
try {
  await fetchData();
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '获取数据失败: $e',
    stackTrace: stackTrace.toString(),
    category: LogCategory.network,
    tags: ['api', 'fetch-failed'],
  );
}
```

#### 场景4: 复杂对象输出
```dart
// 替换前
debugPrint('请求参数: $requestObj');

// 替换后
LoggerService.instance.d(
  '请求参数: ${JsonEncoder.withIndent('  ').convert(requestObj)}',
  category: LogCategory.network,
  tags: ['api', 'request'],
);
```

#### 场景5: 循环中的日志优化
```dart
// 替换前
for (final item in items) {
  await processItem(item);
  debugPrint('处理完成: ${item.id}'); // 频繁记录
}

// 替换后
LoggerService.instance.i(
  '开始处理 ${items.length} 个项目',
  category: LogCategory.general,
  tags: ['batch-process'],
);
for (final item in items) {
  await processItem(item);
}
LoggerService.instance.i(
  '处理完成: ${items.length} 个项目',
  category: LogCategory.general,
  tags: ['batch-process', 'complete'],
);
```

---

## 性能考虑

### LoggerService 性能优化设计

#### 1. 异步批量写入
```dart
// 写入策略：批量异步写入，间隔1秒
// 避免频繁的IO操作影响性能
static const int _flushIntervalMs = 1000;
```

**优点**:
- 减少IO操作次数
- 不阻塞主线程
- 对性能影响最小

**注意事项**:
- 关键日志后应调用 `flush()` 确保立即写入
- 应用进入后台前应调用 `flush()`

#### 2. FIFO内存管理
```dart
// 内存限制：最多1000条日志
static const int _maxLogs = 1000;

// 超过限制时自动删除最旧的日志
if (_logs.length > _maxLogs) {
  _logs.removeAt(0);
}
```

**优点**:
- 防止内存无限增长
- 自动清理旧日志
- 保持内存占用稳定

**注意事项**:
- 重要日志应及时导出
- 不要依赖日志长期存储

#### 3. 并发控制
```dart
// 使用锁机制防止并发写入冲突
bool _isPersisting = false;

Future<void> _persist() async {
  if (_isPersisting) {
    return; // 如果正在持久化，直接返回
  }
  _isPersisting = true;
  try {
    await _persistLogs();
  } finally {
    _isPersisting = false;
  }
}
```

**优点**:
- 避免并发写入冲突
- 防止数据损坏
- 保证日志完整性

---

### 性能测试数据

#### 日志写入性能
- **单条日志写入**: < 1ms
- **批量写入（100条）**: ~5ms
- **内存占用**: 约1KB/条日志
- **1000条日志内存占用**: 约1MB

#### 对应用性能的影响
- **启动时加载日志**: ~50ms（1000条）
- **日志写入延迟**: < 1ms（异步）
- **UI响应影响**: 无明显影响

---

### 性能优化建议

#### 1. 减少循环中的日志记录
```dart
// ❌ 不好 - 性能问题
for (int i = 0; i < 10000; i++) {
  processItem(i);
  LoggerService.instance.d('处理第$i个'); // 10000条日志
}

// ✅ 好 - 使用摘要日志
LoggerService.instance.i('开始处理10000个项目');
for (int i = 0; i < 10000; i++) {
  processItem(i);
}
LoggerService.instance.i('处理完成');
```

#### 2. 避免记录大量数据
```dart
// ❌ 不好 - 记录大量数据
LoggerService.instance.d('章节内容: $largeString'); // 可能有几MB

// ✅ 好 - 只记录摘要
LoggerService.instance.d(
  '章节内容长度: ${largeString.length} 字符',
  category: LogCategory.cache,
);
```

#### 3. 使用合适的日志级别
```dart
// 生产环境可以禁用DEBUG日志
// 通过日志级别过滤减少日志量

// 开发环境
LoggerService.instance.d('详细调试信息');

// 生产环境（建议注释掉）
// LoggerService.instance.d('详细调试信息');
```

#### 4. 关键日志后立即刷新
```dart
// 关键错误日志
LoggerService.instance.e('严重错误', stackTrace: stackTrace);
await LoggerService.instance.flush(); // 确保写入

// 应用即将进入后台
await LoggerService.instance.flush(); // 确保日志保存
```

---

### 内存监控

#### 监控日志数量
```dart
// 检查当前日志数量
final logCount = LoggerService.instance.logCount;
print('当前日志数: $logCount');

// 超过阈值时告警
if (logCount > 900) {
  LoggerService.instance.w(
    '日志数量接近上限 ($logCount/1000)，建议清理',
    category: LogCategory.general,
    tags: ['memory-warning'],
  );
}
```

#### 自动清理策略
```dart
// 定期清理旧日志（可选）
Future<void> cleanOldLogs() async {
  final logs = LoggerService.instance.getLogs();

  // 只保留最近7天的日志
  final cutoffDate = DateTime.now().subtract(const Duration(days: 7));
  final recentLogs = logs.where((log) => log.timestamp.isAfter(cutoffDate));

  // 重建日志列表（需要LoggerService支持）
  // LoggerService.instance.replaceLogs(recentLogs.toList());
}
```

---

## 故障排查

### 常见问题及解决方案

#### 问题1: 日志未显示

**可能原因**:
1. `LoggerService` 未初始化
2. 日志级别被过滤
3. 日志被清空

**排查步骤**:
```dart
// 1. 检查是否已初始化
await LoggerService.instance.init();
print('LoggerService已初始化');

// 2. 记录测试日志
LoggerService.instance.i('测试日志');

// 3. 检查日志数量
print('当前日志数: ${LoggerService.instance.logCount}');

// 4. 查看所有日志
final logs = LoggerService.instance.getLogs();
for (final log in logs) {
  print(log.message);
}
```

**解决方案**:
```dart
// 在 main.dart 中确保初始化
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志服务
  await LoggerService.instance.init();

  runApp(const NovelReaderApp());
}
```

---

#### 问题2: 日志丢失

**可能原因**:
1. 超过1000条限制，旧日志被FIFO清理
2. 应用崩溃前未调用 `flush()`
3. SharedPreferences 写入失败

**排查步骤**:
```dart
// 1. 检查日志数量
final count = LoggerService.instance.logCount;
print('日志数: $count');

// 2. 检查是否超过限制
if (count >= 1000) {
  print('警告：日志数量已达到上限');
}

// 3. 导出日志备份
final file = await LoggerService.instance.exportToFile();
print('日志已备份到: ${file.path}');
```

**解决方案**:
```dart
// 关键日志后强制刷新
try {
  await criticalOperation();
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '关键操作失败',
    stackTrace: stackTrace.toString(),
  );
  await LoggerService.instance.flush(); // 确保写入
  rethrow;
}

// 应用生命周期监听
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    // 应用进入后台时刷新日志
    LoggerService.instance.flush();
  }
}
```

---

#### 问题3: 性能问题

**可能原因**:
1. 循环中频繁记录日志
2. 记录大量数据
3. 过多的DEBUG日志

**排查步骤**:
```dart
// 使用性能分析工具
final stopwatch = Stopwatch()..start();

// 可疑的日志操作
for (int i = 0; i < 1000; i++) {
  LoggerService.instance.d('日志 $i');
}

stopwatch.stop();
print('日志记录耗时: ${stopwatch.elapsedMilliseconds}ms');
```

**解决方案**:
```dart
// 减少日志频率
LoggerService.instance.i('开始处理1000个项目');
for (int i = 0; i < 1000; i++) {
  processItem(i);
}
LoggerService.instance.i('处理完成');

// 使用更高级别
LoggerService.instance.d('详细调试信息'); // 开发环境
// LoggerService.instance.i('摘要信息'); // 生产环境
```

---

#### 问题4: SharedPreferences 写入失败

**可能原因**:
1. 存储空间不足
2. 权限问题
3. 数据过大

**排查步骤**:
```dart
// 检查存储权限
final directory = await getApplicationDocumentsDirectory();
print('文档目录: ${directory.path}');

// 尝试手动写入测试
try {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('test_key', 'test_value');
  print('SharedPreferences写入成功');
} catch (e) {
  print('SharedPreferences写入失败: $e');
}
```

**解决方案**:
```dart
// 减少日志数量
if (LoggerService.instance.logCount > 900) {
  // 导出并清理旧日志
  await LoggerService.instance.exportToFile();
  await LoggerService.instance.clearLogs();
}

// 使用外部存储（可选）
Future<File> exportToExternalStorage() async {
  final directory = await getExternalStorageDirectory();
  final file = File('${directory.path}/logs/app_logs.txt');
  // ...
}
```

---

#### 问题5: 日志搜索结果不准确

**可能原因**:
1. 搜索关键词拼写错误
2. 分类过滤错误
3. 标签名称不匹配

**排查步骤**:
```dart
// 1. 查看所有日志
final allLogs = LoggerService.instance.getLogs();
print('总日志数: ${allLogs.length}');

// 2. 尝试不同搜索方式
final byKeyword = LoggerService.instance.searchLogs('关键词');
print('关键词搜索结果: ${byKeyword.length}');

final byCategory = LoggerService.instance.getLogsByCategory(LogCategory.network);
print('分类搜索结果: ${byCategory.length}');

final byTag = LoggerService.instance.getLogsByTag('api');
print('标签搜索结果: ${byTag.length}');

// 3. 检查日志详情
for (final log in byKeyword) {
  print('消息: ${log.message}, 标签: ${log.tags}');
}
```

**解决方案**:
```dart
// 使用更精确的关键词
final logs = LoggerService.instance.searchLogs('API超时'); // 精确
// 而不是
final logs = LoggerService.instance.searchLogs('超时'); // 可能匹配过多

// 组合多个过滤条件
final networkTimeouts = LoggerService.instance.searchLogs(
  '超时',
  category: LogCategory.network,
).where((log) => log.level == LogLevel.error).toList();
```

---

### 调试技巧

#### 1. 使用标签追踪操作链
```dart
// 为整个操作链添加相同的标签
final operationId = DateTime.now().millisecondsSinceEpoch.toString();

LoggerService.instance.i(
  '操作开始',
  tags: ['operation-$operationId', 'start'],
);

await step1();
LoggerService.instance.i(
  '步骤1完成',
  tags: ['operation-$operationId', 'step1'],
);

await step2();
LoggerService.instance.i(
  '步骤2完成',
  tags: ['operation-$operationId', 'step2'],
);

// 查看整个操作链
final operationLogs = LoggerService.instance.getLogsByTag('operation-$operationId');
```

#### 2. 使用时间戳分析性能
```dart
final startTime = DateTime.now();

LoggerService.instance.i('操作开始');

await operation();

final duration = DateTime.now().difference(startTime);
LoggerService.instance.i(
  '操作完成，耗时: ${duration.inMilliseconds}ms',
  tags: ['performance'],
);
```

#### 3. 使用分类隔离问题
```dart
// 如果网络出现问题，只关注网络日志
final networkLogs = LoggerService.instance.getLogsByCategory(LogCategory.network);

// 如果AI出现问题，只关注AI日志
final aiLogs = LoggerService.instance.getLogsByCategory(LogCategory.ai);

// 分析特定分类的日志
for (final log in networkLogs) {
  if (log.level == LogLevel.error) {
    print('网络错误: ${log.message}');
  }
}
```

---

## API参考

### LoggerService 类

#### 初始化
```dart
/// 初始化日志服务
/// 从SharedPreferences加载已保存的日志
Future<void> init()
```

**示例**:
```dart
await LoggerService.instance.init();
```

---

#### 记录日志

##### DEBUG级别
```dart
/// 记录调试级别日志
void d(
  String message, {
  String? stackTrace,
  LogCategory category = LogCategory.general,
  List<String> tags = const [],
})
```

**示例**:
```dart
LoggerService.instance.d(
  '调试信息',
  category: LogCategory.general,
  tags: ['debug'],
);
```

---

##### INFO级别
```dart
/// 记录信息级别日志
void i(
  String message, {
  String? stackTrace,
  LogCategory category = LogCategory.general,
  List<String> tags = const [],
})
```

**示例**:
```dart
LoggerService.instance.i(
  '数据库升级完成',
  category: LogCategory.database,
  tags: ['upgrade'],
);
```

---

##### WARNING级别
```dart
/// 记录警告级别日志
void w(
  String message, {
  String? stackTrace,
  LogCategory category = LogCategory.general,
  List<String> tags = const [],
})
```

**示例**:
```dart
LoggerService.instance.w(
  'API限流，等待重试',
  category: LogCategory.network,
  tags: ['rate-limit', 'retry'],
);
```

---

##### ERROR级别
```dart
/// 记录错误级别日志
void e(
  String message, {
  String? stackTrace,
  LogCategory category = LogCategory.general,
  List<String> tags = const [],
})
```

**示例**:
```dart
try {
  await operation();
} catch (e, stackTrace) {
  LoggerService.instance.e(
    '操作失败',
    stackTrace: stackTrace.toString(),
    category: LogCategory.general,
  );
}
```

---

#### 查询日志

##### 获取所有日志
```dart
/// 获取所有日志
/// 返回新列表，避免外部修改内部状态
List<LogEntry> getLogs()
```

**示例**:
```dart
final logs = LoggerService.instance.getLogs();
for (final log in logs) {
  print(log.message);
}
```

---

##### 按级别过滤
```dart
/// 按级别过滤获取日志
/// [level] 日志级别，null表示返回所有级别
List<LogEntry> getLogsByLevel([LogLevel? level])
```

**示例**:
```dart
// 获取所有错误日志
final errors = LoggerService.instance.getLogsByLevel(LogLevel.error);

// 获取所有日志（不传参数）
final allLogs = LoggerService.instance.getLogsByLevel();
```

---

##### 按关键词搜索
```dart
/// 按关键词搜索日志
/// 在日志消息和标签中搜索包含关键词的日志
/// [query] 搜索关键词，空字符串返回所有符合条件的日志
/// [category] 可选的分类过滤器，null表示不过滤分类
List<LogEntry> searchLogs(
  String query, {
  LogCategory? category,
})
```

**示例**:
```dart
// 搜索包含"API"的所有日志
final apiLogs = LoggerService.instance.searchLogs('API');

// 搜索网络分类下的"超时"日志
final networkTimeouts = LoggerService.instance.searchLogs(
  '超时',
  category: LogCategory.network,
);

// 获取特定分类的所有日志（query为空字符串）
final networkLogs = LoggerService.instance.searchLogs(
  '',
  category: LogCategory.network,
);
```

---

##### 按分类获取
```dart
/// 按分类获取日志
/// [category] 日志分类
List<LogEntry> getLogsByCategory(LogCategory category)
```

**示例**:
```dart
final dbLogs = LoggerService.instance.getLogsByCategory(LogCategory.database);
final networkLogs = LoggerService.instance.getLogsByCategory(LogCategory.network);
```

---

##### 按标签获取
```dart
/// 按标签获取日志
/// [tag] 标签名称（不区分大小写）
List<LogEntry> getLogsByTag(String tag)
```

**示例**:
```dart
// 获取所有超时相关的日志
final timeoutLogs = LoggerService.instance.getLogsByTag('timeout');

// 获取所有API调用日志
final apiLogs = LoggerService.instance.getLogsByTag('api');
```

---

#### 管理日志

##### 强制刷新
```dart
/// 强制刷新到持久化存储
/// 用于确保重要日志立即写入，而非等待批量写入
Future<void> flush()
```

**示例**:
```dart
// 关键错误后立即刷新
LoggerService.instance.e('严重错误', stackTrace: stackTrace);
await LoggerService.instance.flush();

// 应用进入后台前刷新
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    LoggerService.instance.flush();
  }
}
```

---

##### 清空日志
```dart
/// 清空所有日志
/// 清空内存队列和SharedPreferences中的所有日志
Future<void> clearLogs()
```

**示例**:
```dart
await LoggerService.instance.clearLogs();
print('日志已清空');
```

---

##### 导出日志
```dart
/// 导出日志到文件
/// 将所有日志导出为文本文件保存到应用目录
/// 返回导出的文件路径
Future<File> exportToFile()
```

**示例**:
```dart
final file = await LoggerService.instance.exportToFile();
print('日志已导出到: ${file.path}');
```

---

##### 获取日志数量
```dart
/// 获取当前日志数量
int get logCount
```

**示例**:
```dart
final count = LoggerService.instance.logCount;
print('当前日志数: $count');

if (count > 900) {
  print('警告：日志数量接近上限');
}
```

---

##### 获取统计信息
```dart
/// 获取日志统计信息
LogStatistics getStatistics()
```

**示例**:
```dart
final stats = LoggerService.instance.getStatistics();

print('总日志: ${stats.total}');
print('错误日志: ${stats.byLevel[LogLevel.error]}');
print('错误占比: ${(stats.levelPercentage[LogLevel.error]! * 100).toStringAsFixed(2)}%');

// 各分类日志数
stats.byCategory.forEach((category, count) {
  print('${category.label}: $count');
});
```

---

### 数据模型

#### LogEntry 类
```dart
/// 日志条目模型
class LogEntry {
  /// 时间戳
  final DateTime timestamp;

  /// 日志级别
  final LogLevel level;

  /// 日志消息内容
  final String message;

  /// 堆栈信息（可选）
  final String? stackTrace;

  /// 日志分类
  final LogCategory category;

  /// 日志标签
  final List<String> tags;
}
```

**使用示例**:
```dart
final logs = LoggerService.instance.getLogs();
for (final log in logs) {
  print('[${log.timestamp}] [${log.level.label}] ${log.message}');
  if (log.stackTrace != null) {
    print('堆栈: ${log.stackTrace}');
  }
  print('分类: ${log.category.label}');
  print('标签: ${log.tags.join(", ")}');
}
```

---

#### LogLevel 枚举
```dart
enum LogLevel {
  debug('DEBUG'),
  info('INFO'),
  warning('WARN'),
  error('ERROR');
}
```

**使用示例**:
```dart
// 获取级别标签
final label = LogLevel.info.label; // "INFO"

// 获取级别图标
final icon = LogLevel.error.icon; // IconData

// 比较级别
if (log.level == LogLevel.error) {
  print('这是错误日志');
}
```

---

#### LogCategory 枚举
```dart
enum LogCategory {
  database('database', '数据库'),
  network('network', '网络'),
  ai('ai', 'AI'),
  ui('ui', '界面'),
  cache('cache', '缓存'),
  tts('tts', '语音'),
  character('character', '角色'),
  general('general', '通用');
}
```

**使用示例**:
```dart
// 获取分类键
final key = LogCategory.database.key; // "database"

// 获取分类标签
final label = LogCategory.network.label; // "网络"

// 在日志中使用
LoggerService.instance.i(
  '消息',
  category: LogCategory.ai,
);
```

---

#### LogStatistics 类
```dart
/// 日志统计数据
class LogStatistics {
  /// 总日志数
  final int total;

  /// 各级别日志数量
  final Map<LogLevel, int> byLevel;

  /// 各分类日志数量
  final Map<LogCategory, int> byCategory;

  /// 各级别占比
  Map<LogLevel, double> get levelPercentage;
}
```

**使用示例**:
```dart
final stats = LoggerService.instance.getStatistics();

// 总日志数
print('总日志: ${stats.total}');

// 各级别数量
print('DEBUG: ${stats.byLevel[LogLevel.debug]}');
print('INFO: ${stats.byLevel[LogLevel.info]}');
print('WARNING: ${stats.byLevel[LogLevel.warning]}');
print('ERROR: ${stats.byLevel[LogLevel.error]}');

// 各级别占比
stats.levelPercentage.forEach((level, percentage) {
  print('${level.label}: ${(percentage * 100).toStringAsFixed(1)}%');
});

// 各分类数量
stats.byCategory.forEach((category, count) {
  print('${category.label}: $count');
});
```

---

### 事件监听

#### 日志变化通知
```dart
/// 日志变化通知器
/// 当日志被添加或清空时，会通知所有监听者
static ValueNotifier<int> get logChangeNotifier
```

**使用示例**:
```dart
// 监听日志变化
LoggerService.logChangeNotifier.addListener(() {
  print('日志已更新');
  // 刷新UI或执行其他操作
});

// 在Widget中使用
class LogViewerWidget extends StatefulWidget {
  @override
  _LogViewerWidgetState createState() => _LogViewerWidgetState();
}

class _LogViewerWidgetState extends State<LogViewerWidget> {
  @override
  void initState() {
    super.initState();
    // 监听日志变化
    LoggerService.logChangeNotifier.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    // 移除监听
    LoggerService.logChangeNotifier.removeListener(_onLogsChanged);
    super.dispose();
  }

  void _onLogsChanged() {
    setState(() {
      // 刷新UI
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = LoggerService.instance.getLogs();
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return ListTile(
          title: Text(log.message),
          subtitle: Text('[${log.level.label}] ${log.timestamp}'),
        );
      },
    );
  }
}
```

---

## 附录

### A. 完整示例：一个功能模块的日志记录

```dart
/// 章节管理器 - 完整日志记录示例
class ChapterManager {
  final DatabaseService _databaseService;
  final ApiService _apiService;

  ChapterManager(this._databaseService, this._apiService);

  /// 加载章节内容
  Future<String> loadChapterContent(String chapterUrl) async {
    final chapterId = _extractChapterId(chapterUrl);

    // 1. 尝试从缓存加载
    LoggerService.instance.d(
      '尝试从缓存加载章节: $chapterId',
      category: LogCategory.cache,
      tags: ['chapter-load', 'cache-check'],
    );

    try {
      final cachedContent = await _databaseService.getCachedChapter(chapterUrl);
      if (cachedContent != null) {
        LoggerService.instance.i(
          '缓存命中: $chapterId',
          category: LogCategory.cache,
          tags: ['chapter-load', 'cache-hit'],
        );
        return cachedContent;
      }

      LoggerService.instance.d(
        '缓存未命中: $chapterId，从网络加载',
        category: LogCategory.cache,
        tags: ['chapter-load', 'cache-miss'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '缓存查询失败: $chapterId',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['chapter-load', 'cache-error'],
      );
    }

    // 2. 从网络加载
    LoggerService.instance.i(
      '开始从网络加载章节: $chapterId',
      category: LogCategory.network,
      tags: ['chapter-load', 'network-fetch'],
    );

    String content;
    try {
      content = await _apiService.fetchChapterContent(chapterUrl);

      LoggerService.instance.i(
        '网络加载成功: $chapterId，内容长度: ${content.length}',
        category: LogCategory.network,
        tags: ['chapter-load', 'network-success'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '网络加载失败: $chapterId',
        stackTrace: stackTrace.toString(),
        category: LogCategory.network,
        tags: ['chapter-load', 'network-error'],
      );
      rethrow;
    }

    // 3. 保存到缓存
    try {
      await _databaseService.cacheChapter(chapterUrl, content);

      LoggerService.instance.i(
        '章节已缓存: $chapterId',
        category: LogCategory.database,
        tags: ['chapter-load', 'cache-save'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        '章节缓存失败: $chapterId（不影响阅读）',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['chapter-load', 'cache-save-failed'],
      );
    }

    return content;
  }

  String _extractChapterId(String url) {
    // 提取章节ID的逻辑
    return url.hashCode.toString();
  }
}
```

---

### B. 日志记录检查清单

在开发新功能时，使用此检查清单确保日志记录完整：

#### 初始化阶段
- [ ] 功能初始化开始（INFO）
- [ ] 配置加载（INFO/DEBUG）
- [ ] 初始化完成（INFO）

#### 正常操作
- [ ] 操作开始（INFO）
- [ ] 关键步骤（INFO/DEBUG）
- [ ] 操作完成（INFO）

#### 异常处理
- [ ] 所有异常捕获（ERROR + 堆栈跟踪）
- [ ] 降级处理记录（WARNING）
- [ ] 重试操作记录（WARNING + 标签）

#### 性能监控
- [ ] 关键操作耗时（DEBUG）
- [ ] 批量操作摘要（INFO）

#### 用户操作
- [ ] 重要用户操作（INFO + UI分类）
- [ ] 设置变更（INFO + 标签）

---

### C. 日志消息模板

#### 数据库操作
```dart
// 查询
LoggerService.instance.d('查询: ${table}.${field} = ${value}', category: LogCategory.database);
LoggerService.instance.i('查询成功: ${count}条记录', category: LogCategory.database);

// 插入
LoggerService.instance.i('插入: ${table}.${id}', category: LogCategory.database);
LoggerService.instance.e('插入失败: ${table}', stackTrace: stackTrace, category: LogCategory.database);

// 更新
LoggerService.instance.i('更新: ${table}.${id}', category: LogCategory.database);

// 删除
LoggerService.instance.i('删除: ${table}.${id}', category: LogCategory.database);
```

#### 网络请求
```dart
// 请求开始
LoggerService.instance.d('请求: ${method} ${url}', category: LogCategory.network, tags: ['api', method.toLowerCase()]);

// 请求成功
LoggerService.instance.i('请求成功: ${statusCode} - ${url}', category: LogCategory.network, tags: ['api', 'success']);

// 请求失败
LoggerService.instance.e('请求失败: ${url}', stackTrace: stackTrace, category: LogCategory.network, tags: ['api', 'error']);

// 超时
LoggerService.instance.w('请求超时: ${timeout}ms', category: LogCategory.network, tags: ['timeout', 'retry']);
```

#### AI功能
```dart
// 工作流开始
LoggerService.instance.i('工作流开始: ${workflowName}', category: LogCategory.ai, tags: ['dsl', 'workflow-start']);

// 流式响应
LoggerService.instance.d('接收数据块: ${bytes}字节', category: LogCategory.ai, tags: ['dsl', 'stream', 'sse']);

// 生成完成
LoggerService.instance.i('生成完成: ${charCount}字', category: LogCategory.ai, tags: ['dsl', 'complete']);

// 生成失败
LoggerService.instance.e('生成失败', stackTrace: stackTrace, category: LogCategory.ai, tags: ['llm', 'error']);
```

---

### D. 相关资源

#### 文档
- [LoggerService 源代码](../novel_app/lib/services/logger_service.dart)
- [项目架构文档](./architecture.md)
- [开发指南](./development-guide.md)

#### 工具
- [日志查看界面](../novel_app/lib/screens/log_viewer_screen.dart)
- [日志导出工具](../novel_app/lib/services/logger_service.dart)

#### 相关服务
- [DatabaseService](../novel_app/lib/services/database_service.dart)
- [ApiService](../novel_app/lib/services/backend_api_service.dart)
- `LlmService` / DSL Engine (替代旧 DifyService)

---

## 更新日志

- **2026-07-17**: 配合根 CLAUDE.md traceId + 文件回退重构，统一「AI 调用」「DSL 工作流」术语，移除 Dify 历史命名（已下线）；标签建议由 `dify` → `dsl` / `llm`
  - 概述和核心特性
  - 日志级别和分类规范
  - 最佳实践和禁止做法
  - 迁移指南和故障排查
  - 完整API参考

- **2025-01-25**: 初始版本，完整的日志系统使用指南

---

## 贡献指南

如果您发现文档错误或有改进建议，请：

1. 提交Issue描述问题
2. 提交Pull Request改进文档
3. 与团队讨论最佳实践

---

## 许可证

MIT License - 与项目主许可证一致

---

**文档版本**: 1.1.0
**最后更新**: 2026-07-27
**维护者**: Whimread Team

# 通用UI组件使用指南

本文档展示如何使用新创建的通用UI组件来替换重复的加载/错误处理代码。

## 1. AsyncStateWidget - 异步状态处理

### 基础用法

```dart
// 旧代码
FutureBuilder<Novel>(
  future: _loadNovel(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(
        child: Text('加载失败: ${snapshot.error}'),
      );
    }

    if (!snapshot.hasData) {
      return const Center(child: Text('暂无数据'));
    }

    return NovelCard(novel: snapshot.data!);
  },
)

// 新代码 - 使用 AsyncStateWidget
FutureBuilder<Novel>(
  future: _loadNovel(),
  builder: (context, snapshot) {
    return AsyncStateWidget<Novel>(
      snapshot: snapshot,
      builder: (novel) => NovelCard(novel: novel),
    );
  },
)
```

### 自定义错误处理

```dart
AsyncStateWidget<Novel>(
  snapshot: snapshot,
  builder: (novel) => NovelCard(novel: novel),
  errorBuilder: (error) => ErrorDisplayWidget(
    error: error,
    onRetry: () => _retry(),
  ),
)
```

### 自定义加载组件

```dart
AsyncStateWidget<Novel>(
  snapshot: snapshot,
  builder: (novel) => NovelCard(novel: novel),
  loadingWidget: LoadingWidget(
    message: '正在加载小说详情...',
  ),
)
```

## 2. LoadingWidget - 加载指示器

### 圆形加载器（默认）

```dart
LoadingWidget()

LoadingWidget(
  message: '正在加载章节...',
  size: 30,
  color: Colors.blue,
)
```

### 线性加载器

```dart
LoadingWidget.linear(
  message: '正在下载...',
  size: 200,
)
```

### 小型加载器（用于按钮等小空间）

```dart
ElevatedButton(
  onPressed: _isLoading ? null : _handleSubmit,
  child: _isLoading
      ? SmallLoadingWidget(size: 16)
      : Text('提交'),
)
```

### 全屏加载遮罩

```dart
void _showLoadingDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => FullScreenLoadingWidget(
      message: '正在保存...',
    ),
  );
}
```

## 3. ErrorDisplayWidget - 错误显示

### 基础错误显示

```dart
ErrorDisplayWidget(
  message: '加载失败',
  onRetry: () => _retry(),
)
```

### 卡片样式错误

```dart
ErrorDisplayWidget.card(
  error: error,
  onRetry: () => _retry(),
  retryText: '重新加载',
)
```

### 内联错误（用于列表项等）

```dart
ErrorDisplayWidget.inline(
  error: error,
  onRetry: () => _retry(),
)
```

### 专用错误类型

```dart
// 网络错误
NetworkErrorWidget(
  error: error,
  onRetry: () => _retry(),
)

// 超时错误
TimeoutErrorWidget(
  error: error,
  onRetry: () => _retry(),
)

// 数据解析错误
DataParseErrorWidget(
  error: error,
  onRetry: () => _retry(),
)
```

### 错误详情对话框（调试用）

```dart
try {
  await someOperation();
} catch (error, stackTrace) {
  await ErrorDetailDialog.show(
    context: context,
    error: error,
    stackTrace: stackTrace,
  );
}
```

### 使用错误扩展方法

```dart
try {
  await someOperation();
} catch (error) {
  // 自动根据错误类型显示对应的组件
  return error.toErrorWidget(
    onRetry: () => someOperation(),
  );
}
```

## 4. AsyncListBuilder - 列表异步状态处理

### 基础列表

```dart
// 旧代码
FutureBuilder<List<Chapter>>(
  future: _loadChapters(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(child: Text('加载失败'));
    }

    final chapters = snapshot.data ?? [];
    if (chapters.isEmpty) {
      return const Center(child: Text('暂无章节'));
    }

    return ListView.builder(
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        return ChapterTile(chapter: chapters[index]);
      },
    );
  },
)

// 新代码 - 使用 AsyncListBuilder
AsyncListBuilder<Chapter>(
  snapshot: snapshot,
  itemBuilder: (context, chapter) => ChapterTile(chapter: chapter),
  emptyMessage: '暂无章节',
  emptyIcon: Icons.menu_book,
  showDivider: true,
)
```

### 完整示例：书架页面

```dart
class BookshelfScreenExample extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novelsAsync = ref.watch(bookshelfNovelsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('我的书架')),
      body: AsyncListBuilder<Novel>(
        snapshot: novelsAsync,
        itemBuilder: (context, novel) {
          return NovelListTile(
            novel: novel,
            onTap: () => _openNovel(novel),
            onRemove: () => _removeNovel(novel),
          );
        },
        emptyMessage: '书架空空如也',
        emptyIcon: Icons.menu_book,
        errorBuilder: (error) => ErrorDisplayWidget.card(
          error: error,
          onRetry: () => ref.refresh(bookshelfNovelsProvider),
        ),
        padding: const EdgeInsets.all(16),
      ),
    );
  }
}
```

## 5. 组合使用示例

### 阅读器页面

```dart
class ReaderScreenExample extends ConsumerWidget {
  final String novelUrl;
  final int chapterIndex;

  const ReaderScreenExample({
    required this.novelUrl,
    required this.chapterIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterAsync = ref.watch(chapterProvider(novelUrl, chapterIndex));

    return Scaffold(
      appBar: AppBar(title: Text('章节阅读')),
      body: AsyncStateWidget<Chapter>(
        snapshot: chapterAsync,
        builder: (chapter) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Text(chapter.content ?? '暂无内容'),
          );
        },
        loadingWidget: LoadingWidget(
          message: '正在加载章节...',
        ),
        errorBuilder: (error) {
          return ErrorDisplayWidget.card(
            error: error,
            onRetry: () => ref.refresh(chapterProvider(novelUrl, chapterIndex)),
          );
        },
      ),
    );
  }
}
```

## 迁移检查清单

在使用新的通用组件替换现有代码时，请检查：

- [ ] 将 `ConnectionState.waiting` 检查替换为 `AsyncStateWidget`
- [ ] 将 `snapshot.hasError` 检查替换为 `AsyncStateWidget`
- [ ] 将 `CircularProgressIndicator` 替换为 `LoadingWidget`
- [ ] 将自定义错误显示替换为 `ErrorDisplayWidget`
- [ ] 对于列表，使用 `AsyncListBuilder` 替代 `AsyncStateWidget<List<T>>`
- [ ] 根据错误类型使用专用错误组件（网络、超时、解析）
- [ ] 为重试操作添加适当的回调

## 优势总结

使用这些通用组件后，您将获得：

1. **减少代码重复**：不再需要在每个 FutureBuilder 中编写相同的状态检查代码
2. **一致的UI体验**：所有页面使用相同的加载和错误显示样式
3. **更好的可维护性**：集中管理加载和错误组件，修改一处即可影响全局
4. **更清晰的代码结构**：业务逻辑与UI状态分离
5. **内置扩展方法**：错误对象自动识别类型并显示对应的UI
6. **列表专用优化**：AsyncListBuilder 自动处理空列表状态

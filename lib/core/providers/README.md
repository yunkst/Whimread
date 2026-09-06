# Riverpod Providers

此目录包含所有 Riverpod Provider 的定义，提供统一的依赖注入和状态管理。

## 📋 目录

- [概述](#概述)
- [文件结构](#文件结构)
- [Provider 分类](#provider-分类)
- [使用指南](#使用指南)
- [最佳实践](#最佳实践)
- [测试指南](#测试指南)
- [常见问题](#常见问题)

## 概述

Riverpod 是 Flutter 的响应式状态管理和依赖注入框架。本项目使用 Riverpod 提供以下功能：

- **依赖注入**: 统一管理服务、Repository、Controller 等依赖
- **状态管理**: 管理应用的各种状态（主题、书架、搜索等）
- **生命周期管理**: 自动管理 Provider 的创建和销毁
- **类型安全**: 编译时类型检查，减少运行时错误

## 文件结构

```
lib/core/providers/
├── service_providers.dart              # 服务层 Providers（Logger, API, AI 等）
├── database_provider.dart              # 数据库和 Repository Providers
├── database_providers.dart             # 旧版数据库 Provider（兼容性保留）
├── repository_providers.dart           # Repository Providers 重新导出
├── theme_provider.dart                 # 主题管理 Provider
├── provider_defaults.dart              # 默认值配置常量
├── reader_settings_state.dart          # 阅读器设置状态
│
├── bookshelf_providers.dart            # 书架功能 Providers
├── chapter_list_providers.dart         # 章节列表 Providers
├── chapter_search_providers.dart       # 章节搜索 Providers
├── chapter_content_provider.dart       # 章节内容 Providers
├── reader_screen_providers.dart        # 阅读器页面 Providers
├── character_screen_providers.dart     # 角色管理 Providers
├── chat_scene_management_providers.dart # 聊天场景管理 Providers
│
└── README.md                           # 本文档
```

## Provider 分类

### 1. 核心服务 Providers (`service_providers.dart`)

提供应用程序的核心服务实例。

| Provider | 类型 | 描述 | keepAlive |
|---------|------|------|-----------|
| `loggerServiceProvider` | LoggerService | 日志服务，支持多级别日志和分类 | ✓ |
| `preferencesServiceProvider` | PreferencesService | SharedPreferences 封装，存储用户偏好 | ✓ |
| `apiServiceWrapperProvider` | ApiServiceWrapper | 后端 API 服务封装 | ✓ |
| `llmConfigServiceProvider` | LlmConfigService | LLM 配置管理服务 | ✓ |
| `preloadServiceProvider` | PreloadService | 章节预加载服务 | ✓ |
| `chapterLoaderProvider` | ChapterLoader | 章节加载器 | ✗ |
| `chapterActionHandlerProvider` | ChapterActionHandler | 章节操作处理器 | ✗ |
| `chapterReorderControllerProvider` | ChapterReorderController | 章节重排控制器 | ✗ |
| `sceneIllustrationServiceProvider` | SceneIllustrationService | 场景插图服务 | ✗ |
| `roleGalleryCacheServiceProvider` | RoleGalleryCacheService | 角色图集缓存 | ✓ |
| `characterAvatarSyncServiceProvider` | CharacterAvatarSyncService | 头像同步服务 | ✓ |
| `characterAvatarServiceProvider` | CharacterAvatarService | 角色头像服务 | ✓ |
| `chapterSearchServiceProvider` | ChapterSearchService | 章节搜索服务 | ✗ |

### 2. 数据库和 Repository Providers (`database_provider.dart`)

提供数据访问层的 Repository 实例。

| Provider | 类型 | 描述 |
|---------|------|------|
| `databaseServiceProvider` | DatabaseService | SQLite 数据库服务 |
| `novelRepositoryProvider` | NovelRepository | 小说数据访问 |
| `chapterRepositoryProvider` | ChapterRepository | 章节数据访问 |
| `characterRepositoryProvider` | CharacterRepository | 角色数据访问 |
| `characterRelationRepositoryProvider` | CharacterRelationRepository | 角色关系数据访问 |
| `illustrationRepositoryProvider` | IllustrationRepository | 插图数据访问 |
| `outlineRepositoryProvider` | OutlineRepository | 大纲数据访问 |
| `chatSceneRepositoryProvider` | ChatSceneRepository | 聊天场景数据访问 |
| `bookshelfRepositoryProvider` | BookshelfRepository | 书架分类数据访问 |

### 3. 主题和设置 Providers

| Provider | 文件 | 描述 |
|---------|------|------|
| `themeNotifierProvider` | theme_provider.dart | 主题状态管理 |
| `readerSettingsStateNotifierProvider` | reader_settings_state.dart | 阅读器设置管理 |

### 4. 功能页面 Providers

#### 书架功能 (`bookshelf_providers.dart`)
- `currentBookshelfIdProvider` - 当前选中的书架ID
- `bookshelfNovelsProvider` - 书架小说列表
- `preloadProgressProvider` - 预加载进度流
- `preloadProgressMapProvider` - 预加载进度映射

#### 章节列表 (`chapter_list_providers.dart`)
- `chapterListProvider` - 章节列表状态管理
- `currentNovelProvider` - 当前小说参数
- `chapterGenerationProvider` - 章节生成状态
- `generatedContentProvider` - 生成的内容
- `preloadProgressProvider` - 预加载进度

#### 角色管理 (`character_screen_providers.dart`)
- `characterImageCacheServiceProvider` - 角色图片缓存
- `characterManagementStateProvider` - 角色列表状态
- `characterEditControllerProvider` - 角色编辑控制器
- `relationshipCountCacheProvider` - 关系数量缓存
- `hasOutlineProvider` - 大纲存在检查
- `autoSaveStateProvider` - 自动保存状态
- `multiSelectModeProvider` - 多选模式状态
- `selectedCharacterIdsProvider` - 已选角色ID集合

#### 聊天场景 (`chat_scene_management_providers.dart`)
- `chatSceneRepositoryProvider` - 聊天场景 Repository
- `chatSceneManagementProvider` - 聊天场景管理状态

#### 章节搜索 (`chapter_search_providers.dart`)
- `novelParamProvider` - Novel 参数
- `chaptersListProvider` - 章节列表
- `searchQueryProvider` - 搜索查询
- `searchResultsProvider` - 搜索结果
- `searchStateProvider` - 搜索状态

#### 章节内容 (`chapter_content_provider.dart`)
- `chapterContentProvider` - 章节内容状态管理

### 5. 配置常量 (`provider_defaults.dart`)

| 常量 | 值 | 描述 |
|-----|---|------|
| `defaultBookshelfId` | 1 | 默认书架 ID（"全部小说"） |
| `defaultPageSize` | 20 | 分页每页数量 |
| `maxCacheSizeMB` | 500 | 最大缓存大小（MB） |
| `cacheCleanupThresholdMB` | 400 | 缓存清理阈值（MB） |
| `preloadConcurrency` | 3 | 预加载并发数 |

## 使用指南

### 基本使用模式

#### 1. 在 ConsumerWidget 中使用

```dart
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用 ref.watch 监听 Provider，建立响应式依赖
    final logger = ref.watch(loggerServiceProvider);
    final novelsAsync = ref.watch(bookshelfNovelsProvider);

    return novelsAsync.when(
      data: (novels) => ListView.builder(
        itemCount: novels.length,
        itemBuilder: (context, index) => NovelCard(novel: novels[index]),
      ),
      loading: () => CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  }
}
```

#### 2. 在 ConsumerStatefulWidget 中使用

```dart
class MyScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeNotifierProvider);
    return Container();
  }

  void _handleAction() {
    // 在回调中使用 ref.read，避免重建
    ref.read(themeNotifierProvider.notifier).setDarkMode();
  }
}
```

#### 3. 在回调函数中使用

```dart
onPressed: () {
  // 使用 ref.read 读取 Provider，不建立响应式依赖
  final service = ref.read(myServiceProvider);
  service.doSomething();
}
```

#### 4. 监听 Provider 变化

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  ref.listen<int>(homeTabIndexNotifierProvider, (previous, next) {
    if (next != previous) {
      // 响应 Tab 切换
      debugPrint('切换到 Tab: $next');
    }
  });

  return Scaffold(...);
}
```

### 依赖注入模式

#### Provider 依赖其他 Provider

```dart
@riverpod
ChapterLoader chapterLoader(ChapterLoaderRef ref) {
  // 使用 ref.watch 建立依赖关系
  final chapterRepository = ref.watch(chapterRepositoryProvider);
  return ChapterLoader(chapterRepository: chapterRepository);
}
```

#### 传递参数给 Provider

```dart
@riverpod
class ChapterList extends _$ChapterList {
  @override
  ChapterListState build(Novel novel) {
    // novel 是从外部传入的参数
    _initializeData();
    return const ChapterListState();
  }
}

// 使用
final chapterList = ref.watch(chapterListProvider(novel));
```

## 最佳实践

### 1. 使用 `keepAlive: true` 对于单例服务

```dart
@Riverpod(keepAlive: true)
LoggerService loggerService(LoggerServiceRef ref) {
  return LoggerService.instance;
}
```

**为什么**: 单例服务应该保持存活，避免重复创建和状态丢失。

### 2. 使用 `ref.watch` 建立依赖关系

```dart
@riverpod
MyService myService(MyServiceRef ref) {
  final db = ref.watch(databaseServiceProvider);
  return MyService(database: db);
}
```

**为什么**: 当依赖发生变化时，Provider 会自动重建。

### 3. 使用 `select` 优化重建

```dart
// 只在 count 变化时重建，而不是整个 state
final count = ref.watch(novelsProvider.select((state) => state.length));
```

**为什么**: 避免不必要的 UI 重建，提高性能。

### 4. 在 build 方法中使用 `ref.watch`

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final service = ref.watch(myServiceProvider);
  // 使用 service 构建 UI
}
```

**为什么**: `ref.watch` 建立响应式依赖，Provider 更新时自动重建 Widget。

### 5. 在回调中使用 `ref.read`

```dart
onPressed: () {
  final service = ref.read(myServiceProvider);
  service.doSomething();
}
```

**为什么**: `ref.read` 不建立依赖，避免在回调中触发不必要的重建。

### 6. 命名规范

- Provider 名称使用 camelCase
- 以 `Provider` 后缀结尾
- 例如: `loggerServiceProvider`, `novelRepositoryProvider`

### 7. 文档注释

为所有 Provider 添加详细的文档注释：

```dart
/// LoggerService Provider
///
/// 提供全局日志服务实例，用于记录应用运行时的日志信息。
///
/// **功能**:
/// - 支持多级别日志（debug, info, warning, error）
/// - 支持日志分类和标签
/// - 持久化日志到本地文件
///
/// **依赖**:
/// - 无（单例服务）
///
/// **使用示例**:
/// ```dart
/// final logger = ref.watch(loggerServiceProvider);
/// logger.info('应用已启动');
/// ```
@riverpod
LoggerService loggerService(LoggerServiceRef ref) {
  return LoggerService.instance;
}
```

## 测试指南

### 使用 ProviderContainer 测试

```dart
test('loggerServiceProvider should return LoggerService', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final logger = container.read(loggerServiceProvider);
  expect(logger, isA<LoggerService>());
});
```

### Mock Provider

```dart
testWidgets('BookshelfScreen should show novels', (tester) async {
  final mockRepo = MockNovelRepository();
  when(mockRepo.getNovels()).thenAnswer((_) async => testNovels);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        novelRepositoryProvider.overrideWithValue(mockRepo),
      ],
      child: MaterialApp(home: BookshelfScreen()),
    ),
  );

  await tester.pump();
  expect(find.text('测试小说'), findsOneWidget);
});
```

### 测试异步 Provider

```dart
test('bookshelfNovelsProvider should load novels', () async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final novelsAsync = container.read(bookshelfNovelsProvider.future);
  final novels = await novelsAsync;

  expect(novels, isNotEmpty);
});
```

## 常见问题

### Q: 为什么有些服务使用 `.instance` 访问？

**A**: 为了保持向后兼容，我们暂时保留了单例模式。在未来版本中会添加 `@Deprecated` 注解。

### Q: 如何在测试中 Mock Provider？

**A**: 使用 `ProviderScope` 的 `overrides` 参数：

```dart
ProviderScope(
  overrides: [
    myServiceProvider.overrideWithValue(mockInstance),
  ],
  child: MyApp(),
)
```

### Q: 何时使用 `ref.watch` vs `ref.read`？

**A**:
- `ref.watch` - 在 `build` 方法中使用，建立响应式依赖
- `ref.read` - 在回调函数中使用，不建立依赖

### Q: `keepAlive: true` 是什么意思？

**A**: 当没有 Widget 监听 Provider 时，Provider 实例不会被销毁。适用于单例服务。

### Q: 如何传递参数给 Provider？

**A**: 在 Provider 定义中添加参数：

```dart
@riverpod
class MyProvider extends _$MyProvider {
  @override
  Result build(MyParams params) {
    return compute(params);
  }
}

// 使用
final result = ref.watch(myProviderProvider(params));
```

### Q: 代码生成失败怎么办？

**A**: 运行以下命令：

```bash
# 清理并重新生成
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs

# 或使用 watch 模式（开发时推荐）
dart run build_runner watch --delete-conflicting-outputs
```

## 迁移进度

- [x] Service Providers
- [x] Database/Repository Providers
- [x] Theme Provider
- [x] Bookshelf Providers
- [x] Chapter List Providers
- [x] Search Screen Providers
- [x] Reader Screen Providers
- [x] Character Screen Providers
- [x] Chat Scene Providers
- [x] Chapter Search Providers
- [x] Chapter Content Provider
- [x] Reader Settings State

## 参考资料

- [Riverpod 官方文档](https://riverpod.dev/)
- [Riverpod 教程](https://riverpod.dev/docs/introduction/getting_started)
- [迁移指南](../../../docs/RIVERPOD_MIGRATION_GUIDE.md)
- [Flutter 状态管理最佳实践](https://docs.flutter.dev/data-and-backend/state-mgmt/options)

## 相关文档

- [服务层文档](../../services/README.md)
- [Repository 层文档](../../repositories/REFACTOR_PLAN.md)
- [数据库服务文档](../../services/database_service.dart)

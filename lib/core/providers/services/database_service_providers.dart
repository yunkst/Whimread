/// Database Service Providers
///
/// 此文件定义所有数据库相关服务的 Provider。
///
/// **功能**:
/// - 章节加载器
/// - 章节操作处理器
/// - 章节重排控制器
/// - 章节搜索服务
/// - 缓存搜索服务
///
/// **依赖**:
/// - database_providers.dart - 数据库服务
/// - network_service_providers.dart - 网络服务
///
/// **相关 Providers**:
/// - [ai_service_providers.dart] - AI相关 Providers
/// - [network_service_providers.dart] - 网络相关 Providers
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import '../../../services/chapter_search_service.dart';
import '../../../controllers/chapter_list/chapter_loader.dart';
import '../../../controllers/chapter_list/chapter_action_handler.dart';
import '../../../controllers/chapter_list/chapter_reorder_controller.dart';
import '../database_providers.dart';
import 'network_service_providers.dart';

part 'database_service_providers.g.dart';

/// ChapterLoader Provider
///
/// 提供章节加载器实例，负责从 API 和数据库加载章节数据。
///
/// **功能**:
/// - 从 API 获取章节列表
/// - 从数据库加载缓存章节
/// - 刷新章节列表
/// - 最后阅读位置管理
///
/// **依赖**:
/// - [apiServiceWrapperProvider] - API 服务
/// - [databaseServiceProvider] - 数据库服务
///
/// **使用示例**:
/// ```dart
/// final chapterLoader = ref.watch(chapterLoaderProvider);
/// await chapterLoader.initApi();
/// final chapters = await chapterLoader.loadChapters(novelUrl);
/// ```
///
/// **注意事项**:
/// - 不使用 `keepAlive`，每次使用时创建新实例
/// - 需要先调用 `initApi()` 初始化
/// - 自动处理缓存和刷新逻辑
@riverpod
ChapterLoader chapterLoader(Ref ref) {
  final apiService = ref.watch(apiServiceWrapperProvider);
  final chapterRepository = ref.watch(chapterRepositoryProvider);
  final novelRepository = ref.watch(novelRepositoryProvider);
  final chapterListHeadlessService = ref.watch(headlessWebViewChapterListServiceProvider);
  return ChapterLoader(
    ref: ref,
    api: apiService,
    chapterRepository: chapterRepository,
    novelRepository: novelRepository,
    chapterListHeadlessService: chapterListHeadlessService,
  );
}

/// ChapterActionHandler Provider
///
/// 提供章节操作处理器实例，处理章节的增删改查操作。
///
/// **功能**:
/// - 章节缓存状态查询
/// - 章节删除
/// - 章节重排
/// - 批量操作
///
/// **依赖**:
/// - [databaseServiceProvider] - 数据库服务
///
/// **使用示例**:
/// ```dart
/// final handler = ref.watch(chapterActionHandlerProvider);
/// final isCached = await handler.isChapterCached(chapterUrl);
/// await handler.deleteChapter(chapterUrl);
/// ```
///
/// **注意事项**:
/// - 不使用 `keepAlive`，每次使用时创建新实例
/// - 支持批量操作以提高性能
@riverpod
ChapterActionHandler chapterActionHandler(Ref ref) {
  final chapterRepository = ref.watch(chapterRepositoryProvider);
  return ChapterActionHandler(
    chapterRepository: chapterRepository,
  );
}

/// ChapterReorderController Provider
///
/// 提供章节重排控制器实例，管理章节顺序调整。
///
/// **功能**:
/// - 章节拖拽重排
/// - 保存重排结果
/// - 验证重排合法性
///
/// **依赖**:
/// - [databaseServiceProvider] - 数据库服务
///
/// **使用示例**:
/// ```dart
/// final reorderController = ref.watch(chapterReorderControllerProvider);
/// final reordered = reorderController.onReorder(
///   oldIndex: 0,
///   newIndex: 2,
///   chapters: chapters,
/// );
/// await reorderController.saveReorderedChapters(novelUrl, reordered);
/// ```
///
/// **注意事项**:
/// - 不使用 `keepAlive`，每次使用时创建新实例
/// - 保存操作会持久化到数据库
@riverpod
ChapterReorderController chapterReorderController(Ref ref) {
  return ChapterReorderController();
}

/// ChapterSearchService Provider
///
/// 提供章节搜索服务实例，支持章节内容的全文搜索。
///
/// **功能**:
/// - 章节内容搜索
/// - 搜索结果高亮
/// - 模糊搜索
///
/// **依赖**:
/// - [chapterRepositoryProvider] - 章节数据访问
///
/// **使用示例**:
/// ```dart
/// final searchService = ref.watch(chapterSearchServiceProvider);
/// final results = await searchService.searchInNovel(novelUrl, '关键词');
/// ```
///
/// **注意事项**:
/// - 不使用 `keepAlive`，每次使用时创建新实例
/// - 搜索操作是异步的
@riverpod
ChapterSearchService chapterSearchService(Ref ref) {
  final chapterRepository = ref.watch(chapterRepositoryProvider);
  return ChapterSearchService(chapterRepository: chapterRepository);
}

/// CharacterExtractionService 和 PromptTagService 已删除，相关 provider 已移除。

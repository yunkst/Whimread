// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_service_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$dioHash() => r'e29c612f910d2ebaae7bae655d0da68d54468bf2';

/// Dio Provider
///
/// 提供全局统一的 HTTP 客户端实例。
///
/// **功能**:
/// - 统一配置超时时间、连接池
/// - 添加日志拦截器
/// - 优化HTTP连接管理
///
/// **配置**:
/// - 连接超时: 10秒
/// - 接收超时: 90秒
/// - 发送超时: 30秒
/// - 最大并发连接: 20/主机
/// - 空闲超时: 60秒
///
/// **使用示例**:
/// ```dart
/// final dio = ref.watch(dioProvider);
/// final response = await dio.get('/api/endpoint');
/// ```
///
/// **注意事项**:
/// - 使用 `keepAlive: true` 确保实例不会被销毁（单例模式）
/// - 自动添加日志拦截器（调试模式）
/// - 已优化的连接池配置，避免资源耗尽
///
/// Copied from [dio].
@ProviderFor(dio)
final dioProvider = Provider<Dio>.internal(
  dio,
  name: r'dioProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$dioHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DioRef = ProviderRef<Dio>;
String _$apiServiceWrapperHash() => r'0135da35269bab301c905e5c16985c11de90b691';

/// ApiServiceWrapper Provider
///
/// 提供全局 API 服务实例，负责与后端服务器通信。
///
/// **功能**:
/// - 封装后端 API 调用
/// - 自动初始化和配置
/// - 错误处理和重试机制
/// - 支持 OpenAPI 生成的类型安全接口
///
/// **依赖**:
/// - [dioProvider] - HTTP 客户端
///
/// **使用示例**:
/// ```dart
/// // 方式1: 直接使用（已自动初始化）
/// final apiService = ref.watch(apiServiceWrapperProvider);
///
/// // 方式2: 仅获取 Future（异步场景）
/// final initFuture = ref.watch(apiServiceWrapperInitProvider);
/// await initFuture;
/// ```
///
/// **注意事项**:
/// - 使用 `keepAlive: true` 确保实例不会被销毁
/// - Provider 会自动调用 `init()`，无需手动初始化
/// - 通过依赖注入创建实例，便于测试
///
/// Copied from [apiServiceWrapper].
@ProviderFor(apiServiceWrapper)
final apiServiceWrapperProvider = Provider<ApiServiceWrapper>.internal(
  apiServiceWrapper,
  name: r'apiServiceWrapperProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$apiServiceWrapperHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ApiServiceWrapperRef = ProviderRef<ApiServiceWrapper>;
String _$apiServiceWrapperInitHash() =>
    r'050646a40f43e0fadbcc7ef4dc0a888c82a7ddd7';

/// ApiServiceWrapper 初始化 Provider
///
/// 提供 ApiServiceWrapper 的初始化 Future，用于需要等待初始化的场景。
///
/// **使用示例**:
/// ```dart
/// // 在应用启动时等待初始化
/// final initFuture = ref.watch(apiServiceWrapperInitProvider);
/// await initFuture;
/// ```
///
/// Copied from [apiServiceWrapperInit].
@ProviderFor(apiServiceWrapperInit)
final apiServiceWrapperInitProvider = FutureProvider<void>.internal(
  apiServiceWrapperInit,
  name: r'apiServiceWrapperInitProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$apiServiceWrapperInitHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ApiServiceWrapperInitRef = FutureProviderRef<void>;
String _$preloadServiceHash() => r'f8008e19770a7d08daa85df946bfa94b8a5e112c';

/// PreloadService Provider
///
/// 提供全局预加载服务实例，用于章节内容的预加载和缓存管理。
///
/// **功能**:
/// - 后台预加载章节内容
/// - 进度流式更新
/// - 并发控制
/// - 任务队列管理
///
/// **依赖**:
/// - [apiServiceWrapperProvider] - API 服务
/// - [chapterRepositoryProvider] - 章节数据访问
///
/// **使用示例**:
/// ```dart
/// final preloadService = ref.watch(preloadServiceProvider);
///
/// // 监听预加载进度
/// ref.listen(preloadProgressProvider, (previous, next) {
///   print('预加载进度: ${next.cachedChapters}/${next.totalChapters}');
/// });
///
/// // 开始预加载
/// await preloadService.enqueueTasks(
///   novelUrl: novelUrl,
///   novelTitle: novelTitle,
///   chapterUrls: chapterUrls,
///   currentIndex: currentIndex,
/// );
/// ```
///
/// **注意事项**:
/// - 使用 `keepAlive: true` 确保实例不会被销毁（单例模式）
/// - 预加载在后台异步执行
/// - 支持通过 progressStream 监听进度
///
/// Copied from [preloadService].
@ProviderFor(preloadService)
final preloadServiceProvider = Provider<PreloadService>.internal(
  preloadService,
  name: r'preloadServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$preloadServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PreloadServiceRef = ProviderRef<PreloadService>;
String _$headlessWebViewContentServiceHash() =>
    r'a9d7bd3e61f61370fc731bf3303f7af9a222c0b8';

/// SceneIllustrationService 和 SceneIllustrationCacheService 已删除，相关 provider 已移除。
/// HeadlessWebViewContentService Provider
///
/// 提供无头 WebView 内容获取服务实例。
/// 当域名有 AI Agent 生成的 `chapter_content_js` 脚本时，
/// 使用 HeadlessInAppWebView 直接加载页面并执行脚本获取内容。
///
/// **功能**:
/// - 绕过 API 直接获取章节内容
/// - 自动回退：无脚本或失败时返回 null
/// - 脚本健康度追踪：连续失败 3 次自动标记 unverified
///
/// **依赖**:
/// - [siteScriptRepositoryProvider] - 站点脚本查询
///
/// **使用示例**:
/// ```dart
/// final headlessService = ref.watch(headlessWebViewContentServiceProvider);
/// final result = await headlessService.fetchContent(chapterUrl);
/// if (result != null) {
///   // 使用 result.content
/// } else {
///   // 回退到 API
/// }
/// ```
///
/// Copied from [headlessWebViewContentService].
@ProviderFor(headlessWebViewContentService)
final headlessWebViewContentServiceProvider =
    Provider<HeadlessWebViewContentService>.internal(
  headlessWebViewContentService,
  name: r'headlessWebViewContentServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$headlessWebViewContentServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HeadlessWebViewContentServiceRef
    = ProviderRef<HeadlessWebViewContentService>;
String _$headlessWebViewChapterListServiceHash() =>
    r'c0c666e0516358c3e4254c8eaa78a7ad2e3301f6';

/// HeadlessWebViewChapterListService Provider
///
/// 提供无头 WebView 章节列表获取服务实例。该服务**自管一个独立的
/// HeadlessInAppWebView 实例**，与 HeadlessWebViewPool（Agent 场景）和
/// HeadlessWebViewContentService（章节内容）各自隔离，避免章节列表加载时
/// URL 被其它场景覆盖。
///
/// 当域名有 AI Agent 生成的 `chapter_list_js` 脚本时，
/// 使用 HeadlessInAppWebView 直接加载页面并执行脚本获取章节列表。
///
/// **功能**:
/// - 绕过 API 直接获取章节列表
/// - 无脚本时返回 FetchChapterListResult.noScript()
/// - 页面加载失败时返回 FetchChapterListResult.loadFailed()
/// - 脚本健康度追踪：连续失败 3 次自动标记 unverified
///
/// **依赖**:
/// - [siteScriptRepositoryProvider] - 站点脚本查询
///
/// Copied from [headlessWebViewChapterListService].
@ProviderFor(headlessWebViewChapterListService)
final headlessWebViewChapterListServiceProvider =
    Provider<HeadlessWebViewChapterListService>.internal(
  headlessWebViewChapterListService,
  name: r'headlessWebViewChapterListServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$headlessWebViewChapterListServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HeadlessWebViewChapterListServiceRef
    = ProviderRef<HeadlessWebViewChapterListService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'core_service_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$loggerServiceHash() => r'f7f42a5bf125c4aefb0d28f78e9ff7824ff70838';

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
/// class MyWidget extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     final logger = ref.watch(loggerServiceProvider);
///     logger.info('Widget 已构建');
///     return Container();
///   }
/// }
/// ```
///
/// **注意事项**:
/// - 使用 `LoggerService.instance` 单例模式
/// - 日志文件位于应用文档目录
/// - 支持异步日志写入
///
/// Copied from [loggerService].
@ProviderFor(loggerService)
final loggerServiceProvider = AutoDisposeProvider<LoggerService>.internal(
  loggerService,
  name: r'loggerServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$loggerServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LoggerServiceRef = AutoDisposeProviderRef<LoggerService>;
String _$llmLoggerHash() => r'7db4b6f0e55537fdbe94f184f9f89070e090bae0';

/// LlmLogger Provider
///
/// 提供全局 LLM 调用日志服务实例，记录前端所有 LLM 请求/响应。
///
/// **功能**:
/// - JSONL 文件落盘（按天分文件，7 天自动清理）
/// - 内存缓存最近 200 条记录
/// - 查询接口：getRecent / getById / clear / getTotalSize
/// - 通过 [LlmLogger.changeNotifier] 推送变化通知
///
/// **依赖**:
/// - 需在 `main.dart` 启动时调用 `LlmLogger.instance.initialize()`
///
/// Copied from [llmLogger].
@ProviderFor(llmLogger)
final llmLoggerProvider = AutoDisposeProvider<LlmLogger>.internal(
  llmLogger,
  name: r'llmLoggerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$llmLoggerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LlmLoggerRef = AutoDisposeProviderRef<LlmLogger>;
String _$preferencesServiceHash() =>
    r'082811fb7cecf997dd4fe3f88aa802ee93900402';

/// PreferencesService Provider
///
/// 提供全局 SharedPreferences 服务实例，用于存储用户偏好设置。
///
/// **功能**:
/// - 持久化键值对存储
/// - 支持多种数据类型（String、int、bool、double、List等）
/// - 线程安全访问
///
/// **依赖**:
/// - 无（单例服务）
///
/// **使用示例**:
/// ```dart
/// final prefs = ref.watch(preferencesServiceProvider);
/// await prefs.setString('theme_mode', 'dark');
/// final themeMode = await prefs.getString('theme_mode');
/// ```
///
/// **注意事项**:
/// - 使用 `PreferencesService.instance` 单例模式
/// - 所有操作都是异步的
/// - 数据存储在本地 SharedPreferences
///
/// Copied from [preferencesService].
@ProviderFor(preferencesService)
final preferencesServiceProvider =
    AutoDisposeProvider<PreferencesService>.internal(
  preferencesService,
  name: r'preferencesServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$preferencesServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PreferencesServiceRef = AutoDisposeProviderRef<PreferencesService>;
String _$backupServiceHash() => r'ca2b99f7f26dceac6912129ba0d015c1f34cdbcc';

/// BackupService Provider
///
/// 提供数据库备份服务实例，用于备份和恢复数据库。
///
/// **功能**:
/// - 数据库文件获取
/// - 上传备份到服务器
/// - 备份时间记录
///
/// **依赖**:
/// - 无（单例服务）
///
/// **使用示例**:
/// ```dart
/// final backupService = ref.watch(backupServiceProvider);
/// final dbFile = await backupService.getDatabaseFile();
/// await backupService.uploadBackup(dbFile: dbFile);
/// ```
///
/// **注意事项**:
/// - 使用 `BackupService()` 单例模式
/// - 上传操作需要网络连接
/// - 备份文件存储在服务器
///
/// Copied from [backupService].
@ProviderFor(backupService)
final backupServiceProvider = AutoDisposeProvider<BackupService>.internal(
  backupService,
  name: r'backupServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$backupServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BackupServiceRef = AutoDisposeProviderRef<BackupService>;
String _$logReporterServiceHash() =>
    r'4fb0243ec15e652fa427935b524afe4494e6369c';

/// LogReporterService Provider
///
/// 提供全局日志上报服务实例，用于将本地日志批量上报到后端。
///
/// **功能**:
/// - 批量上报：累积 20 条或 30 秒后自动触发
/// - 级别过滤：可配置最低上报级别（默认 WARNING）
/// - 退避策略：连续失败 3 次后进入退避模式（间隔翻倍，最大 5 分钟）
/// - 配置持久化：开关与级别存在 SharedPreferences
///
/// **依赖**:
/// - 无（单例服务）
///
/// **使用示例**:
/// ```dart
/// final reporter = ref.read(logReporterServiceProvider);
/// await reporter.flush(); // 立即上报
/// ```
///
/// Copied from [logReporterService].
@ProviderFor(logReporterService)
final logReporterServiceProvider =
    AutoDisposeProvider<LogReporterService>.internal(
  logReporterService,
  name: r'logReporterServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$logReporterServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LogReporterServiceRef = AutoDisposeProviderRef<LogReporterService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

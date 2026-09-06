/// Core Service Providers
///
/// 此文件定义核心基础服务的 Provider。
///
/// **功能**:
/// - 日志服务
/// - 偏好设置服务
///
/// **依赖**:
/// - 无（最底层服务）
///
/// **相关 Providers**:
/// - [ai_service_providers.dart] - AI相关 Providers
/// - [network_service_providers.dart] - 网络相关 Providers
/// - [database_service_providers.dart] - 数据库相关 Providers
/// - [cache_service_providers.dart] - 缓存相关 Providers
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import '../../../services/logger_service.dart';
import '../../../services/llm_logger/llm_logger.dart';
import '../../../services/log_reporter_service.dart';
import '../../../services/preferences_service.dart';
import '../../../services/backup_service.dart';

part 'core_service_providers.g.dart';

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
@riverpod
LoggerService loggerService(Ref ref) {
  return LoggerService.instance;
}

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
@riverpod
LlmLogger llmLogger(Ref ref) {
  return LlmLogger.instance;
}

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
@riverpod
PreferencesService preferencesService(Ref ref) {
  return PreferencesService.instance;
}

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
@riverpod
BackupService backupService(Ref ref) {
  return BackupService();
}

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
@riverpod
LogReporterService logReporterService(Ref ref) {
  return LogReporterService.instance;
}

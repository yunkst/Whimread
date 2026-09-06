import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'preferences_service.dart';

/// 日志级别
enum LogLevel {
  /// 调试信息
  debug('DEBUG'),

  /// 一般信息
  info('INFO'),

  /// 警告信息
  warning('WARN'),

  /// 错误信息
  error('ERROR');

  final String label;

  const LogLevel(this.label);

  /// 获取对应的图标
  IconData get icon {
    switch (this) {
      case LogLevel.debug:
        return Icons.bug_report_outlined;
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warning:
        return Icons.warning_outlined;
      case LogLevel.error:
        return Icons.error_outline;
    }
  }
}

/// 日志分类
enum LogCategory {
  /// 数据库操作
  database('database', '数据库'),

  /// 网络请求
  network('network', '网络'),

  /// AI功能
  ai('ai', 'AI'),

  /// 界面交互
  ui('ui', '界面'),

  /// 缓存操作
  cache('cache', '缓存'),

  /// 角色管理
  character('character', '角色'),

  /// 数据备份
  backup('backup', '备份'),

  /// 通用（默认）
  general('general', '通用');

  final String key;
  final String label;

  const LogCategory(this.key, this.label);
}

/// 日志统计数据
class LogStatistics {
  /// 总日志数
  final int total;

  /// 各级别日志数量
  final Map<LogLevel, int> byLevel;

  /// 各分类日志数量
  final Map<LogCategory, int> byCategory;

  /// 各级别占比
  Map<LogLevel, double> get levelPercentage {
    if (total == 0) return {};
    return byLevel.map((level, count) => MapEntry(level, count / total));
  }

  const LogStatistics({
    required this.total,
    required this.byLevel,
    required this.byCategory,
  });
}

/// 日志条目模型
///
/// 用于存储单条日志记录，包含时间戳、级别、消息和堆栈信息。
/// [traceId] 为请求级追踪 ID，通过 [LoggerService.withTraceId] 注入的 Zone
/// 自动附着，用于将同一逻辑请求跨多个异步操作的日志关联起来。
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

  /// 请求级追踪 ID（可选），通过 [LoggerService.withTraceId] 自动附着
  final String? traceId;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.stackTrace,
    this.category = LogCategory.general,
    this.tags = const [],
    this.traceId,
  });

  /// 转换为Map用于序列化
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'level': level.index,
      'message': message,
      'stackTrace': stackTrace,
      'category': category.index,
      'tags': tags,
      if (traceId != null) 'traceId': traceId,
    };
  }

  /// 从Map反序列化创建LogEntry
  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      level: LogLevel.values[map['level'] as int],
      message: map['message'] as String,
      stackTrace: map['stackTrace'] as String?,
      // 向后兼容：如果没有category字段，默认为general
      category: map.containsKey('category')
          ? LogCategory.values[map['category'] as int]
          : LogCategory.general,
      // 向后兼容：如果没有tags字段，默认为空数组
      tags: map.containsKey('tags')
          ? (map['tags'] as List<dynamic>).cast<String>()
          : const [],
      // 向后兼容：旧日志无 traceId
      traceId: map['traceId'] as String?,
    );
  }

  @override
  String toString() {
    return 'LogEntry(timestamp: $timestamp, level: ${level.label}, message: $message)';
  }
}

/// 日志服务
///
/// 负责管理应用日志的收集、存储和持久化。
/// 使用内存队列存储最新1000条日志，超过限制时自动清理旧日志。
/// 所有日志会在添加时自动持久化：SharedPreferences 优先，失败时回退到文件存储。
/// 使用批量写入优化，减少频繁IO操作。
///
/// ## traceId 追踪
///
/// 通过 [withTraceId] 在 Zone 中注入请求级追踪 ID，该 Zone 内所有日志
/// 自动携带此 ID，用于将同一逻辑请求跨异步操作的日志关联起来。
///
/// ## 使用方式：
/// ```dart
/// // 初始化（在main.dart中调用一次）
/// await LoggerService.instance.init();
///
/// // 记录日志
/// LoggerService.instance.d('调试信息');
/// LoggerService.instance.i('数据库升级完成');
/// LoggerService.instance.w('警告信息');
/// LoggerService.instance.e('错误信息', stackTrace);
///
/// // 重要日志后强制刷新
/// LoggerService.instance.e('严重错误', stackTrace: stackTrace);
/// await LoggerService.instance.flush();
///
/// // traceId 追踪——Zone 内所有日志自动附着 request-xxx
/// await LoggerService.withTraceId('request-xxx', () async {
///   LoggerService.instance.i('开始处理');   // traceId=request-xxx
///   await someAsyncWork();
///   LoggerService.instance.i('处理完成');   // traceId=request-xxx
/// });
///
/// // 获取所有日志
/// final logs = LoggerService.instance.getLogs();
///
/// // 按级别过滤
/// final errors = LoggerService.instance.getLogsByLevel(LogLevel.error);
///
/// // 搜索日志
/// final results = LoggerService.instance.searchLogs('API', category: LogCategory.network);
///
/// // 按分类获取
/// final dbLogs = LoggerService.instance.getLogsByCategory(LogCategory.database);
///
/// // 按标签获取
/// final apiLogs = LoggerService.instance.getLogsByTag('api');
///
/// // 获取统计信息
/// final stats = LoggerService.instance.getStatistics();
/// print('总日志: ${stats.total}');
/// print('错误占比: ${stats.levelPercentage[LogLevel.error]}');
///
/// // 清空日志
/// await LoggerService.instance.clearLogs();
///
/// // 导出日志文件
/// final file = await LoggerService.instance.exportToFile();
/// ```
class LoggerService {
  // ========== 单例模式 ==========
  static LoggerService? _instance;
  static LoggerService get instance {
    _instance ??= LoggerService._internal();
    return _instance!;
  }

  LoggerService._internal();

  // ========== 测试辅助方法 ==========
  /// 重置单例（仅用于测试）
  ///
  /// WARNING: 此方法仅用于单元测试，生产代码不应调用。
  static void resetForTesting() {
    // 取消尚未 fire 的延迟持久化 timer，避免跨测试残留的 pending timer
    // 触发 widget test 的 _verifyInvariants（timersPending 断言）。
    _instance?._pendingFlushTimer?.cancel();
    // 创建新的 ValueNotifier 以确保测试间状态隔离
    _logChangeNotifier = ValueNotifier<int>(0);
    _instance = null;
  }

  /// 持久化是否健康（供测试和调试面板检查）。
  ///
  /// 返回 false 表示 SP 和文件两端都写入失败，日志可能丢失。
  @visibleForTesting
  static bool get isPersistHealthyForTest => instance._lastPersistSuccess;

  /// 自启动以来的持久化失败次数（供测试和调试面板检查）。
  @visibleForTesting
  static int get persistErrorCountForTest => instance._persistErrorCount;

  // ========== 常量定义 ==========
  /// 最大日志条数
  static const int _maxLogs = 1000;

  /// SharedPreferences存储键
  static const String _prefsKey = 'app_logs';

  /// 导出文件名
  static const String _exportFileName = 'app_logs.txt';

  /// 文件回退存储文件名（SP 写入失败时的回退方案）
  static const String _fallbackFileName = 'app_logs_fallback.json';

  /// traceId 在 Zone 中的键
  static const Symbol _traceIdKey = #_logTraceId;

  // ========== 状态管理 ==========
  /// 内存日志队列
  final List<LogEntry> _logs = [];

  /// 是否已初始化
  bool _initialized = false;

  /// 持久化锁，防止并发写入
  bool _isPersisting = false;

  /// 待持久化标记
  bool _pendingPersist = false;

  /// 批量写入间隔（毫秒）
  static const int _flushIntervalMs = 1000;

  /// 上次持久化时间
  DateTime? _lastPersistTime;

  /// 兜底延迟持久化的 timer（_schedulePersist 在距上次写入 < 间隔时安排）。
  /// 保存引用以便测试时取消，避免跨测试残留的 pending timer 触发 widget test
  /// 的 _verifyInvariants（timersPending 断言）。
  Timer? _pendingFlushTimer;

  /// 日志变化通知器
  ///
  /// 当日志被添加或清空时，会通知所有监听者。
  /// LogViewerScreen 可以通过监听此 ValueNotifier 来自动更新UI。
  static ValueNotifier<int> _logChangeNotifier = ValueNotifier<int>(0);

  /// 获取日志变化通知器
  static ValueNotifier<int> get logChangeNotifier => _logChangeNotifier;

  /// 最近一次持久化是否成功（供测试和调试面板检查）
  bool _lastPersistSuccess = true;

  /// 累计持久化失败次数（自启动以来）
  int _persistErrorCount = 0;

  // ========== traceId Zone 传播 ==========

  /// 读取当前 Zone 中注入的 traceId。
  ///
  /// 通过 [withTraceId] 创建的 Zone 会自动设置此值；
  /// 未在 withTraceId 内调用时返回 null（对现有代码完全透明）。
  static String? get currentTraceId {
    try {
      return Zone.current[_traceIdKey] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 在 [action] 执行期间注入 [traceId]，该 Zone 内所有日志自动携带此 ID。
  ///
  /// 用于将同一逻辑请求（如一次 LLM 调用）跨多个异步操作的日志关联起来。
  ///
  /// 示例：
  /// ```dart
  /// await LoggerService.withTraceId('llm-req-001', () async {
  ///   LoggerService.instance.i('开始请求');  // 自动带 traceId=llm-req-001
  ///   await doWork();
  ///   LoggerService.instance.i('请求完成');  // 自动带 traceId=llm-req-001
  /// });
  /// ```
  static Future<T> withTraceId<T>(
    String traceId,
    Future<T> Function() action,
  ) {
    return runZoned(action, zoneValues: {_traceIdKey: traceId});
  }

  // ========== 公开方法 ==========

  /// 初始化日志服务
  ///
  /// 从SharedPreferences加载已保存的日志到内存队列。
  /// 应在应用启动时调用一次（main.dart中）。
  Future<void> init() async {
    if (_initialized) return;

    await _loadLogs();
    _initialized = true;
  }

  /// 记录调试级别日志
  ///
  /// 注意：release 模式下直接返回，不写入队列，避免高频调试日志在 release 包
  /// 占用内存与 SharedPreferences 存储。
  void d(String message,
      {String? stackTrace,
      LogCategory category = LogCategory.general,
      List<String> tags = const []}) {
    if (kReleaseMode) return;
    _log(message, LogLevel.debug, stackTrace, category, tags);
  }

  /// 记录信息级别日志
  void i(String message,
      {String? stackTrace,
      LogCategory category = LogCategory.general,
      List<String> tags = const []}) {
    _log(message, LogLevel.info, stackTrace, category, tags);
  }

  /// 记录警告级别日志
  void w(String message,
      {String? stackTrace,
      LogCategory category = LogCategory.general,
      List<String> tags = const []}) {
    _log(message, LogLevel.warning, stackTrace, category, tags);
  }

  /// 记录错误级别日志
  void e(String message,
      {String? stackTrace,
      LogCategory category = LogCategory.general,
      List<String> tags = const []}) {
    _log(message, LogLevel.error, stackTrace, category, tags);
  }

  /// 强制刷新到持久化存储
  ///
  /// 用于确保重要日志立即写入，而非等待批量写入。
  /// 使用场景：
  /// - 记录错误日志后
  /// - 应用即将进入后台时
  /// - 应用即将退出时
  Future<void> flush() async {
    if (_pendingPersist) {
      await _persistChain();
    }
  }

  /// 记录日志（内部方法）
  ///
  /// 添加一条新日志到内存队列，如果超过最大限制则删除最旧的日志（FIFO）。
  /// 自动从当前 Zone 读取 traceId（通过 [withTraceId] 注入），无需调用方显式传递。
  /// 添加后会触发持久化、状态通知和上报服务回调。
  void _log(String message, LogLevel level,
      [String? stackTrace,
      LogCategory category = LogCategory.general,
      List<String> tags = const []]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      stackTrace: stackTrace,
      category: category,
      tags: tags,
      traceId: currentTraceId, // 从 Zone 自动读取，无则 null
    );

    _logs.add(entry);

    // FIFO：如果超过最大限制，删除最旧的日志
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // 通知监听器日志已更新
    logChangeNotifier.value++;

    // 触发持久化（使用锁机制防止并发）
    _schedulePersist();

    // 通知上报服务（静默调用，由 LogReporterService 自行做级别过滤）
    _notifyReporter(entry);
  }

  /// 通知日志上报服务
  ///
  /// 通过动态 import 避免循环依赖：
  /// logger_service → log_reporter_service（单向）
  void _notifyReporter(LogEntry entry) {
    try {
      // 延迟加载避免循环引用
      // ignore: invalid_use_of_visible_for_testing_member
      _reporterCallback?.call(entry);
    } catch (_) {
      // 静默忽略上报服务异常
    }
  }

  /// 静态回调钩子：上报服务注册到 LoggerService
  ///
  /// 调用 LogReporterService.instance.onLogAdded。
  /// 设为静态字段以避免 logger_service.dart 顶部 import log_reporter_service.dart 形成循环依赖。
  static void Function(LogEntry entry)? _reporterCallback;

  /// 注册上报回调（仅供 LogReporterService 内部调用）
  static void registerReporter(void Function(LogEntry entry) callback) {
    _reporterCallback = callback;
  }

  /// 注销上报回调（仅供 LogReporterService 内部 dispose 调用）
  static void unregisterReporter() {
    _reporterCallback = null;
  }

  /// 获取指定级别及以上的日志（供上报服务初始化时补齐已累积的日志）
  List<LogEntry> getLogsAboveLevel(LogLevel level) {
    return _logs.where((log) => log.level.index >= level.index).toList();
  }

  /// 删除指定时间之前的日志
  Future<void> removeLogsBefore(DateTime cutoff) async {
    _logs.removeWhere((log) => log.timestamp.isBefore(cutoff));
    await _persistLogs();
    logChangeNotifier.value++;
  }

  /// 调度持久化任务
  void _schedulePersist() {
    _pendingPersist = true;

    // 批量写入优化：距离上次写入超过指定间隔才执行
    final now = DateTime.now();
    if (_lastPersistTime == null ||
        now.difference(_lastPersistTime!).inMilliseconds >= _flushIntervalMs) {
      _persistChain();
    } else {
      // 兜底：仅在内存置 _pendingPersist 但未立即写的分支,
      // 安排一个延后的 _persistChain,确保最后一批日志不卡在内存
      // (避免后续无新日志触发 _schedulePersist 时,当前待写日志被遗忘)。
      // 保存 timer 引用以便 resetForTesting 取消，避免跨测试残留的 pending timer
      // 触发 widget test 的 _verifyInvariants（timersPending）。
      _pendingFlushTimer?.cancel();
      _pendingFlushTimer = Timer(
        Duration(milliseconds: _flushIntervalMs),
        () {
          _pendingFlushTimer = null;
          _persistChain();
        },
      );
    }
  }

  /// 持久化链（带互斥锁，确保不会并发执行）
  Future<void> _persistChain() async {
    if (_isPersisting) return;

    _isPersisting = true;
    try {
      while (_pendingPersist) {
        _pendingPersist = false;
        _lastPersistTime = DateTime.now();
        await _persistLogs();
      }
    } finally {
      _isPersisting = false;
    }
  }

  /// 获取所有日志
  ///
  /// 返回内存队列中的所有日志条目列表。
  /// 返回的是新列表，避免外部修改内部状态。
  List<LogEntry> getLogs() {
    return List.unmodifiable(_logs);
  }

  /// 按级别过滤获取日志
  ///
  /// 参数：
  /// - [level] 日志级别，null表示返回所有级别
  List<LogEntry> getLogsByLevel([LogLevel? level]) {
    if (level == null) {
      return getLogs();
    }
    return _logs.where((log) => log.level == level).toList();
  }

  /// 按关键词搜索日志
  ///
  /// 在日志消息和标签中搜索包含关键词的日志。
  ///
  /// 参数：
  /// - [query] 搜索关键词，空字符串返回所有符合条件的日志
  /// - [category] 可选的分类过滤器，null表示不过滤分类
  ///
  /// 返回匹配的日志列表（新列表，不修改内部状态）
  ///
  /// 搜索特性：
  /// - 不区分大小写
  /// - 同时匹配消息内容和标签
  /// - 支持与分类的组合过滤
  List<LogEntry> searchLogs(String query, {LogCategory? category}) {
    Iterable<LogEntry> results = _logs;

    // 先按分类过滤
    if (category != null) {
      results = results.where((log) => log.category == category);
    }

    // 再按关键词搜索
    if (query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      results = results.where((log) {
        // 检查消息内容
        if (log.message.toLowerCase().contains(lowerQuery)) {
          return true;
        }
        // 检查标签
        return log.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
      });
    }

    return results.toList();
  }

  /// 按分类获取日志
  ///
  /// 参数：
  /// - [category] 日志分类
  ///
  /// 返回该分类的所有日志
  List<LogEntry> getLogsByCategory(LogCategory category) {
    return _logs.where((log) => log.category == category).toList();
  }

  /// 按标签获取日志
  ///
  /// 参数：
  /// - [tag] 标签名称（不区分大小写）
  ///
  /// 返回包含该标签的所有日志
  List<LogEntry> getLogsByTag(String tag) {
    final lowerTag = tag.toLowerCase();
    return _logs.where((log) {
      return log.tags.any((t) => t.toLowerCase() == lowerTag);
    }).toList();
  }

  /// 清空所有日志
  ///
  /// 清空内存队列和SharedPreferences中的所有日志。
  /// 此操作不可撤销，请谨慎使用。
  Future<void> clearLogs() async {
    _logs.clear();
    await _persistLogs();
    // 通知监听器日志已清空
    logChangeNotifier.value++;
  }

  /// 获取当前日志数量
  ///
  /// 返回内存队列中的日志条数。
  int get logCount => _logs.length;

  /// 获取日志统计信息
  LogStatistics getStatistics() {
    final byLevel = <LogLevel, int>{};
    final byCategory = <LogCategory, int>{};

    // 初始化计数器
    for (final level in LogLevel.values) {
      byLevel[level] = 0;
    }
    for (final category in LogCategory.values) {
      byCategory[category] = 0;
    }

    // 统计
    for (final log in _logs) {
      byLevel[log.level] = byLevel[log.level]! + 1;
      byCategory[log.category] = byCategory[log.category]! + 1;
    }

    return LogStatistics(
      total: _logs.length,
      byLevel: byLevel,
      byCategory: byCategory,
    );
  }

  /// 导出日志到文件
  ///
  /// 将所有日志导出为文本文件保存到应用目录。
  /// 返回导出的文件路径。
  Future<File> exportToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_exportFileName');

    final content = _logs.map((log) {
      final timestamp = formatTimestamp(log.timestamp);
      final stackTrace = log.stackTrace != null ? '\n${log.stackTrace}' : '';
      return '[$timestamp] [${log.level.label}] ${log.message}$stackTrace';
    }).join('\n\n---\n\n');

    await file.writeAsString(content, flush: true);
    return file;
  }

  // ========== 私有方法 ==========

  /// 从 SharedPreferences 加载已保存的日志；SP 失败时回退到文件。
  Future<void> _loadLogs() async {
    // 优先从 SP 加载
    try {
      final logsJson = await PreferencesService.instance.getString(_prefsKey);
      if (logsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(logsJson) as List<dynamic>;
        _logs.addAll(
          decoded.map((e) => LogEntry.fromMap(e as Map<String, dynamic>)),
        );
        return;
      }
    } catch (e) {
      debugPrint('LoggerService: 从 SP 加载日志失败: $e');
    }

    // 回退：从文件加载
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fallbackFileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
          _logs.addAll(
            decoded.map((e) => LogEntry.fromMap(e as Map<String, dynamic>)),
          );
          debugPrint('LoggerService: 从回退文件加载日志成功（${_logs.length} 条）');
          return;
        }
      }
    } catch (e) {
      debugPrint('LoggerService: 从回退文件加载日志也失败: $e');
    }

    _logs.clear();
  }

  /// 持久化日志：SharedPreferences 优先，失败时回退到文件存储。
  Future<void> _persistLogs() async {
    final data = jsonEncode(_logs.map((e) => e.toMap()).toList());

    // 优先写 SP
    try {
      await PreferencesService.instance.setString(_prefsKey, data);
      _lastPersistSuccess = true;
      return;
    } catch (e1) {
      debugPrint('LoggerService: SP 持久化失败，回退到文件: $e1');
    }

    // 回退：写文件
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fallbackFileName');
      await file.writeAsString(data, flush: true);
      _lastPersistSuccess = true;
      _persistErrorCount++;
      debugPrint('LoggerService: 回退文件保存成功 (SP失败次数=$_persistErrorCount)');
    } catch (e2) {
      _lastPersistSuccess = false;
      _persistErrorCount++;
      debugPrint('LoggerService: SP 和文件持久化均失败');
    }
  }

  /// 格式化时间戳
  ///
  /// 将DateTime格式化为易读的字符串格式。
  /// 格式: YYYY-MM-DD HH:mm:ss
  static String formatTimestamp(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  /// 格式化单条日志为可读的纯文本（用于复制全部信息）
  ///
  /// 包含时间、级别、分类、标签、消息、堆栈，便于贴到工单/聊天里排查问题。
  /// 展示内容与日志详情对话框一致，确保"所见即所复制"。
  static String formatLogForCopy(LogEntry log) {
    final buf = StringBuffer()
      ..writeln('时间: ${formatTimestamp(log.timestamp)}')
      ..writeln('级别: ${log.level.label}')
      ..writeln('分类: ${log.category.label}');
    if (log.tags.isNotEmpty) {
      buf.writeln('标签: ${log.tags.join(', ')}');
    }
    buf
      ..writeln('消息: ${log.message}')
      ..writeln();
    if (log.stackTrace != null && log.stackTrace!.isNotEmpty) {
      buf
        ..writeln('堆栈:')
        ..writeln(log.stackTrace);
    }
    return buf.toString().trimRight();
  }
}

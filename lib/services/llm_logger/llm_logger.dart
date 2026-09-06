/// LLM 调用日志服务
///
/// 将所有前端 LLM 请求和响应记录到本地 JSONL 文件，便于调试和回溯。
///
/// 存储策略：
/// - 文件路径：`{appDocumentsDir}/llm_logs/llm_YYYYMMDD.jsonl`
/// - 每行一条 JSON 记录（JSONL 格式）
/// - 启动时自动清理 7 天前的日志文件
/// - 异步写入队列，不阻塞调用方
///
/// 用法：
/// ```dart
/// // 初始化（main.dart 中调用一次）
/// await LlmLogger.instance.initialize();
///
/// // 记录调用（由 IoLlmHttpClient 拦截器自动调用，无需手动使用）
/// final recordId = LlmLogger.instance.logRequest(...);
/// LlmLogger.instance.logResponse(recordId, ...);
///
/// // 查询最近调用
/// final recent = await LlmLogger.instance.getRecent(limit: 50);
///
/// // 查询单条详情
/// final detail = await LlmLogger.instance.getById(recordId);
///
/// // 清空所有日志
/// await LlmLogger.instance.clear();
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, ValueNotifier, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logger_service.dart';
import 'llm_call_record.dart';

class LlmLogger extends ChangeNotifier {
  static LlmLogger? _instance;
  static LlmLogger get instance {
    _instance ??= LlmLogger._internal();
    return _instance!;
  }

  LlmLogger._internal();

  /// 重置单例（仅测试用）
  static void resetForTesting() {
    _instance = null;
    changeNotifier.value = 0;
  }

  /// 静态 ValueNotifier：UI 可用 `LlmLogger.changeNotifier.addListener(...)`
  /// 监听日志变化，`.value` 为变化计数（每次 log/clear 递增）。
  /// 与 [instance]（也是 ChangeNotifier）并行通知，互不影响。
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  // ==================== 常量 ====================

  /// 日志文件目录名
  static const String _logDirName = 'llm_logs';

  /// 日志文件名前缀
  static const String _logFilePrefix = 'llm_';

  /// 日志保留天数
  static const int _retentionDays = 7;

  /// 单条响应体最大长度（5MB），超出截断
  static const int _maxResponseLength = 5 * 1024 * 1024;

  /// 最近记录的内存缓存条数
  static const int _cacheSize = 200;

  // ==================== 状态 ====================

  /// 日志目录路径
  String? _logDir;

  /// 是否已初始化
  bool _initialized = false;

  /// 异步写入队列
  final List<String> _writeQueue = [];

  /// 是否正在写入
  bool _isWriting = false;

  /// 内存缓存（最近的记录，用于列表页快速访问）
  final List<LlmCallRecord> _recentCache = [];

  /// 变化通知计数器
  int _changeCount = 0;

  /// 获取变化计数器（UI 可用 ValueNotifier 监听）
  int get changeCount => _changeCount;

  // ==================== 初始化 ====================

  /// 初始化日志服务
  ///
  /// - 确保日志目录存在
  /// - 清理过期日志文件
  /// - 加载最近缓存
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      _logDir = '${docsDir.path}/$_logDirName';
      await Directory(_logDir!).create(recursive: true);

      await _cleanOldFiles();
      await _loadRecentCache();

      _initialized = true;
      debugPrint('LlmLogger: 初始化完成, dir=$_logDir');
    } catch (e) {
      debugPrint('LlmLogger: 初始化失败: $e');
      // 初始化失败不阻塞应用
    }
  }

  // ==================== 记录接口 ====================

  /// 记录请求开始，返回记录 ID
  ///
  /// 由 IoLlmHttpClient 在发送请求前调用。
  /// 仅更新内存缓存，不写入文件；等响应完成后统一写入完整记录。
  String logRequest({
    required String id,
    required String endpoint,
    required String requestBody,
    bool isStreaming = false,
  }) {
    // 尝试提取 model
    String? model;
    try {
      final body = jsonDecode(requestBody) as Map<String, dynamic>;
      model = body['model'] as String?;
    } catch (e, st) {
      LoggerService.instance.w(
        'LLM日志: 解析请求body model字段失败: $e',
        category: LogCategory.ai,
        tags: ['llm-logger', 'parse-err'],
        stackTrace: st.toString(),
      );
    }

    final record = LlmCallRecord(
      id: id,
      timestamp: DateTime.now().toUtc(),
      endpoint: endpoint,
      model: model,
      isStreaming: isStreaming,
      requestBody: requestBody,
      isSuccess: false, // 请求阶段标记为未完成
    );

    // 仅更新内存缓存，不写文件
    _updateCache(record);
    return id;
  }

  /// 记录响应完成
  ///
  /// 由 IoLlmHttpClient 在收到完整响应后调用。
  void logResponse({
    required String id,
    required String responseBody,
    required int durationMs,
    bool isSuccess = true,
    String? errorMessage,
  }) {
    // 截断超大响应
    final truncatedBody = responseBody.length > _maxResponseLength
        ? '${responseBody.substring(0, _maxResponseLength)}...(truncated at $_maxResponseLength bytes)'
        : responseBody;

    // 尝试提取 token 统计
    int? promptTokens, completionTokens, totalTokens;
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final usage = json['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        promptTokens = usage['prompt_tokens'] as int?;
        completionTokens = usage['completion_tokens'] as int?;
        totalTokens = usage['total_tokens'] as int?;
      }
    } catch (e, st) {
      LoggerService.instance.w(
        'LLM日志: 解析响应body token用量失败: $e',
        category: LogCategory.ai,
        tags: ['llm-logger', 'parse-err'],
        stackTrace: st.toString(),
      );
    }

    // 从缓存中找到原始请求记录，合并写入完整记录
    final cachedIndex = _recentCache.indexWhere((r) => r.id == id);
    if (cachedIndex >= 0) {
      final updated = _recentCache[cachedIndex].copyWith(
        responseBody: truncatedBody,
        durationMs: durationMs,
        isSuccess: isSuccess,
        errorMessage: errorMessage,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      );
      _recentCache[cachedIndex] = updated;

      // 写入最终完整记录到文件（仅一次）
      _enqueueWrite(updated);
    } else {
      // 缓存中找不到，仅写响应部分
      final record = LlmCallRecord(
        id: id,
        timestamp: DateTime.now().toUtc(),
        endpoint: '',
        isStreaming: false,
        requestBody: '',
        responseBody: truncatedBody,
        durationMs: durationMs,
        isSuccess: isSuccess,
        errorMessage: errorMessage,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      );
      _updateCache(record);
      _enqueueWrite(record);
    }

    _changeCount++;
    changeNotifier.value = _changeCount;
    notifyListeners();
  }

  /// 记录请求失败
  void logError({
    required String id,
    required String errorMessage,
    int? durationMs,
  }) {
    final cachedIndex = _recentCache.indexWhere((r) => r.id == id);
    if (cachedIndex >= 0) {
      final updated = _recentCache[cachedIndex].copyWith(
        durationMs: durationMs,
        isSuccess: false,
        errorMessage: errorMessage,
      );
      _recentCache[cachedIndex] = updated;
      _enqueueWrite(updated);
    }

    _changeCount++;
    changeNotifier.value = _changeCount;
    notifyListeners();
  }

  // ==================== 查询接口 ====================

  /// 获取最近 N 条记录
  ///
  /// 优先从内存缓存返回；不足时从文件补齐。
  Future<List<LlmCallRecord>> getRecent({int limit = 50}) async {
    if (_recentCache.length >= limit) {
      return _recentCache.sublist(0, limit);
    }

    // 缓存不足，从文件读取补充
    final fromFile = await _readRecentFromFile(limit - _recentCache.length);
    return [..._recentCache, ...fromFile];
  }

  /// 根据 ID 查询单条记录
  ///
  /// 先查缓存，再查文件。
  Future<LlmCallRecord?> getById(String id) async {
    // 先查缓存
    final cached = _recentCache.where((r) => r.id == id).firstOrNull;
    if (cached != null) return cached;

    // 缓存未命中，从文件查找
    return _findByIdInFiles(id);
  }

  /// 清空所有日志
  Future<void> clear() async {
    _recentCache.clear();
    _writeQueue.clear();
    _changeCount++;
    changeNotifier.value = _changeCount;
    notifyListeners();

    if (_logDir == null) return;
    try {
      final dir = Directory(_logDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('LlmLogger: 清空日志失败: $e');
    }
  }

  /// 获取日志文件总大小（字节）
  Future<int> getTotalSize() async {
    if (_logDir == null) return 0;
    int totalSize = 0;
    try {
      final dir = Directory(_logDir!);
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } catch (e, st) {
      LoggerService.instance.w(
        'LLM日志: 计算日志目录大小失败: $e',
        category: LogCategory.ai,
        tags: ['llm-logger', 'fs-err'],
        stackTrace: st.toString(),
      );
    }
    return totalSize;
  }

  // ==================== 内部实现 ====================

  /// 更新内存缓存（仅内存，不写文件）
  void _updateCache(LlmCallRecord record) {
    final existingIndex = _recentCache.indexWhere((r) => r.id == record.id);
    if (existingIndex >= 0) {
      _recentCache[existingIndex] = record;
    } else {
      _recentCache.insert(0, record);
      if (_recentCache.length > _cacheSize) {
        _recentCache.removeLast();
      }
    }
  }

  /// 将完整记录加入异步写入队列（仅在响应完成后调用一次）
  void _enqueueWrite(LlmCallRecord record) {
    final line = jsonEncode(record.toJson());
    _writeQueue.add(line);
    _flushWriteQueue();
  }

  /// 异步刷新写入队列
  Future<void> _flushWriteQueue() async {
    if (_isWriting || _writeQueue.isEmpty || _logDir == null) return;

    _isWriting = true;
    try {
      // 取出当前队列中所有待写数据
      final lines = List<String>.from(_writeQueue);
      _writeQueue.clear();

      final today = _dateStr(DateTime.now().toUtc());
      final file = File('$_logDir/$_logFilePrefix$today.jsonl');

      // 批量追加写入
      final content = lines.join('\n');
      if (await file.exists()) {
        await file.writeAsString('\n$content', mode: FileMode.append, flush: true);
      } else {
        await file.writeAsString(content, flush: true);
      }
    } catch (e) {
      debugPrint('LlmLogger: 写入日志失败: $e');
    } finally {
      _isWriting = false;
      // 如果队列中又有新数据，继续刷新
      if (_writeQueue.isNotEmpty) {
        _flushWriteQueue();
      }
    }
  }

  /// 清理过期日志文件
  Future<void> _cleanOldFiles() async {
    if (_logDir == null) return;
    try {
      final dir = Directory(_logDir!);
      if (!await dir.exists()) return;

      final cutoff = DateTime.now().toUtc().subtract(Duration(days: _retentionDays));

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.jsonl')) {
          // 从文件名提取日期：llm_YYYYMMDD.jsonl
          final name = p.basename(entity.path);
          final dateStr = name.replaceAll(_logFilePrefix, '').replaceAll('.jsonl', '');
          try {
            final year = int.parse(dateStr.substring(0, 4));
            final month = int.parse(dateStr.substring(4, 6));
            final day = int.parse(dateStr.substring(6, 8));
            final fileDate = DateTime.utc(year, month, day);
            if (fileDate.isBefore(cutoff)) {
              await entity.delete();
              debugPrint('LlmLogger: 删除过期日志 $name');
            }
          } catch (_) {
            // 文件名格式不匹配，跳过
          }
        }
      }
    } catch (e) {
      debugPrint('LlmLogger: 清理过期文件失败: $e');
    }
  }

  /// 从文件加载最近缓存
  Future<void> _loadRecentCache() async {
    if (_logDir == null) return;
    try {
      final records = await _readRecentFromFile(_cacheSize);
      _recentCache.addAll(records);
    } catch (e) {
      debugPrint('LlmLogger: 加载缓存失败: $e');
    }
  }

  /// 从文件读取最近 N 条记录
  Future<List<LlmCallRecord>> _readRecentFromFile(int limit) async {
    if (_logDir == null) return [];

    final records = <LlmCallRecord>[];
    try {
      final dir = Directory(_logDir!);
      if (!await dir.exists()) return [];

      // 获取所有 JSONL 文件，按日期倒序
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.jsonl')) {
          files.add(entity);
        }
      }
      files.sort((a, b) => b.path.compareTo(a.path)); // 倒序

      for (final file in files) {
        if (records.length >= limit) break;
        try {
          final content = await file.readAsString();
          final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
          for (final line in lines) {
            if (records.length >= limit) break;
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              records.add(LlmCallRecord.fromJson(json));
            } catch (e, st) {
              LoggerService.instance.w(
                'LLM日志: 解析单行调用记录失败: $e',
                category: LogCategory.ai,
                tags: ['llm-logger', 'parse-err'],
                stackTrace: st.toString(),
              );
            }
          }
        } catch (e, st) {
          LoggerService.instance.w(
            'LLM日志: 读取日志文件失败: $e',
            category: LogCategory.ai,
            tags: ['llm-logger', 'fs-err'],
            stackTrace: st.toString(),
          );
        }
      }
    } catch (e, st) {
      LoggerService.instance.w(
        'LLM日志: 扫描日志目录失败: $e',
        category: LogCategory.ai,
        tags: ['llm-logger', 'fs-err'],
        stackTrace: st.toString(),
      );
    }

    return records;
  }

  /// 在文件中按 ID 查找记录
  Future<LlmCallRecord?> _findByIdInFiles(String id) async {
    if (_logDir == null) return null;

    try {
      final dir = Directory(_logDir!);
      if (!await dir.exists()) return null;

      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
        try {
          final content = await entity.readAsString();
          final lines = content.split('\n');
          for (final line in lines.reversed) {
            if (line.trim().isEmpty) continue;
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              if (json['id'] == id) {
                return LlmCallRecord.fromJson(json);
              }
            } catch (e, st) {
              LoggerService.instance.w(
                'LLM日志: 按ID查找记录JSON解析失败: $e',
                category: LogCategory.ai,
                tags: ['llm-logger', 'parse-err'],
                stackTrace: st.toString(),
              );
            }
          }
        } catch (e, st) {
          LoggerService.instance.w(
            'LLM日志: 按ID查找记录文件读取失败: $e',
            category: LogCategory.ai,
            tags: ['llm-logger', 'fs-err'],
            stackTrace: st.toString(),
          );
        }
      }
    } catch (e, st) {
      LoggerService.instance.w(
        'LLM日志: 按ID查找记录目录扫描失败: $e',
        category: LogCategory.ai,
        tags: ['llm-logger', 'fs-err'],
        stackTrace: st.toString(),
      );
    }

    return null;
  }

  // ==================== 工具方法 ====================

  /// 日期字符串 YYYYMMDD
  static String _dateStr(DateTime utc) {
    final y = utc.year.toString();
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}

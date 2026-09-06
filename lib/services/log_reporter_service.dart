import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'logger_service.dart';
import 'preferences_service.dart';

/// 日志上报服务
///
/// 将本地日志批量上报到自建 FastAPI 后端。
/// 静默运行，不影响 LoggerService 正常工作流程。
///
/// 触发条件（满足任一即上报）：
/// - 缓冲区数量 ≥ [batchSize]（默认 20 条）
/// - 距上次上报 ≥ [intervalSeconds]（默认 30 秒）
/// - 手动调用 [flush()]
///
/// 错误处理：
/// - 连续失败 ≥ 3 次后进入退避模式（间隔翻倍，最大 5 分钟）
/// - 上报成功后恢复正常间隔
/// - 失败日志保留在缓冲区，下次重试
class LogReporterService {
  // ========== 单例模式 ==========
  static final LogReporterService _instance = LogReporterService._internal();
  static LogReporterService get instance => _instance;
  LogReporterService._internal();

  // ========== 常量 ==========
  /// 触发上报的缓冲数量阈值
  static const int batchSize = 20;

  /// 定时刷新间隔（秒）
  static const int intervalSeconds = 30;

  /// 单次上报最大条数
  static const int maxPerBatch = 50;

  /// 缓冲区最大容量
  static const int maxBufferSize = 100;

  /// 连续失败进入退避模式的阈值
  static const int backoffThreshold = 3;

  /// 退避最大间隔（秒）
  static const int backoffMaxSeconds = 300;

  // ========== SharedPreferences Keys ==========
  static const String _keyEnabled = 'log_upload_enabled';
  static const String _keyMinLevel = 'log_upload_min_level';
  static const String _keyLastUploadTime = 'log_upload_last_time';

  // ========== 状态 ==========
  /// 是否启用上报
  bool _enabled = true;

  /// 最低上报级别（index 越大级别越高）
  int _minLevelIndex = LogLevel.warning.index;

  /// 待上报缓冲区
  final List<LogEntry> _buffer = [];

  /// 定时器
  Timer? _timer;

  /// 连续失败计数
  int _consecutiveFailures = 0;

  /// 是否正在上报中
  bool _isUploading = false;

  /// 上次上报时间
  DateTime? _lastUploadTime;

  /// 是否已初始化
  bool _initialized = false;

  /// Dio 实例（懒加载）
  Dio? _dio;

  /// 日志上报变化回调列表（UI 层注册）
  final List<void Function()> _listeners = [];

  void addListener(void Function() callback) {
    _listeners.add(callback);
  }

  void removeListener(void Function() callback) {
    _listeners.remove(callback);
  }

  void _notifyListeners() {
    for (final c in List.of(_listeners)) {
      c();
    }
  }

  // ========== 公开 Getter ==========
  bool get enabled => _enabled;
  int get minLevelIndex => _minLevelIndex;
  int get bufferSize => _buffer.length;
  DateTime? get lastUploadTime => _lastUploadTime;
  bool get isUploading => _isUploading;

  /// 当前生效的定时间隔（退避模式下可能更长）
  int get _currentIntervalSeconds {
    if (_consecutiveFailures < backoffThreshold) {
      return intervalSeconds;
    }
    final multiplier = 1 << (_consecutiveFailures - backoffThreshold);
    final seconds = intervalSeconds * multiplier;
    return seconds > backoffMaxSeconds ? backoffMaxSeconds : seconds;
  }

  // ========== 公开方法 ==========

  /// 初始化：加载配置 + 启动定时器
  Future<void> init() async {
    if (_initialized) return;

    await _loadConfig();
    _startTimer();
    _initialized = true;

    // 注册到 LoggerService：每条新日志都回调 onLogAdded
    LoggerService.registerReporter(_onLogAddedRelay);
  }

  /// 中继函数：避免在 log_reporter_service 顶部 import logger_service 形成循环
  void _onLogAddedRelay(LogEntry entry) {
    onLogAdded(entry);
  }

  /// LoggerService 写日志后的回调
  ///
  /// 级别低于 [minLevel] 的日志直接忽略。
  void onLogAdded(LogEntry entry) {
    if (!_enabled || !_initialized) return;

    // 级别过滤：只有 index >= minLevel 才上报
    if (entry.level.index < _minLevelIndex) return;

    _buffer.add(entry);

    // 缓冲区超限时立即上报
    if (_buffer.length >= maxBufferSize) {
      flush();
    }
  }

  /// 立即上报所有缓冲日志
  Future<void> flush() async {
    if (!_enabled || _isUploading || _buffer.isEmpty) return;

    _isUploading = true;
    _notifyListeners();

    try {
      // 分批上报
      while (_buffer.isNotEmpty) {
        final batch = _buffer.take(maxPerBatch).toList();
        final success = await _upload(batch);
        if (success) {
          // 移除已上报成功的条目
          _buffer.removeRange(0, batch.length);
        } else {
          // 上报失败，保留缓冲区等待下次重试
          break;
        }
      }
    } finally {
      _isUploading = false;
      _notifyListeners();
    }
  }

  /// 设置启用/禁用
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await PreferencesService.instance.setBool(_keyEnabled, value);
    _notifyListeners();

    if (!value) {
      _buffer.clear();
      _timer?.cancel();
      _timer = null;
    } else if (_initialized) {
      _startTimer();
    }
  }

  /// 设置最低上报级别
  Future<void> setMinLevel(LogLevel level) async {
    _minLevelIndex = level.index;
    await PreferencesService.instance.setInt(_keyMinLevel, level.index);
    _notifyListeners();

    // 清除缓冲区中级别不够的条目
    _buffer.removeWhere((e) => e.level.index < _minLevelIndex);
  }

  /// 销毁服务
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _dio?.close();
    _dio = null;
    _buffer.clear();
    _initialized = false;

    LoggerService.unregisterReporter();
  }

  // ========== 私有方法 ==========

  /// 从 SharedPreferences 加载配置
  Future<void> _loadConfig() async {
    try {
      final prefs = PreferencesService.instance;
      _enabled = await prefs.getBool(_keyEnabled, defaultValue: true);
      _minLevelIndex = await prefs.getInt(_keyMinLevel, defaultValue: LogLevel.warning.index);

      // 读取上次上报时间
      final lastMs = await prefs.getInt(_keyLastUploadTime, defaultValue: 0);
      if (lastMs > 0) {
        _lastUploadTime = DateTime.fromMillisecondsSinceEpoch(lastMs);
      }
    } catch (e) {
      // 加载失败用默认值继续（避免递归，用 debugPrint）
      debugPrint('LogReporter: 加载配置失败: $e');
    }
  }

  /// 启动定时器
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _currentIntervalSeconds),
      (_) => flush(),
    );
  }

  /// 重建定时器（退避间隔变化时）
  void _restartTimer() {
    if (_enabled && _initialized) {
      _startTimer();
    }
  }

  /// 上报一批日志到后端
  Future<bool> _upload(List<LogEntry> batch) async {
    try {
      final host = await PreferencesService.instance.getString('backend_host');
      if (host.isEmpty) return false;

      final token = await PreferencesService.instance.getString('backend_token');

      _dio ??= Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'X-API-TOKEN': token,
        },
      ));

      final payload = {
        'logs': batch.map((e) => _entryToMap(e)).toList(),
      };

      final response = await _dio!.post(
        '$host/api/logs/upload',
        data: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        _consecutiveFailures = 0;
        _lastUploadTime = DateTime.now();

        // 持久化上报时间
        await PreferencesService.instance.setInt(
          _keyLastUploadTime,
          _lastUploadTime!.millisecondsSinceEpoch,
        );

        _restartTimer(); // 恢复正常间隔
        debugPrint('LogReporter: 上报成功 batch=${batch.length}');
        return true;
      }

      debugPrint('LogReporter: 上报失败 reason=HTTP ${response.statusCode}');
      return _onUploadFailure('HTTP ${response.statusCode}');
    } on DioException catch (e) {
      debugPrint('LogReporter: 上报失败 reason=网络错误: ${e.message ?? e.type.name}');
      return _onUploadFailure('网络错误: ${e.message ?? e.type.name}');
    } catch (e) {
      debugPrint('LogReporter: 上报失败 reason=未知错误: $e');
      return _onUploadFailure('未知错误: $e');
    }
  }

  /// 上报失败处理
  bool _onUploadFailure(String reason) {
    _consecutiveFailures++;

    // 连续失败达到阈值时记录一条本地警告（避免递归上报）
    if (_consecutiveFailures == backoffThreshold) {
      _logLocally('日志上报连续失败 $_consecutiveFailures 次，进入退避模式: $reason');
    }

    _restartTimer(); // 退避模式使用更长间隔
    return false;
  }

  /// 本地记录警告（不触发上报，避免递归）
  void _logLocally(String message) {
    // 直接写入 LoggerService 内存队列，不触发 onLogAdded
    LoggerService.instance.w(
      message,
      category: LogCategory.network,
      tags: ['log-reporter', 'backoff'],
    );
  }

  /// LogEntry 转为上报用的 Map
  Map<String, dynamic> _entryToMap(LogEntry entry) {
    return {
      'timestamp': entry.timestamp.toUtc().toIso8601String(),
      'level': entry.level.label.toLowerCase(),
      'message': entry.message,
      if (entry.stackTrace != null) 'stack_trace': entry.stackTrace,
      'category': entry.category.key,
      'tags': entry.tags,
    };
  }
}

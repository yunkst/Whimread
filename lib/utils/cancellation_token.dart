
import 'package:flutter/foundation.dart' show VoidCallback;
import '../services/logger_service.dart';

/// 取消令牌
///
/// 用于跨层传递取消信号，支持监听器模式和超时自动取消。
///
/// 使用示例：
/// ```dart
/// final token = CancellationToken();
///
/// // 注册取消监听器
/// token.register(() {
///   LoggerService.instance.i('操作已取消');
/// });
///
/// // 取消操作
/// token.cancel(reason: '用户主动取消');
///
/// // 检查是否已取消
/// if (token.isCancelled) {
///   LoggerService.instance.i('停止处理');
/// }
/// ```
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _callbacks = [];

  /// 是否已取消
  bool get isCancelled => _isCancelled;

  /// 取消操作
  ///
  /// [reason] 可选的取消原因说明（进日志，便于排障）
  void cancel({String? reason}) {
    if (_isCancelled) {
      LoggerService.instance.w(
        '操作已经取消，无需重复取消',
        category: LogCategory.general,
        tags: ['cancellation'],
      );
      return;
    }

    _isCancelled = true;
    LoggerService.instance.i(
      '操作已取消${reason != null ? ": $reason" : ""}',
      category: LogCategory.general,
      tags: ['cancellation'],
    );

    // 通知所有监听器
    for (final callback in _callbacks) {
      try {
        callback();
      } catch (e, stackTrace) {
        LoggerService.instance.e(
          '取消回调执行失败: $e',
          stackTrace: stackTrace.toString(),
          category: LogCategory.general,
          tags: ['cancellation', 'callback', 'failed'],
        );
      }
    }
    _callbacks.clear();
  }

  /// 注册取消监听器
  ///
  /// 当令牌被取消时，会调用 [callback]
  /// 返回一个取消注册的函数
  VoidCallback register(VoidCallback callback) {
    if (_isCancelled) {
      LoggerService.instance.w(
        '令牌已取消，注册监听器会立即执行',
        category: LogCategory.general,
        tags: ['cancellation'],
      );
      // 立即执行回调
      try {
        callback();
      } catch (e, stackTrace) {
        LoggerService.instance.e(
          '取消回调执行失败: $e',
          stackTrace: stackTrace.toString(),
          category: LogCategory.general,
          tags: ['cancellation', 'callback', 'failed'],
        );
      }
      return () {};
    }

    _callbacks.add(callback);

    // 返回取消注册函数
    return () {
      _callbacks.remove(callback);
    };
  }
}


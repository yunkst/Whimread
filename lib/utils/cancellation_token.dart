
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
///   print('操作已取消');
/// });
///
/// // 取消操作
/// token.cancel(reason: '用户主动取消');
///
/// // 检查是否已取消
/// if (token.isCancelled) {
///   print('操作已取消，停止处理');
/// }
/// ```
class CancellationToken {
  bool _isCancelled = false;
  String? _cancelReason;
  final List<VoidCallback> _callbacks = [];
  final List<CancellationToken> _childTokens = [];

  /// 是否已取消
  bool get isCancelled => _isCancelled;

  /// 取消原因
  String? get cancelReason => _cancelReason;

  /// 取消操作
  ///
  /// [reason] 可选的取消原因说明
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
    _cancelReason = reason;
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

    // 级联取消所有子令牌
    for (final child in _childTokens) {
      child.cancel(reason: '父令牌已取消: $reason');
    }
    _childTokens.clear();
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

  /// 创建一个子令牌
  ///
  /// 子令牌会在父令牌取消时自动取消
  CancellationToken createChildToken() {
    if (_isCancelled) {
      final child = CancellationToken();
      child._isCancelled = true;
      child._cancelReason = '父令牌已取消';
      return child;
    }

    final child = CancellationToken();
    _childTokens.add(child);

    // 注册父令牌取消时自动取消子令牌
    register(() {
      child._isCancelled = true;
      child._cancelReason = _cancelReason;
      child._notifyCallbacks();
    });

    return child;
  }

  /// 通知所有监听器（内部方法）
  void _notifyCallbacks() {
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

}


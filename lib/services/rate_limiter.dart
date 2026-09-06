import 'dart:async';
import 'logger_service.dart';

/// 速率限制器
///
/// 确保操作之间至少间隔指定的时间
class RateLimiter {
  /// 时间间隔
  final Duration interval;

  /// 上次请求的时间戳
  DateTime? _lastRequestTime;

  /// 创建速率限制器
  ///
  /// [interval] 时间间隔，默认30秒
  RateLimiter({this.interval = const Duration(seconds: 30)});

  /// 获取执行许可（自动等待）
  ///
  /// 如果距离上次请求不足interval时间，会自动等待剩余时间
  Future<void> acquire() async {
    if (_lastRequestTime == null) {
      // 第一次请求，无需等待
      _lastRequestTime = DateTime.now();
      return;
    }

    final elapsed = DateTime.now().difference(_lastRequestTime!);

    if (elapsed < interval) {
      // 需要等待剩余时间
      final waitTime = interval - elapsed;
      LoggerService.instance.i(
        '速率限制: 等待 ${waitTime.inSeconds} 秒',
        category: LogCategory.network,
        tags: ['rate-limit'],
      );
      await Future.delayed(waitTime);
    }

    // 更新最后请求时间
    _lastRequestTime = DateTime.now();
  }

  /// 重置速率限制器
  ///
  /// 重置后，下一次acquire()将立即返回
  void reset() {
    _lastRequestTime = null;
    LoggerService.instance.i(
      '速率限制器已重置',
      category: LogCategory.network,
      tags: ['rate-limit'],
    );
  }

}

/// LLM 重试 UI 信号总线
///
/// 模块级单例 `RetrySignals` 持有 `ValueNotifier<RetryState?>`,供 UI
/// (RetryBanner) 通过 `ValueListenableBuilder` 订阅。
///
/// 信号来源:
/// - 传输层:IoLlmHttpClient.postJson/postJsonStream 通过 withRetry 的
///   onRetry 回调报告 transportRetry → reportTransport
/// - 回合层:agent_loop.dart 的 round-level catch 块直接调 reportRound
///   (不走事件流,绕开 shouldMainSessionHandleEvent 过滤 — spec §3.1.1 方案 B)
///
/// 多 session 串号限制:模块级单例同时只能显示一个 active retry,本次接受(YAGNI)。
/// factory reset:test 用 resetForTest() 复位 ValueNotifier。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:novel_app/utils/retry_helper.dart';

/// 重试层级
enum RetryLevel { transport, round }

/// 重试错误类别 — 替代原 [categorizeRetryError] 的字符串返回值。
///
/// 展示文案（中文标签）由 [RetryErrorCategoryLabel] extension 在
/// UI 层（[RetryBanner]）提供，实现 enum → 文案的本地化解耦。
enum RetryErrorCategory {
  rateLimited,       // 429 限流
  requestTimeout,    // 408 请求超时
  requestError,      // 4xx 其他
  serverError,       // 5xx
  networkDisconnected, // Socket/HandshakeException
  responseTimeout,   // TimeoutException
  retrying,          // 其他
}

/// 当前活跃的重试状态
@immutable
class RetryState {
  final RetryLevel level;
  final int attempt;
  final int maxAttempts;
  final int delayMs;
  final RetryErrorCategory errorCategory;

  /// 可选：HTTP 状态码，仅在 [RetryErrorCategory.requestError]/[serverError]
  /// 时有值，便于 UI 层拼接 "请求错误 400" 等完整文案。
  final int? httpStatusCode;

  const RetryState({
    required this.level,
    required this.attempt,
    required this.maxAttempts,
    required this.delayMs,
    required this.errorCategory,
    this.httpStatusCode,
  });
}

/// 模块级重试信号单例
class RetrySignals {
  static final RetrySignals instance = RetrySignals._();
  RetrySignals._();

  /// UI 端通过 ValueListenableBuilder 订阅;null = 无活跃重试,横幅不渲染
  ValueNotifier<RetryState?> notifier = ValueNotifier<RetryState?>(null);

  /// 传输层 withRetry 报告一次重试(覆盖式写入最新)
  void reportTransport({
    required int attempt,
    required int maxAttempts,
    required int delayMs,
    required Object error,
  }) =>
      _report(RetryLevel.transport, attempt, maxAttempts, delayMs, error);

  /// 回合层 agent_loop 报告一次重试
  void reportRound({
    required int attempt,
    required int maxAttempts,
    required int delayMs,
    required Object error,
  }) =>
      _report(RetryLevel.round, attempt, maxAttempts, delayMs, error);

  /// 报告一次重试 — [reportTransport]/[reportRound] 的共用实现,
  /// 仅 [RetryLevel] 不同,合并避免字段漂移。
  void _report(
    RetryLevel level,
    int attempt,
    int maxAttempts,
    int delayMs,
    Object error,
  ) {
    notifier.value = RetryState(
      level: level,
      attempt: attempt,
      maxAttempts: maxAttempts,
      delayMs: delayMs,
      errorCategory: categorizeRetryError(error),
      httpStatusCode:
          error is RetryableHttpException ? error.statusCode : null,
    );
  }

  /// 重试结束(success / final failure / agent done):清空让横幅消失
  void clear() {
    notifier.value = null;
  }

  /// 测试用复位(清空当前值，避免影响后续测试);release 代码不应调用。
  /// 注意：不 dispose 并重建 ValueNotifier，因为已挂载的 ValueListenableBuilder
  /// 持有旧引用，重建会导致它监听一个已 dispose 的 notifier。仅清值即可。
  @visibleForTesting
  void resetForTest() {
    notifier.value = null;
  }
}

/// 共享错误分类工具 — 传输层与回合层共用，避免映射逻辑重复。
///
/// 返回 [RetryErrorCategory] enum（非字符串），展示文案由
/// [RetryErrorCategoryLabel] 在 UI 层映射，实现解耦。
///
/// - 429 → [RetryErrorCategory.rateLimited]
/// - 408 → [RetryErrorCategory.requestTimeout]
/// - 4xx 其他 → [RetryErrorCategory.requestError]
/// - 5xx → [RetryErrorCategory.serverError]
/// - Socket/HandshakeException → [RetryErrorCategory.networkDisconnected]
/// - TimeoutException → [RetryErrorCategory.responseTimeout]
/// - 其它 → [RetryErrorCategory.retrying]
RetryErrorCategory categorizeRetryError(Object error) {
  if (error is RetryableHttpException) {
    final code = error.statusCode;
    if (code == 429) return RetryErrorCategory.rateLimited;
    if (code == 408) return RetryErrorCategory.requestTimeout;
    if (code >= 500) return RetryErrorCategory.serverError;
    return RetryErrorCategory.requestError;
  }
  if (error is SocketException || error is HandshakeException) {
    return RetryErrorCategory.networkDisconnected;
  }
  if (error is TimeoutException) return RetryErrorCategory.responseTimeout;
  return RetryErrorCategory.retrying;
}

/// [RetryErrorCategory] → 中文展示文案的 UI 层映射。
///
/// 放在 [RetryBanner] 之外、与 enum 同文件，便于集中维护文案；
/// i18n 未来可在此扩展多语言。
extension RetryErrorCategoryLabel on RetryErrorCategory {
  String get label {
    switch (this) {
      case RetryErrorCategory.rateLimited:
        return '限流';
      case RetryErrorCategory.requestTimeout:
        return '请求超时';
      case RetryErrorCategory.requestError:
        return '请求错误';
      case RetryErrorCategory.serverError:
        return '服务端错误';
      case RetryErrorCategory.networkDisconnected:
        return '网络断开';
      case RetryErrorCategory.responseTimeout:
        return '响应超时';
      case RetryErrorCategory.retrying:
        return '重试中';
    }
  }
}

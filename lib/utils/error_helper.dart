import 'package:flutter/material.dart';
import '../services/logger_service.dart';
import 'toast_utils.dart';

/// 错误处理辅助类
///
/// 提供统一的错误处理和日志记录接口，确保所有用户可见的错误提示都被正确记录。
class ErrorHelper {
  /// 显示错误提示并记录日志
  ///
  /// [context] - BuildContext 上下文
  /// [userMessage] - 显示给用户的错误消息
  /// [error] - 错误对象（可选）
  /// [stackTrace] - 堆栈跟踪（可选）
  /// [category] - 日志分类（默认为 general）
  /// [tags] - 日志标签（可选）
  static void showErrorWithLog(
    BuildContext context,
    String userMessage, {
    Object? error,
    StackTrace? stackTrace,
    LogCategory category = LogCategory.general,
    List<String> tags = const [],
  }) {
    // 记录错误日志
    LoggerService.instance.e(
      userMessage,
      stackTrace: stackTrace?.toString(),
      category: category,
      tags: [...tags, 'user-visible'],
    );

    // 显示用户提示
    if (context.mounted) {
      ToastUtils.showError(error != null ? '$userMessage: $error' : userMessage,
          context: context);
    }
  }

}

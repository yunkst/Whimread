import 'package:flutter/material.dart';

/// ReaderErrorView - 阅读器错误视图
///
/// 职责：
/// - 显示错误消息
/// - 提供重试按钮
class ReaderErrorView extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const ReaderErrorView({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            errorMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

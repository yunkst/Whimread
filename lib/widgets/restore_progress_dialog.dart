import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';

/// 恢复状态
enum RestoreState {
  downloading,
  restoring,
  completed,
  failed,
}

/// 恢复进度对话框
///
/// 显示从服务器恢复备份的进度和状态。
class RestoreProgressDialog extends StatefulWidget {
  final Future<void> Function(void Function(RestoreState state)) restoreTask;

  const RestoreProgressDialog({
    super.key,
    required this.restoreTask,
  });

  /// 显示对话框并执行恢复
  ///
  /// 返回 true 表示恢复成功
  static Future<bool> show({
    required BuildContext context,
    required Future<void> Function(void Function(RestoreState state))
        restoreTask,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => RestoreProgressDialog(
        restoreTask: restoreTask,
      ),
    );
    return result ?? false;
  }

  @override
  State<RestoreProgressDialog> createState() => _RestoreProgressDialogState();
}

class _RestoreProgressDialogState extends State<RestoreProgressDialog> {
  RestoreState _state = RestoreState.downloading;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startRestore();
  }

  Future<void> _startRestore() async {
    try {
      await widget.restoreTask((newState) {
        if (mounted) {
          setState(() {
            _state = newState;
          });
        }
      });

      if (mounted) {
        setState(() {
          _state = RestoreState.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = RestoreState.failed;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          _buildStateIcon(),
          const SizedBox(width: 8),
          Text(_buildTitle()),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_state == RestoreState.downloading ||
                _state == RestoreState.restoring) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _state == RestoreState.downloading ? '正在下载备份...' : '正在恢复数据...',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ] else if (_state == RestoreState.completed) ...[
              Icon(Icons.check_circle,
                  size: 48, color: context.appColors.success),
              const SizedBox(height: 16),
              const Text(
                '数据已恢复',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请重启应用以完成恢复',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ] else if (_state == RestoreState.failed) ...[
              Icon(Icons.error, size: 48, color: context.appColors.error),
              const SizedBox(height: 16),
              const Text(
                '恢复失败',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.appColors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage ?? '未知错误',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _state == RestoreState.completed
          ? [
              TextButton(
                onPressed: () {
                  // 退出应用
                  if (Platform.isAndroid || Platform.isIOS) {
                    SystemNavigator.pop();
                  } else {
                    exit(0);
                  }
                },
                child: const Text('重启应用'),
              ),
            ]
          : _state == RestoreState.failed
              ? [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('关闭'),
                  ),
                ]
              : null,
    );
  }

  Widget _buildStateIcon() {
    switch (_state) {
      case RestoreState.downloading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case RestoreState.restoring:
        return Icon(Icons.restore, color: Theme.of(context).colorScheme.primary);
      case RestoreState.completed:
        return Icon(Icons.check_circle, color: context.appColors.success);
      case RestoreState.failed:
        return Icon(Icons.error, color: context.appColors.error);
    }
  }

  String _buildTitle() {
    switch (_state) {
      case RestoreState.downloading:
        return '下载中';
      case RestoreState.restoring:
        return '恢复中';
      case RestoreState.completed:
        return '恢复成功';
      case RestoreState.failed:
        return '恢复失败';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:novel_api/novel_api.dart';
import '../core/theme/app_colors.dart';
import '../utils/format_utils.dart';

/// 备份进度对话框
///
///显示数据库备份的上传进度和状态
class BackupProgressDialog extends StatefulWidget {
  final Future<BackupUploadResponse> Function() uploadTask;

  const BackupProgressDialog({
    super.key,
    required this.uploadTask,
  });

  /// 显示对话框并执行上传
  ///
  /// 返回上传结果，如果失败则返回null
  static Future<BackupUploadResponse?> show({
    required BuildContext context,
    required Future<BackupUploadResponse> Function() uploadTask,
  }) async {
    return showDialog<BackupUploadResponse>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackupProgressDialog(
        uploadTask: uploadTask,
      ),
    );
  }

  @override
  State<BackupProgressDialog> createState() => _BackupProgressDialogState();
}

class _BackupProgressDialogState extends State<BackupProgressDialog> {
  /// 上传状态
  BackupState _state = BackupState.preparing;

  /// 上传进度 (0.0 - 1.0)
  double _progress = 0.0;

  /// 已上传字节数
  int _uploadedBytes = 0;

  /// 总字节数
  int _totalBytes = 0;

  /// 上传结果
  BackupUploadResponse? _result;

  /// 错误信息
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startUpload();
  }

  /// 开始上传
  Future<void> _startUpload() async {
    try {
      setState(() {
        _state = BackupState.uploading;
      });

      // 执行上传任务（这里会通过回调更新进度）
      final result = await widget.uploadTask();

      // 上传成功
      if (mounted) {
        setState(() {
          _state = BackupState.completed;
          _result = result;
          _progress = 1.0;
        });

        // 延迟关闭对话框，让用户看到完成状态
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.of(context).pop(_result);
        }
      }
    } catch (e) {
      // 上传失败
      if (mounted) {
        setState(() {
          _state = BackupState.failed;
          _errorMessage = e.toString();
        });

        // 延迟关闭对话框，让用户看到错误信息
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop(null);
        }
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
            // 进度条或状态信息
            if (_state == BackupState.uploading) ...[
              _buildProgressBar(),
              const SizedBox(height: 16),
              _buildProgressText(),
            ] else if (_state == BackupState.completed) ...[
              _buildSuccessInfo(),
            ] else if (_state == BackupState.failed) ...[
              _buildErrorInfo(),
            ] else ...[
              _buildPreparingText(),
            ],
          ],
        ),
      ),
      actions: _state == BackupState.failed
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('关闭'),
              ),
            ]
          : null,
    );
  }

  /// 构建状态图标
  Widget _buildStateIcon() {
    switch (_state) {
      case BackupState.preparing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case BackupState.uploading:
        return Icon(Icons.cloud_upload_rounded,
            color: Theme.of(context).colorScheme.primary);
      case BackupState.completed:
        return Icon(Icons.check_circle, color: context.appColors.success);
      case BackupState.failed:
        return Icon(Icons.error, color: context.appColors.error);
    }
  }

  /// 构建标题
  String _buildTitle() {
    switch (_state) {
      case BackupState.preparing:
        return '准备备份';
      case BackupState.uploading:
        return '上传中';
      case BackupState.completed:
        return '备份成功';
      case BackupState.failed:
        return '备份失败';
    }
  }

  /// 构建进度条
  Widget _buildProgressBar() {
    return Column(
      children: [
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 构建进度文本
  Widget _buildProgressText() {
    final percentage = (_progress * 100).toInt();
    final uploaded = FormatUtils.formatFileSize(_uploadedBytes);
    final total = FormatUtils.formatFileSize(_totalBytes);

    return Text(
      '$percentage% ($uploaded / $total)',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 14,
      ),
    );
  }

  /// 构建准备文本
  Widget _buildPreparingText() {
    return Text(
      '正在准备上传...',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 14,
      ),
    );
  }

  /// 构建成功信息
  Widget _buildSuccessInfo() {
    if (_result == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('文件名', _result!.filename),
        const SizedBox(height: 8),
        _buildInfoRow('存储路径', _result!.storedPath),
        const SizedBox(height: 8),
        _buildInfoRow('文件大小', FormatUtils.formatFileSize(_result!.fileSize)),
      ],
    );
  }

  /// 构建错误信息
  Widget _buildErrorInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appColors.errorContainer),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: context.appColors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '未知错误',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// 更新上传进度（供外部调用）
  void updateProgress(int sent, int total) {
    if (mounted) {
      setState(() {
        _uploadedBytes = sent;
        _totalBytes = total;
        _progress = total > 0 ? sent / total : 0.0;
      });
    }
  }
}

/// 备份状态
enum BackupState {
  /// 准备中
  preparing,

  /// 上传中
  uploading,

  /// 完成
  completed,

  /// 失败
  failed,
}

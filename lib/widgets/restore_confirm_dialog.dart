import 'package:flutter/material.dart';
import 'common/base_dialog.dart';
import '../core/theme/app_colors.dart';
import '../utils/format_utils.dart';

/// 恢复确认对话框
///
/// 显示恢复操作的警告信息，防止用户误操作覆盖数据。
///
/// 继承 [BaseDialog],把内容拆到 [buildContent]、按钮拆到 [buildActions]。
/// 为了与改造前保持字节级一致(原 [AlertDialog] 未指定 contentPadding / elevation /
/// shape 等参数),本类重写 [build] 直接构造同样的 [AlertDialog],只是把内容
/// 委托给 [buildContent] / [buildActions]。
class RestoreConfirmDialog extends BaseDialog {
  final String fileName;
  final int fileSize;
  final String uploadedAt;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const RestoreConfirmDialog({
    super.key,
    required this.fileName,
    required this.fileSize,
    required this.uploadedAt,
    required this.onConfirm,
    this.onCancel,
  });

  /// 显示对话框
  ///
  /// 返回用户是否确认恢复。
  /// [barrierDismissible] 透传给 [showDialog],默认 true(与改造前行为一致)。
  static Future<bool> show({
    required BuildContext context,
    required String fileName,
    required int fileSize,
    required String uploadedAt,
    bool barrierDismissible = true,
  }) async {
    final result = await BaseDialog.show<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      dialog: RestoreConfirmDialog(
        fileName: fileName,
        fileSize: fileSize,
        uploadedAt: uploadedAt,
        onConfirm: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('将从服务器备份恢复数据，请确认：'),
        const SizedBox(height: 16),
        _buildInfoRow(context, '文件名', fileName),
        const SizedBox(height: 8),
        _buildInfoRow(
            context, '文件大小', FormatUtils.formatFileSize(fileSize)),
        const SizedBox(height: 8),
        _buildInfoRow(context, '上传时间', uploadedAt),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.appColors.warningContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.appColors.warningContainer),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 20, color: context.appColors.onWarningContainer),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '恢复将覆盖当前所有数据，建议先备份。恢复后需重启应用。',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      TextButton(
        onPressed: onCancel,
        child: const Text('取消'),
      ),
      ElevatedButton(
        onPressed: onConfirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.appColors.error,
          foregroundColor: context.appColors.onSemantic,
        ),
        child: const Text('确认恢复'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: context.appColors.warning),
          const SizedBox(width: 8),
          const Text('确认恢复数据'),
        ],
      ),
      content: buildContent(context),
      actions: buildActions(context),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// 备份确认结果
///
/// [confirmed] 用户是否点击"开始备份"
/// [excludeToken] 用户是否勾选"不包含 API Token"
class BackupConfirmResult {
  final bool confirmed;
  final bool excludeToken;

  const BackupConfirmResult({
    required this.confirmed,
    required this.excludeToken,
  });
}

/// 备份确认对话框
///
/// 显示备份操作的确认信息，包括备份包大小、是否排除 API Token 等
class BackupConfirmDialog extends StatefulWidget {
  final String fileName;
  final String fileSize;
  final void Function(bool excludeToken) onConfirm;
  final VoidCallback? onCancel;

  const BackupConfirmDialog({
    super.key,
    required this.fileName,
    required this.fileSize,
    required this.onConfirm,
    this.onCancel,
  });

  /// 显示对话框
  ///
  /// 返回 [BackupConfirmResult]；若用户取消则 confirmed=false
  static Future<BackupConfirmResult> show({
    required BuildContext context,
    required String fileName,
    required String fileSize,
  }) async {
    final result = await showDialog<BackupConfirmResult>(
      context: context,
      builder: (context) => BackupConfirmDialog(
        fileName: fileName,
        fileSize: fileSize,
        onConfirm: (excludeToken) => Navigator.of(context).pop(
          BackupConfirmResult(confirmed: true, excludeToken: excludeToken),
        ),
        onCancel: () => Navigator.of(context).pop(
          const BackupConfirmResult(confirmed: false, excludeToken: false),
        ),
      ),
    );
    return result ?? const BackupConfirmResult(confirmed: false, excludeToken: false);
  }

  @override
  State<BackupConfirmDialog> createState() => _BackupConfirmDialogState();
}

class _BackupConfirmDialogState extends State<BackupConfirmDialog> {
  bool _excludeToken = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.backup_rounded, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('确认备份数据'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('即将上传备份包到服务器，请确认：'),
          const SizedBox(height: 16),
          _buildInfoRow(context, '文件名', widget.fileName),
          const SizedBox(height: 8),
          _buildInfoRow(context, '文件大小', widget.fileSize),
          const SizedBox(height: 12),
          // Token 排除勾选框
          InkWell(
            onTap: () => setState(() => _excludeToken = !_excludeToken),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: _excludeToken,
                    onChanged: (v) =>
                        setState(() => _excludeToken = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      '不包含 API Token（迁移到新设备后需手动重新配置）',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appColors.infoContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.appColors.infoContainer),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 20, color: context.appColors.onInfoContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '备份包内含数据库与阅读器设置、书签、LLM 配置等偏好设置。'
                    '备份文件将保存在服务器，不会被删除，您可以随时恢复数据。',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.onInfoContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => widget.onConfirm(_excludeToken),
          child: const Text('开始备份'),
        ),
      ],
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

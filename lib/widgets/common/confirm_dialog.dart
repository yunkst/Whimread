import 'package:flutter/material.dart';
import 'base_dialog.dart';

/// 通用确认对话框
///
/// 提供标准的确认/取消对话框，支持自定义标题、内容、按钮文本和图标。
///
/// 功能特性：
/// - 统一的Material Design 3风格
/// - 可自定义按钮文本和颜色
/// - 支持富文本内容
/// - 支持自定义图标
/// - 继承BaseDialog，保持UI一致性
///
/// 示例:
/// ```dart
/// final confirmed = await ConfirmDialog.show(
///   context,
///   title: '确认删除',
///   message: '删除后无法恢复，是否继续？',
///   confirmText: '删除',
///   cancelText: '取消',
///   icon: Icons.delete,
/// );
/// if (confirmed == true) {
///   // 用户点击了确认
/// }
/// ```
///
/// 高级示例:
/// ```dart
/// final confirmed = await ConfirmDialog.show(
///   context,
///   title: '重要操作',
///   message: '此操作将影响所有数据',
///   confirmText: '继续',
///   cancelText: '返回',
///   icon: Icons.warning_amber,
///   confirmColor: Colors.red,
///   isDangerous: true,
/// );
/// ```
class ConfirmDialog extends BaseDialog {
  /// 对话框消息内容
  final String message;

  /// 确认按钮文本，默认为"确认"
  final String confirmText;

  /// 取消按钮文本，默认为"取消"
  final String cancelText;

  /// 对话框图标（可选）
  final IconData? icon;

  /// 确认按钮的颜色，默认使用主题色
  final Color? confirmColor;

  /// 是否为危险操作（影响按钮样式）
  final bool isDangerous;

  /// 是否显示图标在标题中
  final bool showIconInTitle;

  /// 消息文本样式
  final TextStyle? messageStyle;

  /// 对齐方式
  final TextAlign? textAlign;

  const ConfirmDialog({
    super.key,
    required super.title,
    required this.message,
    this.confirmText = '确认',
    this.cancelText = '取消',
    this.icon,
    this.confirmColor,
    this.isDangerous = false,
    this.showIconInTitle = true,
    this.messageStyle,
    this.textAlign,
    super.animationConfig,
    super.barrierDismissible,
    super.width,
    super.maxWidth,
    super.contentPadding,
    super.borderRadius,
    super.backgroundColor,
    super.shadowColor,
    super.elevation,
  });

  /// 显示确认对话框并返回用户选择
  ///
  /// 返回 `true` 表示用户点击确认，`false` 表示点击取消，`null` 表示对话框被关闭
  ///
  /// 参数说明：
  /// - [context] 上下文
  /// - [title] 对话框标题
  /// - [message] 对话框内容信息
  /// - [confirmText] 确认按钮文本，默认为"确认"
  /// - [cancelText] 取消按钮文本，默认为"取消"
  /// - [icon] 对话框图标
  /// - [confirmColor] 确认按钮颜色
  /// - [isDangerous] 是否为危险操作（红色高亮确认按钮）
  /// - [showIconInTitle] 是否在标题中显示图标
  /// - [messageStyle] 消息文本样式
  /// - [textAlign] 文本对齐方式
  /// - [width] 对话框宽度
  /// - [maxWidth] 对话框最大宽度
  /// - [barrierDismissible] 是否允许点击外部关闭
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '确认',
    String cancelText = '取消',
    IconData? icon,
    Color? confirmColor,
    bool isDangerous = false,
    bool showIconInTitle = true,
    TextStyle? messageStyle,
    TextAlign? textAlign,
    double? width,
    double maxWidth = 560,
    bool barrierDismissible = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => ConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        icon: icon,
        confirmColor: confirmColor,
        isDangerous: isDangerous,
        showIconInTitle: showIconInTitle,
        messageStyle: messageStyle,
        textAlign: textAlign,
        width: width,
        maxWidth: maxWidth,
        barrierDismissible: barrierDismissible,
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 确定确认按钮颜色
    Color buttonColor =
        confirmColor ?? (isDangerous ? colorScheme.error : colorScheme.primary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 如果有图标且不在标题中显示，则单独显示
        if (icon != null && !showIconInTitle) ...[
          Row(
            children: [
              Icon(
                icon,
                color: buttonColor,
                size: 32,
              ),
              const SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // 消息内容
        Text(
          message,
          style: messageStyle ??
              Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.87),
                  ),
          textAlign: textAlign ?? TextAlign.left,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 如果需要在标题中显示图标，构建带图标的标题
    if (icon != null && showIconInTitle) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final buttonColor = confirmColor ??
          (isDangerous ? colorScheme.error : colorScheme.primary);

      return AlertDialog(
        title: buildTitleWithIcon(
          context: context,
          icon: icon!,
          title: title!,
          color: buttonColor,
        ),
        content: buildContent(context),
        actions: buildActions(context),
        contentPadding: contentPadding,
        backgroundColor: backgroundColor,
        elevation: elevation,
        shadowColor: shadowColor ?? colorScheme.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(16),
        ),
      );
    }

    // 否则使用默认构建
    return super.build(context);
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 确定确认按钮颜色
    Color buttonColor =
        confirmColor ?? (isDangerous ? colorScheme.error : colorScheme.primary);

    return [
      // 取消按钮
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(
          cancelText,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.74),
          ),
        ),
      ),

      // 确认按钮
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        style: TextButton.styleFrom(
          foregroundColor: buttonColor,
          backgroundColor:
              isDangerous ? buttonColor.withValues(alpha: 0.08) : null,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
        ),
        child: Text(confirmText),
      ),
    ];
  }
}

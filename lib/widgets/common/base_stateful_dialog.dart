import 'package:flutter/material.dart';
import 'base_dialog.dart';

/// 有状态的基础对话框抽象类
///
/// 与 [BaseDialog] 共享同样的 `buildContent` / `buildActions` 契约与所有 UI helper
/// (通过 [DialogCreatorsMixin]),适用于需要在内部管理状态(如
/// [TextEditingController]、滚动位置、自定义动画等)的对话框。
///
/// 子类必须实现 [BaseStatefulDialog.buildContent],可覆写
/// [BaseStatefulDialog.buildActions]。子类的 State 通过 [widget] 字段读取配置
/// 与调用上述两个方法。
///
/// 示例:
/// ```dart
/// class MyDialog extends BaseStatefulDialog {
///   const MyDialog({super.key, required super.title});
///
///   @override
///   Widget buildContent(BuildContext context) => Text('content');
///
///   @override
///   List<Widget>? buildActions(BuildContext context) => [
///         TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
///       ];
///
///   @override
///   MyDialogState createState() => MyDialogState();
/// }
///
/// class MyDialogState extends BaseStatefulDialogState<MyDialog> {
///   @override
///   Widget buildDialog(BuildContext context) {
///     // 可调用 widget.buildContent(context) / widget.buildActions(context)
///     // 也可完全自定义 AlertDialog 布局(继承默认实现即可)。
///     return super.buildDialog(context);
///   }
/// }
/// ```
abstract class BaseStatefulDialog extends StatefulWidget {
  /// 对话框标题（可选）
  final String? title;

  /// 是否允许点击外部关闭
  final bool barrierDismissible;

  /// 对话框宽度约束（null表示使用默认约束）
  final double? width;

  /// 对话框最大宽度
  final double maxWidth;

  /// 对话框内边距
  final EdgeInsetsGeometry contentPadding;

  /// 对话框圆角
  final BorderRadius? borderRadius;

  /// 背景颜色（null表示使用主题颜色）
  final Color? backgroundColor;

  /// 阴影颜色
  final Color? shadowColor;

  /// 阴影深度
  final double elevation;

  const BaseStatefulDialog({
    super.key,
    this.title,
    this.barrierDismissible = true,
    this.width,
    this.maxWidth = 560,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.borderRadius,
    this.backgroundColor,
    this.shadowColor,
    this.elevation = 8.0,
  });

  /// 构建对话框内容
  ///
  /// 子类必须实现此方法来提供对话框的具体内容
  Widget buildContent(BuildContext context);

  /// 构建对话框操作按钮（可选）
  ///
  /// 子类可以重写此方法来提供自定义的操作按钮
  List<Widget>? buildActions(BuildContext context) => null;

  /// 显示对话框
  ///
  /// 透传 [barrierDismissible] 给 [showDialog]。
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget dialog,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => dialog,
    );
  }

  /// 获取对话框的标准内边距
  static EdgeInsets get standardPadding => const EdgeInsets.all(24);

  /// 获取对话框的标准间距
  static double get standardSpacing => 16.0;

  /// 获取对话框的小间距
  static double get smallSpacing => 8.0;
}

/// [BaseStatefulDialog] 配套的 State 基类
///
/// 自动混入 [DialogCreatorsMixin],因此子类可直接调用 `buildDivider` /
/// `buildInfoCard` / `buildTitleWithIcon` 等 helper。
///
/// 默认 [build] 返回 [AlertDialog],把 [widget.buildContent] 和
/// [widget.buildActions] 嵌入标准的 [BaseDialog] 样式。子类可重写 [buildDialog]
/// 来自定义布局(或直接重写 [build])。
abstract class BaseStatefulDialogState<T extends BaseStatefulDialog>
    extends State<T> with DialogCreatorsMixin {
  /// 构建默认的 [AlertDialog]
  ///
  /// 子类可重写以使用不同的 [AlertDialog] 参数或完全不同的容器
  /// (例如 `Dialog(child: ...)`),同时仍复用 [widget] 中的样式字段。
  Widget buildDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final dialog = AlertDialog(
      title: widget.title != null ? Text(widget.title!) : null,
      content: widget.buildContent(context),
      actions: widget.buildActions(context),
      contentPadding: widget.contentPadding,
      backgroundColor: widget.backgroundColor,
      elevation: widget.elevation,
      shadowColor: widget.shadowColor ?? colorScheme.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
      ),
    );

    return widget.width != null
        ? SizedBox(width: widget.width, child: dialog)
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: dialog,
          );
  }

  @override
  Widget build(BuildContext context) => buildDialog(context);
}
import 'package:flutter/material.dart';
/// 对话框构造器 Mixin
///
/// 抽出 [BaseDialog] 与 [BaseStatefulDialog] 共享的 UI helper 实现,
/// 让无状态 ([BaseDialog]) 与有状态 ([BaseStatefulDialog]) 两种形态复用同一份代码,
/// 避免重复实现。
///
/// 这些 helper 仅依赖 [BuildContext],不依赖任何成员状态,因此可以同时混入
/// `StatelessWidget` 和 `StatefulWidget` 的子类。
mixin DialogCreatorsMixin {

  /// 构建带图标的标题
  ///
  /// 用于创建带图标的对话框标题
  ///
  /// [icon] 标题图标
  /// [title] 标题文本
  /// [color] 图标颜色（null表示使用主题色）
  Widget buildTitleWithIcon({
    required BuildContext context,
    required IconData icon,
    required String title,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          color: color ?? colorScheme.primary,
          size: 24,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

/// 基础对话框抽象类
///
/// 提供统一的对话框样式、动画和行为规范。
/// 所有自定义对话框都应继承此类以保持UI一致性。
///
/// 功能特性：
/// - 统一的Material Design 3风格
/// - 可配置的动画效果
/// - 统一的圆角和阴影
/// - 自动处理状态栏颜色
/// - 支持安全区域
///
/// 对于需要在内部管理状态(如 [TextEditingController])的对话框,
/// 请改用 [BaseStatefulDialog]。
///
/// 示例:
/// ```dart
/// class MyCustomDialog extends BaseDialog {
///   @override
///   Widget buildContent(BuildContext context) {
///     return Column(
///       mainAxisSize: MainAxisSize.min,
///       children: [
///         Text('自定义内容'),
///       ],
///     );
///   }
/// }
/// ```
abstract class BaseDialog extends StatelessWidget
    with DialogCreatorsMixin {
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

  const BaseDialog({
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 构建对话框主体
    final dialog = AlertDialog(
      title: title != null ? Text(title!) : null,
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

    // 应用宽度约束
    final constrainedDialog = width != null
        ? SizedBox(width: width, child: dialog)
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: dialog,
          );

    return constrainedDialog;
  }

  // buildTitleWithIcon
  // 已抽到 DialogCreatorsMixin 共享实现,本类与 BaseStatefulDialog 都自动继承。
}

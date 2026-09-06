import 'package:flutter/material.dart';

/// 对话框动画配置
///
/// 定义对话框的进入和退出动画效果
class DialogAnimationConfig {
  /// 动画持续时间
  final Duration duration;

  /// 进入动画曲线
  final Curve curveIn;

  /// 退出动画曲线
  final Curve curveOut;

  /// 是否使用缩放动画
  final bool useScale;

  /// 缩放起始值
  final double scaleBegin;

  /// 缩放结束值
  final double scaleEnd;

  /// 是否使用淡入淡出
  final bool useFade;

  const DialogAnimationConfig({
    this.duration = const Duration(milliseconds: 200),
    this.curveIn = Curves.easeOutCubic,
    this.curveOut = Curves.easeInCubic,
    this.useScale = true,
    this.scaleBegin = 0.8,
    this.scaleEnd = 1.0,
    this.useFade = true,
  });

  /// 默认配置
  static const defaultConfig = DialogAnimationConfig();

  /// 快速动画配置
  static const fastConfig = DialogAnimationConfig(
    duration: Duration(milliseconds: 150),
  );

  /// 慢速动画配置
  static const slowConfig = DialogAnimationConfig(
    duration: Duration(milliseconds: 300),
  );

  /// 无动画配置
  static const noneConfig = DialogAnimationConfig(
    duration: Duration.zero,
    useScale: false,
    useFade: false,
  );
}

/// 对话框构造器 Mixin
///
/// 抽出 [BaseDialog] 与 [BaseStatefulDialog] 共享的 UI helper 实现,
/// 让无状态 ([BaseDialog]) 与有状态 ([BaseStatefulDialog]) 两种形态复用同一份代码,
/// 避免重复实现。
///
/// 这些 helper 仅依赖 [BuildContext],不依赖任何成员状态,因此可以同时混入
/// `StatelessWidget` 和 `StatefulWidget` 的子类。
mixin DialogCreatorsMixin {
  /// 构建分隔线
  ///
  /// 用于在对话框内容中创建视觉分隔
  Widget buildDivider(BuildContext context) {
    final theme = Theme.of(context);
    return Divider(
      height: 1,
      thickness: 1,
      color: theme.colorScheme.outlineVariant,
    );
  }

  /// 构建信息提示卡片
  ///
  /// 用于显示提示信息或警告信息
  ///
  /// [message] 提示信息内容
  /// [type] 提示类型（info、warning、error、success）
  /// [icon] 自定义图标（可选）
  Widget buildInfoCard({
    required BuildContext context,
    required String message,
    InfoCardType type = InfoCardType.info,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 根据类型确定颜色和图标
    Color backgroundColor;
    Color borderColor;
    Color textColor;
    IconData defaultIcon;

    switch (type) {
      case InfoCardType.info:
        backgroundColor = colorScheme.primary.withValues(alpha: 0.08);
        borderColor = colorScheme.primary.withValues(alpha: 0.3);
        textColor = colorScheme.primary;
        defaultIcon = Icons.info_outline;
        break;
      case InfoCardType.warning:
        backgroundColor = colorScheme.error.withValues(alpha: 0.08);
        borderColor = colorScheme.error.withValues(alpha: 0.3);
        textColor = colorScheme.error;
        defaultIcon = Icons.warning_amber;
        break;
      case InfoCardType.error:
        backgroundColor = colorScheme.error.withValues(alpha: 0.1);
        borderColor = colorScheme.error.withValues(alpha: 0.4);
        textColor = colorScheme.error;
        defaultIcon = Icons.error_outline;
        break;
      case InfoCardType.success:
        backgroundColor = colorScheme.primary.withValues(alpha: 0.1);
        borderColor = colorScheme.primary.withValues(alpha: 0.3);
        textColor = colorScheme.primary;
        defaultIcon = Icons.check_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? defaultIcon,
            size: 18,
            color: textColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: textColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }

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

  /// 对话框动画配置
  final DialogAnimationConfig animationConfig;

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
    this.animationConfig = DialogAnimationConfig.defaultConfig,
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
  /// [context] 上下文
  /// [animationConfig] 自定义动画配置（覆盖对话框默认配置）
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget dialog,
    DialogAnimationConfig? animationConfig,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => dialog,
    );
  }

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

  /// 获取对话框的标准内边距
  ///
  /// 返回符合Material Design 3规范的内边距
  static EdgeInsets get standardPadding => const EdgeInsets.all(24);

  /// 获取对话框的标准间距
  ///
  /// 返回对话框元素之间的标准间距
  static double get standardSpacing => 16.0;

  /// 获取对话框的小间距
  ///
  /// 返回相关元素之间的小间距
  static double get smallSpacing => 8.0;

  // buildDivider / buildInfoCard / buildTitleWithIcon
  // 已抽到 DialogCreatorsMixin 共享实现,本类与 BaseStatefulDialog 都自动继承。
}

/// 信息卡片类型枚举
enum InfoCardType {
  /// 信息提示
  info,

  /// 警告提示
  warning,

  /// 错误提示
  error,

  /// 成功提示
  success,
}

/// 应用自定义颜色主题扩展
///
/// 通过 [ThemeData.extensions] 注入到主题中，提供品牌色、语义色等
/// Material 3 [ColorScheme] 之外的扩展颜色。
///
/// 使用方式：
/// ```dart
/// final colors = context.appColors; // BuildContext 扩展
/// Container(color: colors.agentAccent);
/// ```
library;

import 'package:flutter/material.dart';

/// 应用自定义颜色主题扩展
@immutable
class AppColors extends ThemeExtension<AppColors> {
  // ─── Agent 品牌色 ────────────────────────────────────────────
  /// Agent 主强调色（琥珀）。浮动按钮渐变收尾借用 [chatButtonPrimary]，
  /// 不再单独定义渐变起止色。
  final Color agentAccent;

  /// Agent 头部主文字/图标色
  final Color agentOnBrand;

  /// Agent 头部次要图标色
  final Color agentOnBrandMuted;

  // ─── 语义色（Toast/状态）─────────────────────────────────────
  final Color success;
  final Color error;
  final Color warning;
  final Color info;
  final Color neutral;

  /// 语义色上的文字色
  final Color onSemantic;

  // ─── 语义容器色（卡片背景/边框/次级文字）───────────────────────
  /// 错误容器背景（替代 Colors.red.shade50）
  final Color errorContainer;

  /// 错误容器上的文字/图标（替代 Colors.red.shade700）
  final Color onErrorContainer;

  /// 成功容器背景（替代 Colors.green.shade50）
  final Color successContainer;

  /// 成功容器上的文字/图标（替代 Colors.green.shade700）
  final Color onSuccessContainer;

  /// 警告容器背景（替代 Colors.orange.shade50）
  final Color warningContainer;

  /// 警告容器上的文字/图标（替代 Colors.orange.shade700）
  final Color onWarningContainer;

  /// 信息容器背景（替代 Colors.blue.shade50）
  final Color infoContainer;

  /// 信息容器上的文字/图标（替代 Colors.blue.shade700）
  final Color onInfoContainer;

  // ─── Gallery ──────────────────────────────────────────────────
  /// Gallery 深色背景上的纯白文字/图标
  final Color galleryOnDark;

  // ─── 聊天色系 ──────────────────────────────────────────────
  /// 聊天输入框背景米色（比 [paper] 深一档，视觉聚焦输入区）。
  /// chat 语义专属，阅读风体系无对应。
  final Color chatInputBackground;

  /// 聊天输入框 hint / 次要弱对比文字色。hint 该弱一点，不与 [inkSoft] 合并。
  /// chat 语义专属。
  final Color chatHintText;

  /// 聊天发送按钮主色 / 笔盒强调 / Agent 品牌渐变收尾
  final Color chatButtonPrimary;

  // ─── 阅读风语义色（纸感容器/墨字/分割线）──────────────────────
  /// 卡片纸张色（浅色暖白纸 / 深色炭纸）
  final Color paper;

  /// 主墨字色（标题/强文字 / 聊天主文字）
  final Color ink;

  /// 柔墨灰（正文/次要文字）
  final Color inkSoft;

  /// 分割线 / 边线
  final Color divider;

  // ─── 其他 ─────────────────────────────────────────────────────
  /// 头像/沉浸式半透明阴影（30% 黑）
  final Color avatarShadow;

  const AppColors({
    required this.agentAccent,
    required this.agentOnBrand,
    required this.agentOnBrandMuted,
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    required this.neutral,
    required this.onSemantic,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.galleryOnDark,
    required this.chatInputBackground,
    required this.chatHintText,
    required this.chatButtonPrimary,
    required this.paper,
    required this.ink,
    required this.inkSoft,
    required this.divider,
    required this.avatarShadow,
  });

  /// 亮色主题配色 · 晨读书馆
  ///
  /// 暖白纸底 + 墨色字 + 琥珀强调，护眼且有书卷气。
  /// 业务色（关系图/性别/Agent 品牌）与暗色保持一致，不随主题变化。
  static const AppColors light = AppColors(
    // Agent 品牌色 · 琥珀系（与晨读书馆暖纸主题一致）。
    agentAccent: Color(0xFF8C5A1F),
    agentOnBrand: Colors.white,
    agentOnBrandMuted: Colors.white70,
    success: Color(0xFF5E7A3C),
    error: Color(0xFFB23A2E),
    warning: Color(0xFFB8732A),
    // info 比 neutral(debug 灰)深一档，保持日志 INFO/debug 区分；
    // 走暖中性灰系，不再用冷蓝。
    info: Color(0xFF4A4034),
    neutral: Color(0xFF6B5D48),
    onSemantic: Colors.white,
    // 容器色 · 米白纸感
    errorContainer: Color(0xFFF3DAD5),
    onErrorContainer: Color(0xFF5C1A12),
    successContainer: Color(0xFFE0E8CF),
    onSuccessContainer: Color(0xFF2A3A14),
    warningContainer: Color(0xFFF3E2C5),
    onWarningContainer: Color(0xFF4A2E08),
    infoContainer: Color(0xFFE8E0D0),
    onInfoContainer: Color(0xFF3A3024),
    galleryOnDark: Color(0xFFFFFFFF),
    // 聊天 · 暖纸色系
    chatInputBackground: Color(0xFFEBE3D2),
    chatHintText: Color(0xFF9C8A6E),
    chatButtonPrimary: Color(0xFFB8843A),
    // 阅读风语义色 · 晨读书馆
    paper: Color(0xFFFFFDF8),
    ink: Color(0xFF2B2620),
    inkSoft: Color(0xFF6B6358),
    divider: Color(0xFFE5DDCC),
    avatarShadow: Color(0x2A000000),
  );

  /// 暗色主题配色 · 暗夜书馆
  ///
  /// 深炭黑底 + 羊皮纸字 + 琥珀暖光，沉浸夜读。
  static const AppColors dark = AppColors(
    // Agent 品牌色 · 琥珀系（与暗夜书馆暖纸主题一致）。
    agentAccent: Color(0xFFB8843A),
    agentOnBrand: Colors.white,
    agentOnBrandMuted: Colors.white70,
    success: Color(0xFF7A9A55),
    error: Color(0xFFD9685A),
    warning: Color(0xFFE0A050),
    // info 比 neutral(debug 灰)亮一档，走暖中性灰系。
    info: Color(0xFFB0A282),
    neutral: Color(0xFF8A7C66),
    onSemantic: Color(0xFF1A1610),
    // 容器色 · 深炭低饱和
    errorContainer: Color(0xFF4A1A14),
    onErrorContainer: Color(0xFFF3DAD5),
    successContainer: Color(0xFF2A3A14),
    onSuccessContainer: Color(0xFFE0E8CF),
    warningContainer: Color(0xFF4A2E08),
    onWarningContainer: Color(0xFFF3E2C5),
    infoContainer: Color(0xFF342D22),
    onInfoContainer: Color(0xFFECE3D0),
    galleryOnDark: Color(0xFFFFFFFF),
    // 聊天 · 深炭羊皮纸系
    chatInputBackground: Color(0xFF241F16),
    chatHintText: Color(0xFF7A6B52),
    chatButtonPrimary: Color(0xFFD9A05B),
    // 阅读风语义色 · 暗夜书馆
    paper: Color(0xFF241F16),
    ink: Color(0xFFE8DCC4),
    inkSoft: Color(0xFFB5A482),
    divider: Color(0xFF3A3128),
    avatarShadow: Color(0x4D000000),
  );

  @override
  AppColors copyWith({
    Color? agentAccent,
    Color? agentOnBrand,
    Color? agentOnBrandMuted,
    Color? success,
    Color? error,
    Color? warning,
    Color? info,
    Color? neutral,
    Color? onSemantic,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? galleryOnDark,
    Color? chatInputBackground,
    Color? chatHintText,
    Color? chatButtonPrimary,
    Color? paper,
    Color? ink,
    Color? inkSoft,
    Color? divider,
    Color? avatarShadow,
  }) {
    return AppColors(
      agentAccent: agentAccent ?? this.agentAccent,
      agentOnBrand: agentOnBrand ?? this.agentOnBrand,
      agentOnBrandMuted: agentOnBrandMuted ?? this.agentOnBrandMuted,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      onSemantic: onSemantic ?? this.onSemantic,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      galleryOnDark: galleryOnDark ?? this.galleryOnDark,
      chatInputBackground: chatInputBackground ?? this.chatInputBackground,
      chatHintText: chatHintText ?? this.chatHintText,
      chatButtonPrimary: chatButtonPrimary ?? this.chatButtonPrimary,
      paper: paper ?? this.paper,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      divider: divider ?? this.divider,
      avatarShadow: avatarShadow ?? this.avatarShadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      agentAccent: Color.lerp(agentAccent, other.agentAccent, t)!,
      agentOnBrand: Color.lerp(agentOnBrand, other.agentOnBrand, t)!,
      agentOnBrandMuted:
          Color.lerp(agentOnBrandMuted, other.agentOnBrandMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      onSemantic: Color.lerp(onSemantic, other.onSemantic, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer:
          Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      galleryOnDark: Color.lerp(galleryOnDark, other.galleryOnDark, t)!,
      chatInputBackground:
          Color.lerp(chatInputBackground, other.chatInputBackground, t)!,
      chatHintText: Color.lerp(chatHintText, other.chatHintText, t)!,
      chatButtonPrimary:
          Color.lerp(chatButtonPrimary, other.chatButtonPrimary, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      avatarShadow: Color.lerp(avatarShadow, other.avatarShadow, t)!,
    );
  }
}

/// 便捷访问 [AppColors] 的 [BuildContext] 扩展
///
/// 当 [ThemeData] 未注入 [AppColors] 时（如 loading 兜底分支），
/// 兜底返回 [AppColors.dark] 保持行为稳定。
extension AppColorsX on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}

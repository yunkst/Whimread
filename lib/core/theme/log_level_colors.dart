/// 日志级别/分类配色工具
///
/// 集中管理日志相关颜色，消除 `log_viewer_screen.dart` 与
/// `log_report_settings_screen.dart` 中重复的 `_getLevelColor` / `_levelColor`。
///
/// - **级别色（debug/info/warning/error）**：映射到 [AppColors] 的语义色，
///   随主题明暗变化。
/// - **分类色（database/network/ai/ui/cache/character/backup/general）**：
///   属于"业务数据调色板"（用于区分日志分类，类似关系图节点色），
///   暂保留固定色调以维持识别度，后续如需主题化可扩展 [AppColors]。
library;

import 'package:flutter/material.dart';

import '../../services/logger_service.dart';
import 'app_colors.dart';

/// 日志级别配色
class LogLevelColors {
  LogLevelColors._();

  /// 根据日志级别返回语义色
  ///
  /// - debug → [AppColors.neutral]（灰色）
  /// - info → [AppColors.info]（蓝）
  /// - warning → [AppColors.warning]（橙）
  /// - error → [AppColors.error]（红）
  static Color levelColor(LogLevel level, AppColors appColors) {
    switch (level) {
      case LogLevel.debug:
        return appColors.neutral;
      case LogLevel.info:
        return appColors.info;
      case LogLevel.warning:
        return appColors.warning;
      case LogLevel.error:
        return appColors.error;
    }
  }

  /// 根据日志分类返回区分色（业务调色板，固定色调）
  static Color categoryColor(LogCategory category) {
    switch (category) {
      case LogCategory.database:
        return Colors.purple;
      case LogCategory.network:
        return Colors.cyan;
      case LogCategory.ai:
        return Colors.deepOrange;
      case LogCategory.ui:
        return Colors.green;
      case LogCategory.cache:
        return Colors.orange;
      case LogCategory.character:
        return Colors.pink;
      case LogCategory.backup:
        return Colors.indigo;
      case LogCategory.general:
        return const Color(0xFF9E9E9E);
    }
  }
}

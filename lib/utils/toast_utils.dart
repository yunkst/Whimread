import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../core/theme/app_colors.dart';

/// Toast提示工具类
///
/// 通过 [setThemeColors] 注入当前 [AppColors]（在 `main.dart` 启动时
/// 与 [ThemeState] 同步），所有 showXxx() 方法可基于缓存或调用方
/// `context` 解析主题感知颜色。无 context 的旧调用点保持兼容。
class ToastUtils {
  /// 当前主题扩展缓存（默认 dark 兜底）
  static AppColors _cached = AppColors.dark;

  /// 注入当前主题扩展
  ///
  /// 通常在 [MaterialApp] 重建时调用，使 [Fluttertoast]（系统级 UI）
  /// 能反映当前主题。
  static void setThemeColors(AppColors colors) {
    _cached = colors;
  }

  /// 显示成功提示
  static void showSuccess(
    String message, {
    BuildContext? context,
    Duration? duration,
  }) {
    _showToast(
      message,
      backgroundColor: _resolveColor(context, (c) => c.success, Colors.green),
      duration: duration,
    );
  }

  /// 显示错误提示
  static void showError(
    String message, {
    BuildContext? context,
    Duration? duration,
  }) {
    _showToast(
      message,
      backgroundColor: _resolveColor(context, (c) => c.error, Colors.red),
      duration: duration,
    );
  }

  /// 显示警告提示
  static void showWarning(
    String message, {
    BuildContext? context,
    Duration? duration,
  }) {
    _showToast(
      message,
      backgroundColor:
          _resolveColor(context, (c) => c.warning, Colors.orange),
      duration: duration,
    );
  }

  /// 显示信息提示
  static void showInfo(
    String message, {
    BuildContext? context,
    Duration? duration,
  }) {
    _showToast(
      message,
      backgroundColor: _resolveColor(context, (c) => c.info, Colors.blue),
      duration: duration,
    );
  }

  /// 显示普通提示（默认灰色）
  static void show(
    String message, {
    BuildContext? context,
    Color? backgroundColor,
    Duration? duration,
  }) {
    _showToast(
      message,
      backgroundColor: backgroundColor ??
          _resolveColor(
              context, (c) => c.neutral, const Color(0xFF616161)),
      duration: duration,
    );
  }

  /// 解析主题感知颜色
  ///
  /// 优先级：调用方 context > 缓存 _cached > fallback
  static Color _resolveColor(
    BuildContext? context,
    Color Function(AppColors) selector,
    Color fallback,
  ) {
    if (context != null && context.mounted) {
      try {
        return selector(context.appColors);
      } catch (_) {
        // 主题未注入时静默回退
      }
    }
    try {
      return selector(_cached);
    } catch (_) {
      return fallback;
    }
  }

  /// 私有方法：显示toast（使用FlutterToast插件）
  static void _showToast(
    String message, {
    required Color backgroundColor,
    Duration? duration,
  }) {
    final toastLength =
        duration != null && (duration.inSeconds >= 3 || duration.inMinutes >= 1)
            ? Toast.LENGTH_LONG
            : Toast.LENGTH_SHORT;

    Fluttertoast.showToast(
      msg: message,
      toastLength: toastLength,
      gravity: ToastGravity.TOP,
      backgroundColor: backgroundColor,
      textColor: _cached.onSemantic,
      fontSize: 16.0,
    );
  }
}

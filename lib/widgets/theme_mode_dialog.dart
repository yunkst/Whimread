import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/theme_provider.dart';

/// ThemeModeDialog - 主题模式选择对话框
///
/// 从阅读页等场景快速切换应用全局主题（亮色/暗色/跟随系统），
/// 与设置页使用同一个 ThemeNotifier，选择后全局生效并持久化。
class ThemeModeDialog extends ConsumerWidget {
  const ThemeModeDialog({super.key});

  /// 便捷打开入口
  static Future<void> show(BuildContext context, WidgetRef ref) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ThemeModeDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(themeNotifierProvider).valueOrNull?.themeMode ??
            AppThemeMode.system;

    return AlertDialog(
      title: const Text('选择主题模式'),
      content: RadioGroup<AppThemeMode>(
        groupValue: themeMode,
        onChanged: (AppThemeMode? value) {
          if (value != null) {
            ref.read(themeNotifierProvider.notifier).setThemeMode(value);
            Navigator.pop(context);
          }
        },
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AppThemeMode>(
              title: Text('亮色模式'),
              subtitle: Text('使用浅色主题'),
              secondary: Icon(Icons.light_mode_outlined),
              value: AppThemeMode.light,
            ),
            RadioListTile<AppThemeMode>(
              title: Text('暗色模式'),
              subtitle: Text('使用深色主题'),
              secondary: Icon(Icons.dark_mode_outlined),
              value: AppThemeMode.dark,
            ),
            RadioListTile<AppThemeMode>(
              title: Text('跟随系统'),
              subtitle: Text('跟随系统设置自动切换'),
              secondary: Icon(Icons.brightness_auto_outlined),
              value: AppThemeMode.system,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

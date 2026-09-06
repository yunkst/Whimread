/// GitHub Star 引导服务。
///
/// 管理 4 个 SharedPreferences key，控制启动时的 star 弹窗门槛与冷却：
/// - `star_prompt_install_time` (int ms 时间戳) 首次启动记录
/// - `star_prompt_launch_count` (int) 启动次数计数
/// - `star_prompt_dismissed` (bool) true = 永久不再弹（主按钮触发）
/// - `star_prompt_next_show_time` (int ms 时间戳) 下次允许弹窗时间（关闭按钮写）
///
/// 单例（仿 [NativeCrashReporter]），用 [PreferencesService.instance] 持久化。
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'preferences_service.dart';

class StarPromptService {
  StarPromptService._();

  static final StarPromptService instance = StarPromptService._();

  // preferences key（spec 固定字面值，不改）
  static const String _kInstallTime = 'star_prompt_install_time';
  static const String _kLaunchCount = 'star_prompt_launch_count';
  static const String _kDismissed = 'star_prompt_dismissed';
  static const String _kNextShowTime = 'star_prompt_next_show_time';

  // 门槛常量（spec 固定字面值，不改）
  static const int _launchThreshold = 7;
  static const int _installDaysThreshold = 3;
  static const int _cooldownDays = 7;
  static const int _msPerDay = 86400000;

  /// 测试用：清全部 4 个 key + 重新初始化。
  Future<void> resetForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kInstallTime);
    await prefs.remove(_kLaunchCount);
    await prefs.remove(_kDismissed);
    await prefs.remove(_kNextShowTime);
  }

  /// 启动时调用：首次写 install_time + count=1；非首次 count++。
  Future<void> recordLaunch() async {
    final prefs = await PreferencesService.instance.getInstance();
    final hasInstallTime = prefs.containsKey(_kInstallTime);
    if (!hasInstallTime) {
      await PreferencesService.instance.setInt(
        _kInstallTime,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    final current = await PreferencesService.instance.getInt(_kLaunchCount);
    await PreferencesService.instance.setInt(_kLaunchCount, current + 1);
  }

  /// 是否应该弹窗（四门槛全满足）。
  ///
  /// 1. dismissed != true
  /// 2. launch_count >= 7
  /// 3. now - install_time >= 3 天
  /// 4. now >= next_show_time
  Future<bool> shouldShow() async {
    try {
      final dismissed =
          await PreferencesService.instance.getBool(_kDismissed);
      if (dismissed) return false;

      final count = await PreferencesService.instance.getInt(_kLaunchCount);
      if (count < _launchThreshold) return false;

      final installTime =
          await PreferencesService.instance.getInt(_kInstallTime);
      if (installTime == 0) return false;
      final daysSinceInstall =
          (DateTime.now().millisecondsSinceEpoch - installTime) ~/ _msPerDay;
      if (daysSinceInstall < _installDaysThreshold) return false;

      final nextShowTime =
          await PreferencesService.instance.getInt(_kNextShowTime);
      if (DateTime.now().millisecondsSinceEpoch < nextShowTime) return false;

      return true;
    } catch (_) {
      // 任何异常默认不弹，绝不阻塞启动。
      return false;
    }
  }

  /// 主按钮「⭐ 去 GitHub 点 Star」触发：标记永久关闭。
  ///
  /// 调用方负责 launchUrl（service 不依赖 url_launcher，方便单测）。
  Future<void> onStarClicked() async {
    await PreferencesService.instance.setBool(_kDismissed, true);
  }

  /// 关闭按钮触发：写冷却期，下次可弹时间 = now + 7 天。
  Future<void> onDismissed() async {
    final nextShow =
        DateTime.now().millisecondsSinceEpoch + _cooldownDays * _msPerDay;
    await PreferencesService.instance.setInt(_kNextShowTime, nextShow);
  }
}

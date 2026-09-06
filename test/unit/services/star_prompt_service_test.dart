import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_app/services/star_prompt_service.dart';
import 'package:novel_app/services/preferences_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StarPromptService.instance.resetForTest();
  });

  test('recordLaunch 首次启动写入 install_time + count=1', () async {
    final beforeMs = DateTime.now().millisecondsSinceEpoch;
    await StarPromptService.instance.recordLaunch();
    final afterMs = DateTime.now().millisecondsSinceEpoch;

    final installTime = await PreferencesService.instance.getInt(
      'star_prompt_install_time',
    );
    final count = await PreferencesService.instance.getInt(
      'star_prompt_launch_count',
    );

    expect(installTime, greaterThanOrEqualTo(beforeMs));
    expect(installTime, lessThanOrEqualTo(afterMs));
    expect(count, 1);
  });

  test('recordLaunch 非首次启动 count 累加 + install_time 不变', () async {
    // 模拟已有状态：install_time 是昨天，count=3
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'star_prompt_install_time': yesterday,
      'star_prompt_launch_count': 3,
    });

    await StarPromptService.instance.recordLaunch();

    final installTime = await PreferencesService.instance.getInt(
      'star_prompt_install_time',
    );
    final count = await PreferencesService.instance.getInt(
      'star_prompt_launch_count',
    );

    expect(installTime, yesterday);
    expect(count, 4);
  });

  group('shouldShow 四门槛判定', () {
    /// 辅助：构造「四门槛全满足」的初始 prefs（now=基准时间，count=7，install=4天前，无 dismiss，无 next_show）
    Future<void> setupAllMet() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'star_prompt_install_time': now - 4 * 86400000,
        'star_prompt_launch_count': 7,
        'star_prompt_dismissed': false,
        'star_prompt_next_show_time': 0,
      });
    }

    test('门槛 1: launch_count < 7 → false', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'star_prompt_install_time': now - 4 * 86400000,
        'star_prompt_launch_count': 6,
      });

      expect(await StarPromptService.instance.shouldShow(), isFalse);
    });

    test('门槛 2: install_time 距今 < 3 天 → false', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'star_prompt_install_time': now - 2 * 86400000,
        'star_prompt_launch_count': 7,
      });

      expect(await StarPromptService.instance.shouldShow(), isFalse);
    });

    test('门槛 3: dismissed = true → false（永久关闭）', () async {
      await setupAllMet();
      await PreferencesService.instance.setBool('star_prompt_dismissed', true);

      expect(await StarPromptService.instance.shouldShow(), isFalse);
    });

    test('门槛 4: now < next_show_time → false（关闭冷却期内）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'star_prompt_install_time': now - 4 * 86400000,
        'star_prompt_launch_count': 7,
        'star_prompt_dismissed': false,
        'star_prompt_next_show_time': now + 5 * 86400000, // 5 天后
      });

      expect(await StarPromptService.instance.shouldShow(), isFalse);
    });

    test('四门槛全满足 → true', () async {
      await setupAllMet();

      expect(await StarPromptService.instance.shouldShow(), isTrue);
    });
  });

  test('onStarClicked 写 dismissed=true', () async {
    final beforeMs = DateTime.now().millisecondsSinceEpoch;
    await StarPromptService.instance.onStarClicked();

    final dismissed = await PreferencesService.instance.getBool(
      'star_prompt_dismissed',
    );
    expect(dismissed, isTrue);

    // 验证后续 shouldShow 永远 false（即使其他条件满足）
    SharedPreferences.setMockInitialValues({
      'star_prompt_install_time': beforeMs - 4 * 86400000,
      'star_prompt_launch_count': 7,
      'star_prompt_dismissed': true,
      'star_prompt_next_show_time': 0,
    });
    expect(await StarPromptService.instance.shouldShow(), isFalse);
  });

  test('onDismissed 写 next_show_time = now + 7 天，冷却期内不弹，7 天后恢复', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await StarPromptService.instance.onDismissed();

    final nextShow = await PreferencesService.instance.getInt(
      'star_prompt_next_show_time',
    );
    final sevenDaysLater = now + 7 * 86400000;
    // 允许 ±1000ms 时序误差
    expect(nextShow, greaterThanOrEqualTo(sevenDaysLater - 1000));
    expect(nextShow, lessThanOrEqualTo(sevenDaysLater + 1000));

    // 验证冷却期内不弹
    SharedPreferences.setMockInitialValues({
      'star_prompt_install_time': now - 4 * 86400000,
      'star_prompt_launch_count': 7,
      'star_prompt_dismissed': false,
      'star_prompt_next_show_time': now + 5 * 86400000, // 5 天后到期
    });
    expect(await StarPromptService.instance.shouldShow(), isFalse);
  });
}

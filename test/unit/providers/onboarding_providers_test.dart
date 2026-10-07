import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/onboarding_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('[OnboardingNotifier] - 新手引导状态管理测试', () {
    late ProviderContainer container;

    setUp(() {
      // 每个用例使用干净的 SharedPreferences
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('首次启动：onboardingCompleted 应为 false', () async {
      // Act
      final state =
          await container.read(onboardingNotifierProvider.future);

      // Assert
      expect(state.onboardingCompleted, isFalse,
          reason: '未标记完成时，应返回 false');
    });

    test('completeOnboarding 应将 onboardingCompleted 置为 true 并持久化',
        () async {
      // Arrange - 先读取触发初始化
      await container.read(onboardingNotifierProvider.future);

      // Act
      await container
          .read(onboardingNotifierProvider.notifier)
          .completeOnboarding();

      // Assert - 内存状态
      final state = container.read(onboardingNotifierProvider).value;
      expect(state?.onboardingCompleted, isTrue);

      // Assert - 持久化
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
    });

    test('completeOnboarding 后新建容器读取应为已完成', () async {
      // Arrange - 在第一个容器中完成引导
      await container.read(onboardingNotifierProvider.future);
      await container
          .read(onboardingNotifierProvider.notifier)
          .completeOnboarding();
      container.dispose();

      // Act - 新建容器（模拟重启后从持久化加载）
      container = ProviderContainer();
      final state = await container.read(onboardingNotifierProvider.future);

      // Assert
      expect(state.onboardingCompleted, isTrue,
          reason: '完成状态应被持久化，重启后仍为 true');
    });

});
}

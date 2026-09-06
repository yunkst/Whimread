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
      expect(state.bookshelfGuideShown, isFalse);
      expect(state.searchGuideShown, isFalse);
      expect(state.readerGuideShown, isFalse);
      expect(state.chapterListGuideShown, isFalse);
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

    test('markBookshelfGuideShown 应标记对应场景并持久化', () async {
      // Arrange
      await container.read(onboardingNotifierProvider.future);

      // Act
      await container
          .read(onboardingNotifierProvider.notifier)
          .markBookshelfGuideShown();

      // Assert
      final state = container.read(onboardingNotifierProvider).value;
      expect(state?.bookshelfGuideShown, isTrue);
      expect(state?.onboardingCompleted, isFalse,
          reason: '场景标记不应影响主引导完成状态');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('guide_bookshelf_shown'), isTrue);
    });

    test('markSearchGuideShown 应标记搜索场景', () async {
      await container.read(onboardingNotifierProvider.future);
      await container
          .read(onboardingNotifierProvider.notifier)
          .markSearchGuideShown();

      final state = container.read(onboardingNotifierProvider).value;
      expect(state?.searchGuideShown, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('guide_search_shown'), isTrue);
    });

    test('markReaderGuideShown 应标记阅读器场景', () async {
      await container.read(onboardingNotifierProvider.future);
      await container
          .read(onboardingNotifierProvider.notifier)
          .markReaderGuideShown();

      final state = container.read(onboardingNotifierProvider).value;
      expect(state?.readerGuideShown, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('guide_reader_shown'), isTrue);
    });

    test('markChapterListGuideShown 应标记章节列表场景', () async {
      await container.read(onboardingNotifierProvider.future);
      await container
          .read(onboardingNotifierProvider.notifier)
          .markChapterListGuideShown();

      final state = container.read(onboardingNotifierProvider).value;
      expect(state?.chapterListGuideShown, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('guide_chapter_list_shown'), isTrue);
    });

    test('resetOnboarding 应清空所有引导标记', () async {
      // Arrange - 先标记完成和若干场景
      await container.read(onboardingNotifierProvider.future);
      await container
          .read(onboardingNotifierProvider.notifier)
          .completeOnboarding();
      await container
          .read(onboardingNotifierProvider.notifier)
          .markBookshelfGuideShown();
      await container
          .read(onboardingNotifierProvider.notifier)
          .markReaderGuideShown();

      // Act
      await container
          .read(onboardingNotifierProvider.notifier)
          .resetOnboarding();

      // Assert - 内存状态全部归零
      final state = container.read(onboardingNotifierProvider).value;
      expect(state, equals(OnboardingState.initial));

      // Assert - 持久化数据已删除
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('onboarding_completed'), isFalse);
      expect(prefs.containsKey('guide_bookshelf_shown'), isFalse);
      expect(prefs.containsKey('guide_reader_shown'), isFalse);
    });
  });
}

/// Onboarding 新手引导 Provider
///
/// 管理新手引导状态，支持首次启动向导和场景化提示。
/// 使用 SharedPreferences 持久化引导完成标记。
///
/// 使用示例：
/// ```dart
/// // 检查是否需要显示引导
/// final shouldShow = ref.watch(shouldShowOnboardingProvider);
/// if (shouldShow.value == true) { /* 显示引导页面 */ }
///
/// // 标记引导完成
/// ref.read(onboardingNotifierProvider.notifier).completeOnboarding();
///
/// // 重置引导（设置页"重新查看引导"）
/// ref.read(onboardingNotifierProvider.notifier).resetOnboarding();
/// ```
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/logger_service.dart';
import '../../services/preferences_service.dart';

part 'onboarding_providers.g.dart';

/// Onboarding 引导状态数据类
///
/// 封装各类引导的完成状态，每个场景独立管理
class OnboardingState {
  /// 首次启动向导是否已完成
  final bool onboardingCompleted;

  /// 书架引导是否已显示
  final bool bookshelfGuideShown;

  /// 搜索引导是否已显示
  final bool searchGuideShown;

  /// 阅读器引导是否已显示
  final bool readerGuideShown;

  /// 章节列表引导是否已显示
  final bool chapterListGuideShown;

  const OnboardingState({
    this.onboardingCompleted = false,
    this.bookshelfGuideShown = false,
    this.searchGuideShown = false,
    this.readerGuideShown = false,
    this.chapterListGuideShown = false,
  });

  /// 初始状态（未完成任何引导）
  static const initial = OnboardingState();

  OnboardingState copyWith({
    bool? onboardingCompleted,
    bool? bookshelfGuideShown,
    bool? searchGuideShown,
    bool? readerGuideShown,
    bool? chapterListGuideShown,
  }) {
    return OnboardingState(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      bookshelfGuideShown: bookshelfGuideShown ?? this.bookshelfGuideShown,
      searchGuideShown: searchGuideShown ?? this.searchGuideShown,
      readerGuideShown: readerGuideShown ?? this.readerGuideShown,
      chapterListGuideShown:
          chapterListGuideShown ?? this.chapterListGuideShown,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnboardingState &&
          runtimeType == other.runtimeType &&
          onboardingCompleted == other.onboardingCompleted &&
          bookshelfGuideShown == other.bookshelfGuideShown &&
          searchGuideShown == other.searchGuideShown &&
          readerGuideShown == other.readerGuideShown &&
          chapterListGuideShown == other.chapterListGuideShown;

  @override
  int get hashCode => Object.hash(
        onboardingCompleted,
        bookshelfGuideShown,
        searchGuideShown,
        readerGuideShown,
        chapterListGuideShown,
      );
}

/// Onboarding 状态管理器
///
/// **职责**:
/// - 从 SharedPreferences 加载引导完成状态
/// - 提供标记完成/重置接口
/// - 管理各场景独立的引导标记
///
/// **持久化键**:
/// - `onboarding_completed`: 首次启动向导
/// - `guide_bookshelf_shown`: 书架引导
/// - `guide_search_shown`: 搜索引导
/// - `guide_reader_shown`: 阅读器引导
/// - `guide_chapter_list_shown`: 章节列表引导
@riverpod
class OnboardingNotifier extends _$OnboardingNotifier {
  static const String _onboardingCompletedKey = 'onboarding_completed';
  static const String _bookshelfGuideKey = 'guide_bookshelf_shown';
  static const String _searchGuideKey = 'guide_search_shown';
  static const String _readerGuideKey = 'guide_reader_shown';
  static const String _chapterListGuideKey = 'guide_chapter_list_shown';

  @override
  Future<OnboardingState> build() async {
    ref.keepAlive();

    try {
      final prefs = PreferencesService.instance;

      final onboardingCompleted =
          await prefs.getBool(_onboardingCompletedKey);
      final bookshelfShown = await prefs.getBool(_bookshelfGuideKey);
      final searchShown = await prefs.getBool(_searchGuideKey);
      final readerShown = await prefs.getBool(_readerGuideKey);
      final chapterListShown = await prefs.getBool(_chapterListGuideKey);

      LoggerService.instance.i(
        'Onboarding 状态加载完成: '
        'completed=$onboardingCompleted, bookshelf=$bookshelfShown, '
        'search=$searchShown, reader=$readerShown, chapterList=$chapterListShown',
        category: LogCategory.general,
        tags: ['onboarding', 'load'],
      );

      return OnboardingState(
        onboardingCompleted: onboardingCompleted,
        bookshelfGuideShown: bookshelfShown,
        searchGuideShown: searchShown,
        readerGuideShown: readerShown,
        chapterListGuideShown: chapterListShown,
      );
    } catch (e, st) {
      LoggerService.instance.e(
        '加载 Onboarding 状态失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.general,
        tags: ['onboarding', 'load', 'error'],
      );
      return OnboardingState.initial;
    }
  }

  /// 标记首次启动向导已完成
  Future<void> completeOnboarding() async {
    try {
      final prefs = PreferencesService.instance;
      await prefs.setBool(_onboardingCompletedKey, true);

      final current = await future;
      state = AsyncData(current.copyWith(onboardingCompleted: true));

      LoggerService.instance.i(
        '新手引导已完成',
        category: LogCategory.general,
        tags: ['onboarding', 'complete'],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        '保存引导完成状态失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.general,
        tags: ['onboarding', 'save', 'error'],
      );
    }
  }

  /// 标记书架引导已显示
  Future<void> markBookshelfGuideShown() async {
    await _setGuideFlag(_bookshelfGuideKey, 'bookshelfGuideShown');
  }

  /// 标记搜索引导已显示
  Future<void> markSearchGuideShown() async {
    await _setGuideFlag(_searchGuideKey, 'searchGuideShown');
  }

  /// 标记阅读器引导已显示
  Future<void> markReaderGuideShown() async {
    await _setGuideFlag(_readerGuideKey, 'readerGuideShown');
  }

  /// 标记章节列表引导已显示
  Future<void> markChapterListGuideShown() async {
    await _setGuideFlag(_chapterListGuideKey, 'chapterListGuideShown');
  }

  /// 重置所有引导标记（用于"重新查看引导"）
  ///
  /// 清空所有持久化数据，恢复初始状态
  Future<void> resetOnboarding() async {
    try {
      final prefs = PreferencesService.instance;
      await Future.wait([
        prefs.remove(_onboardingCompletedKey),
        prefs.remove(_bookshelfGuideKey),
        prefs.remove(_searchGuideKey),
        prefs.remove(_readerGuideKey),
        prefs.remove(_chapterListGuideKey),
      ]);

      state = AsyncData(OnboardingState.initial);

      LoggerService.instance.i(
        'Onboarding 状态已重置',
        category: LogCategory.general,
        tags: ['onboarding', 'reset'],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        '重置 Onboarding 状态失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.general,
        tags: ['onboarding', 'reset', 'error'],
      );
    }
  }

  /// 设置单个引导标记
  Future<void> _setGuideFlag(String key, String fieldName) async {
    try {
      final prefs = PreferencesService.instance;
      await prefs.setBool(key, true);

      final current = await future;
      final newState = switch (fieldName) {
        'bookshelfGuideShown' =>
          current.copyWith(bookshelfGuideShown: true),
        'searchGuideShown' => current.copyWith(searchGuideShown: true),
        'readerGuideShown' => current.copyWith(readerGuideShown: true),
        'chapterListGuideShown' =>
          current.copyWith(chapterListGuideShown: true),
        _ => current,
      };
      state = AsyncData(newState);

      LoggerService.instance.d(
        '引导标记已设置: $fieldName',
        category: LogCategory.general,
        tags: ['onboarding', 'mark', fieldName],
      );
    } catch (e, st) {
      LoggerService.instance.e(
        '设置引导标记失败: $fieldName, $e',
        stackTrace: st.toString(),
        category: LogCategory.general,
        tags: ['onboarding', 'mark', fieldName, 'error'],
      );
    }
  }
}

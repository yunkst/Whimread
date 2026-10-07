/// Riverpod Reader State Providers
///
/// 细粒度的阅读器状态管理Provider
/// 用于替代Controller的setState回调，实现选择性Widget重建
///
/// 设计原则：
/// 1. 每个Provider只管理一个明确的状态领域
/// 2. 状态更新只影响监听该Provider的Widget
/// 3. 避免全屏setState导致的性能问题
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../models/novel.dart';
import '../../models/chapter.dart';

part 'reader_state_providers.g.dart';

/// ChapterContentState
///
/// 章节内容加载状态
class ChapterContentState {
  final String content;
  final bool isLoading;
  final String errorMessage;
  final Chapter? currentChapter;
  final Novel? currentNovel;

  const ChapterContentState({
    this.content = '',
    this.isLoading = false,
    this.errorMessage = '',
    this.currentChapter,
    this.currentNovel,
  });

  ChapterContentState copyWith({
    String? content,
    bool? isLoading,
    String? errorMessage,
    Chapter? currentChapter,
    Novel? currentNovel,
    bool clearCurrentChapter = false,
    bool clearCurrentNovel = false,
  }) {
    return ChapterContentState(
      content: content ?? this.content,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      currentChapter:
          clearCurrentChapter ? null : (currentChapter ?? this.currentChapter),
      currentNovel:
          clearCurrentNovel ? null : (currentNovel ?? this.currentNovel),
    );
  }
}

/// ChapterContentStateNotifier
///
/// 管理章节内容的加载状态
@riverpod
class ChapterContentStateNotifier extends _$ChapterContentStateNotifier {
  @override
  ChapterContentState build() {
    return const ChapterContentState();
  }

  /// 设置加载状态
  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  /// 设置内容
  void setContent(String content) {
    state = state.copyWith(content: content);
  }

  /// 加载世代：每次「切换到新章节上下文」自增。
  ///
  /// 抓取是秒级异步：loadChapter 发起的旧章抓取可能晚于切章落地，若无条件
  /// setContent 就把旧内容写进新章状态（B 标题下显示 A 正文）。所有异步
  /// 回写经 [finishLoad] / [failLoad] 按世代校验，过期世代直接丢弃。
  int _loadGeneration = 0;

  /// 设置当前章节和小说，同时开启新世代；返回本次世代号。
  ///
  /// 调用方（loadChapter）需持有返回值，在 await 之后回写状态前校验。
  int setCurrentContext(Chapter chapter, Novel novel) {
    _loadGeneration++;
    state = state.copyWith(currentChapter: chapter, currentNovel: novel);
    return _loadGeneration;
  }

  /// 抓取成功回写：世代已过期（期间切了章）则丢弃并返回 false。
  bool finishLoad(int generation, String content) {
    if (generation != _loadGeneration) return false;
    state = state.copyWith(content: content, isLoading: false);
    return true;
  }

  /// 抓取失败回写：世代已过期则丢弃并返回 false（不覆盖新章的错误态）。
  bool failLoad(int generation, String message) {
    if (generation != _loadGeneration) return false;
    state = state.copyWith(errorMessage: message, isLoading: false);
    return true;
  }

  /// 设置错误信息
  void setError(String error) {
    state = state.copyWith(errorMessage: error, isLoading: false);
  }

  /// 清空内容（用于章节切换）
  void clearContent() {
    state = state.copyWith(content: '');
  }

  /// 清空所有状态
  void clear() {
    state = const ChapterContentState();
  }

  /// 更新内容（用于改写等场景）
  void updateContent(String newContent) {
    state = state.copyWith(content: newContent);
  }
}

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/providers/chapter_list_providers.dart';
import 'package:novel_app/models/chapter.dart';

/// [ChapterListState] 单元测试
///
/// 测试章节列表状态管理功能：
/// - ChapterListState 初始化和 copyWith
/// - cachedCount 计算
/// - totalPages 计算
void main() {
  group('[ChapterListState] - 状态管理测试', () {
    final cachedChapters = [
      Chapter(
        title: '第1章',
        url: 'https://example.com/chapter1',
        chapterIndex: 0,
      ),
      Chapter(
        title: '第2章',
        url: 'https://example.com/chapter2',
        chapterIndex: 1,
      ),
    ];

    test('初始化应该返回默认空状态', () {
      // Arrange & Act
      const state = ChapterListState();

      // Assert
      expect(state.chapters, isEmpty);
      expect(state.isLoading, true);
      expect(state.errorMessage, isEmpty);
      expect(state.isInBookshelf, false);
      expect(state.lastReadChapterIndex, -1);
      expect(state.currentPage, 1);
      expect(state.totalPages, 1);
      expect(state.isReorderingMode, false);
    });

    test('copyWith 应该正确更新章节列表', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final newState = state.copyWith(
        chapters: cachedChapters,
        isLoading: false,
      );

      // Assert
      expect(newState.chapters, cachedChapters);
      expect(newState.isLoading, false);
      expect(newState.chapters.length, 2);
    });

    test('copyWith 应该正确更新 errorMessage', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final newState = state.copyWith(
        isLoading: false,
        errorMessage: '加载失败',
      );

      // Assert
      expect(newState.isLoading, false);
      expect(newState.errorMessage, '加载失败');
    });

    test('copyWith 应该正确更新 isInBookshelf', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final newState = state.copyWith(isInBookshelf: true);

      // Assert
      expect(newState.isInBookshelf, true);
    });

    test('copyWith 应该正确更新 lastReadChapterIndex', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final newState = state.copyWith(lastReadChapterIndex: 5);

      // Assert
      expect(newState.lastReadChapterIndex, 5);
    });

    test('copyWith 应该正确更新 isReorderingMode', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final newState = state.copyWith(isReorderingMode: true);

      // Assert
      expect(newState.isReorderingMode, true);
    });

    test('copyWith 应该正确更新 totalPages', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final newState = state.copyWith(totalPages: 5);

      // Assert
      expect(newState.totalPages, 5);
    });

    test('copyWith 应该正确更新 currentPage', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final newState = state.copyWith(currentPage: 3);

      // Assert
      expect(newState.currentPage, 3);
    });
  });

  group('[ChapterListState] - cachedCount 测试', () {
    test('cachedCount 空状态应该返回0', () {
      // Arrange
      const state = ChapterListState();

      // Act
      final count = state.cachedCount;

      // Assert
      expect(count, 0);
    });

    test('cachedCount 有缓存应该正确计算', () {
      // Arrange
      final state = ChapterListState(
        chapters: [
          Chapter(title: '第1章', url: 'url1', isCached: true),
          Chapter(title: '第2章', url: 'url2', isCached: true),
          Chapter(title: '第3章', url: 'url3', isCached: false),
        ],
      );

      // Act
      final count = state.cachedCount;

      // Assert
      expect(count, 2);
    });

    test('cachedCount 全部缓存应该返回总数', () {
      // Arrange
      final state = ChapterListState(
        chapters: [
          Chapter(title: '第1章', url: 'url1', isCached: true),
          Chapter(title: '第2章', url: 'url2', isCached: true),
          Chapter(title: '第3章', url: 'url3', isCached: true),
        ],
      );

      // Act
      final count = state.cachedCount;

      // Assert
      expect(count, 3);
    });

    test('cachedCount 全部未缓存应该返回0', () {
      // Arrange
      final state = ChapterListState(
        chapters: [
          Chapter(title: '第1章', url: 'url1', isCached: false),
          Chapter(title: '第2章', url: 'url2', isCached: false),
          Chapter(title: '第3章', url: 'url3', isCached: false),
        ],
      );

      // Act
      final count = state.cachedCount;

      // Assert
      expect(count, 0);
    });
  });

  group('[ChapterListState] - 边界测试', () {
    test('copyWith 只更新部分字段应该保留其他字段', () {
      // Arrange
      final state = ChapterListState(
        chapters: [
          Chapter(title: '第1章', url: 'url1', chapterIndex: 0),
        ],
        isLoading: false,
        isInBookshelf: true,
        errorMessage: '错误',
      );

      // Act - 只更新 isLoading
      final newState = state.copyWith(isLoading: true);

      // Assert
      expect(newState.chapters.length, 1); // 保留
      expect(newState.isLoading, true); // 更新
      expect(newState.isInBookshelf, true); // 保留
      expect(newState.errorMessage, '错误'); // 保留
    });

    test('copyWith 空章节列表应该正常处理', () {
      // Arrange
      final state = ChapterListState(
        chapters: [
          Chapter(title: '第1章', url: 'url1', chapterIndex: 0),
        ],
      );

      // Act
      final newState = state.copyWith(chapters: []);

      // Assert
      expect(newState.chapters, isEmpty);
    });
  });
}
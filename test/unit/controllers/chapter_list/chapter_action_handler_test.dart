/// ChapterActionHandler 章节操作处理器单元测试
///
/// Controller 重构（2026-07-29 章节写入收口）后，仅保留 [isChapterCached]
/// 只读委托。原 insertChapter / deleteChapter 写方法已迁出至
/// `ChapterMutationNotifier`（createChapter / deleteChapter），其收口 + bump
/// signal 语义由 `chapter_mutation_provider_test.dart` 覆盖。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/controllers/chapter_list/chapter_action_handler_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_app/controllers/chapter_list/chapter_action_handler.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_repository.dart';

// 生成 MockIChapterRepository（接口脱钩后写方法已移除，mock 仅需 mock isChapterCached）
@GenerateMocks([IChapterRepository])
import 'chapter_action_handler_test.mocks.dart';

void main() {
  late ChapterActionHandler handler;
  late MockIChapterRepository mockRepo;

  setUp(() {
    mockRepo = MockIChapterRepository();
    handler = ChapterActionHandler(chapterRepository: mockRepo);
  });

  group('ChapterActionHandler - isChapterCached', () {
    test('应委托给 repository.isChapterCached', () async {
      when(mockRepo.isChapterCached('chapter_url'))
          .thenAnswer((_) async => true);

      final result = await handler.isChapterCached('chapter_url');

      expect(result, isTrue);
      verify(mockRepo.isChapterCached('chapter_url')).called(1);
    });

    test('应正确返回 false（未缓存）', () async {
      when(mockRepo.isChapterCached('chapter_url'))
          .thenAnswer((_) async => false);

      final result = await handler.isChapterCached('chapter_url');

      expect(result, isFalse);
    });

    test('repository 异常时应 rethrow', () async {
      when(mockRepo.isChapterCached(any)).thenThrow(Exception('查询失败'));

      expect(
        () => handler.isChapterCached('chapter_url'),
        throwsException,
      );
    });
  });
}

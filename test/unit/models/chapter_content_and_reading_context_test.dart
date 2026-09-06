import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/chapter_content_result.dart';
import 'package:novel_app/core/providers/reading_context_providers.dart';

/// ChapterContentResult 和 ReadingContext 单元测试
///
/// 测试核心模型的功能：
/// - ChapterContentResult: 构造、默认值
/// - ReadingContext: hasContext、displayLabel、toSystemPrompt、none
void main() {
  group('ChapterContentResult - 模型测试', () {
    test('应该正确创建带 fromCache=true 的结果', () {
      final result = ChapterContentResult(
        content: '章节内容',
        fromCache: true,
      );

      expect(result.content, '章节内容');
      expect(result.fromCache, true);
    });

    test('应该正确创建带 fromCache=false 的结果', () {
      final result = ChapterContentResult(
        content: '章节内容',
        fromCache: false,
      );

      expect(result.content, '章节内容');
      expect(result.fromCache, false);
    });

    test('fromCache 默认值应该为 false', () {
      final result = ChapterContentResult(content: '章节内容');

      expect(result.fromCache, false);
    });

    test('应该支持空内容', () {
      final result = ChapterContentResult(content: '');

      expect(result.content, '');
      expect(result.fromCache, false);
    });
  });

  group('ReadingContext - 上下文模型测试', () {
    test('hasContext 应该为 true 当 novelTitle 不为空', () {
      const context = ReadingContext(novelTitle: '斗破苍穹');

      expect(context.hasContext, true);
    });

    test('hasContext 应该为 false 当 novelTitle 为空', () {
      const context = ReadingContext();

      expect(context.hasContext, false);
    });

    test('hasContext 应该为 false 当只有 chapterTitle 没有 novelTitle', () {
      const context = ReadingContext(chapterTitle: '第一章');

      expect(context.hasContext, false);
    });

    test('displayLabel 应该返回小说名·章节名 当有章节', () {
      const context = ReadingContext(
        novelTitle: '斗破苍穹',
        chapterTitle: '第一章 陨落的天才',
      );

      expect(context.displayLabel, '斗破苍穹 · 第一章 陨落的天才');
    });

    test('displayLabel 应该只返回小说名 当没有章节', () {
      const context = ReadingContext(novelTitle: '斗破苍穹');

      expect(context.displayLabel, '斗破苍穹');
    });

    test('displayLabel 应该返回空字符串 当没有上下文', () {
      const context = ReadingContext();

      expect(context.displayLabel, '');
    });

    test('toSystemPrompt 应该包含小说和章节信息', () {
      const context = ReadingContext(
        novelTitle: '斗破苍穹',
        chapterTitle: '第一章',
      );

      final prompt = context.toSystemPrompt();

      expect(prompt, contains('当前小说: 斗破苍穹'));
      expect(prompt, contains('当前章节: 第一章'));
      expect(prompt, contains('当前用户正在使用小说阅读应用'));
    });

    test('toSystemPrompt 应该只包含小说信息 当没有章节', () {
      const context = ReadingContext(novelTitle: '斗破苍穹');

      final prompt = context.toSystemPrompt();

      expect(prompt, contains('当前小说: 斗破苍穹'));
      expect(prompt, isNot(contains('当前章节')));
    });

    test('toSystemPrompt 应该返回空字符串 当没有上下文', () {
      const context = ReadingContext();

      expect(context.toSystemPrompt(), '');
    });

    test('none 应该是空上下文', () {
      expect(ReadingContext.none.hasContext, false);
      expect(ReadingContext.none.novelTitle, isNull);
      expect(ReadingContext.none.chapterTitle, isNull);
      expect(ReadingContext.none.novelUrl, isNull);
    });

    test('应该正确存储 novelUrl', () {
      const context = ReadingContext(
        novelTitle: '斗破苍穹',
        novelUrl: 'https://example.com/novel/1',
      );

      expect(context.novelUrl, 'https://example.com/novel/1');
    });
  });
}
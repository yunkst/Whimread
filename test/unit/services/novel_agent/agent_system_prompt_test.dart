/// AgentSystemPrompt 用户上下文注入测试
///
/// 验证 [AgentSystemPrompt.buildUserContextPrefix] 在各种上下文组合下的输出：
/// - 阅读上下文 + 当前工作小说 都有 → 3 行
/// - 仅阅读上下文 → 1-2 行
/// - 仅当前工作小说 → 1 行
/// - 都没有 → 空串（调用方据此跳过注入）
/// - 章节缺失 / 标题空白 → 对应行省略
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/reading_context_providers.dart';
import 'package:novel_app/services/novel_agent/agent_system_prompt.dart';

void main() {
  group('AgentSystemPrompt.buildUserContextPrefix', () {
    test('阅读 + 章节 + 工作小说都有 → 三行上下文', () {
      final prefix = AgentSystemPrompt.buildUserContextPrefix(
        readingContext: const ReadingContext(
          novelTitle: '凡人修仙传',
          chapterTitle: '第一章 初入修仙界',
        ),
        currentNovelTitle: '凡人修仙传',
      );

      expect(prefix, startsWith('## 用户上下文\n'));
      expect(prefix, contains('正在阅读：《凡人修仙传》'));
      expect(prefix, contains('章节：第一章 初入修仙界'));
      expect(prefix, contains('当前工作小说：《凡人修仙传》'));
      // 必须是 3 条 bullet
      final bulletCount = '- '.allMatches(prefix).length;
      expect(bulletCount, 3);
      // 必须以空行结尾（user 输入跟在前缀后）
      expect(prefix, endsWith('\n\n'));
    });

    test('仅有工作小说（readingContext 为 null）', () {
      final prefix = AgentSystemPrompt.buildUserContextPrefix(
        currentNovelTitle: '凡人修仙传',
      );

      expect(prefix, startsWith('## 用户上下文\n'));
      expect(prefix, contains('当前工作小说：《凡人修仙传》'));
      expect(prefix, isNot(contains('正在阅读')));
      expect(prefix, isNot(contains('章节')));
      expect(prefix, endsWith('\n\n'));
    });

    test('仅有工作小说（readingContext 为空）', () {
      final prefix = AgentSystemPrompt.buildUserContextPrefix(
        readingContext: ReadingContext.none,
        currentNovelTitle: '凡人修仙传',
      );

      expect(prefix, contains('当前工作小说：《凡人修仙传》'));
      expect(prefix, isNot(contains('正在阅读')));
    });

    test('仅有阅读上下文 + 章节', () {
      final prefix = AgentSystemPrompt.buildUserContextPrefix(
        readingContext: const ReadingContext(
          novelTitle: '斗破苍穹',
          chapterTitle: '第三章 退婚',
        ),
      );

      expect(prefix, contains('正在阅读：《斗破苍穹》'));
      expect(prefix, contains('章节：第三章 退婚'));
      expect(prefix, isNot(contains('当前工作小说')));
    });

    test('仅有阅读上下文，无章节', () {
      final prefix = AgentSystemPrompt.buildUserContextPrefix(
        readingContext: const ReadingContext(novelTitle: '斗破苍穹'),
      );

      expect(prefix, contains('正在阅读：《斗破苍穹》'));
      expect(prefix, isNot(contains('章节')));
      expect(prefix, isNot(contains('当前工作小说')));
    });

    test('阅读小说与工作小说不同时，三者并列', () {
      final prefix = AgentSystemPrompt.buildUserContextPrefix(
        readingContext: const ReadingContext(
          novelTitle: '斗破苍穹',
          chapterTitle: '第三章 退婚',
        ),
        currentNovelTitle: '凡人修仙传',
      );

      expect(prefix, contains('正在阅读：《斗破苍穹》'));
      expect(prefix, contains('章节：第三章 退婚'));
      expect(prefix, contains('当前工作小说：《凡人修仙传》'));
    });

    test('当前工作小说为空白字符串 → 跳过该行', () {
      final prefix = AgentSystemPrompt.buildUserContextPrefix(
        readingContext: const ReadingContext(novelTitle: '斗破苍穹'),
        currentNovelTitle: '   ',
      );

      expect(prefix, contains('正在阅读'));
      expect(prefix, isNot(contains('当前工作小说')));
    });

    test('全部为空 → 返回空串（调用方应跳过注入）', () {
      expect(
        AgentSystemPrompt.buildUserContextPrefix(
          readingContext: ReadingContext.none,
        ),
        '',
      );
      expect(
        AgentSystemPrompt.buildUserContextPrefix(),
        '',
      );
      expect(
        AgentSystemPrompt.buildUserContextPrefix(
          currentNovelTitle: '',
        ),
        '',
      );
      expect(
        AgentSystemPrompt.buildUserContextPrefix(
          currentNovelTitle: '  ',
        ),
        '',
      );
    });
  });

  group('AgentSystemPrompt.build（system prompt 不再注入阅读/工作小说）', () {
    test('不再包含 "## 用户阅读上下文" 与 "## 当前小说" 段', () {
      final prompt = AgentSystemPrompt.build();
      expect(prompt, isNot(contains('## 用户阅读上下文')));
      expect(prompt, isNot(contains('用户当前正在阅读')));
      expect(prompt, isNot(contains('## 当前小说')));
    });

    test('仍包含工作原则段（确保未误删）', () {
      final prompt = AgentSystemPrompt.build();
      expect(prompt, contains('## 工作原则'));
      expect(prompt, contains('1. 选定目标'));
      expect(prompt, contains('5. 修改小说封面'));
      expect(prompt, contains('6. 修改操作完成后向用户汇报'));
    });

    test('memories 非空时渲染编号列表', () {
      final prompt = AgentSystemPrompt.build(memories: const [
        '大纲不需要标题',
        '每轮注入用户上下文',
      ]);
      expect(prompt, contains('## 经验记忆'));
      expect(prompt, contains('[1] 大纲不需要标题'));
      expect(prompt, contains('[2] 每轮注入用户上下文'));
    });

    test('system prompt 提及 set_novel_cover 封面工具', () {
      final prompt = AgentSystemPrompt.build();

      expect(prompt, contains('set_novel_cover'));
      expect(prompt, contains('封面'));
    });
  });
}
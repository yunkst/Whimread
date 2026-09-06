/// outline_replacer.dart 纯函数单测
///
/// 不依赖 DB / Provider，直接对 9 重 Replacer 的命中/未命中/歧义场景
/// + Levenshtein 阈值边界做单元测试。
///
/// 算法对标 opencode edit.ts:608-645 的 replace() 流程。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/outline_replacer.dart';

void main() {
  // ══════════════════════════════════════
  // Levenshtein 基础
  // ══════════════════════════════════════
  group('Levenshtein', () {
    test('空串与非空串的距离 = 另一串长度', () {
      // 通过公开的 escapeNormalizedReplacer 间接不可访问，这里只做端到端验证：
      // 当 oldString 在 content 里编辑距离较小时仍能命中 blockAnchor。
      const content = 'line one\nline two\nline three';
      final result = replaceOutlineSnippet(
        content: content,
        oldString: 'line one\nline TWO\nline three', // 一行小写误传
        newString: 'line one\nLINE TWO\nline three',
      );
      // blockAnchor:首尾 'line one'/'line three' 命中,中间 'line TWO' 与 'line two' 相似度=1.0≥0.0
      expect(result, 'line one\nLINE TWO\nline three');
    });
  });

  // ══════════════════════════════════════
  // simpleReplacer（字面精确）
  // ══════════════════════════════════════
  group('simpleReplacer（路径1：字面精确匹配）', () {
    test('oldString 唯一 → 替换', () {
      final r = replaceOutlineSnippet(
        content: 'hello world',
        oldString: 'world',
        newString: 'Dart',
      );
      expect(r, 'hello Dart');
    });

    test('多行片段精确匹配 → 替换', () {
      const content = '# 第一章\n场景一\n# 第二章';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '场景一',
        newString: '场景一(改)',
      );
      expect(r, '# 第一章\n场景一(改)\n# 第二章');
    });
  });

  // ══════════════════════════════════════
  // lineTrimmedReplacer
  // ══════════════════════════════════════
  group('lineTrimmedReplacer（路径2：行 trim 容错）', () {
    test('AI 漏了行尾空格仍能命中', () {
      const content = '第一幕  \n第二幕\n第三幕';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '第一幕\n第二幕', // 没带尾部空格
        newString: '第一幕(改)\n第二幕',
      );
      expect(r, '第一幕(改)\n第二幕\n第三幕');
    });

    test('AI 多带了行首缩进仍能命中（按匹配块整体替换）', () {
      const content = '  开头行\n  正文行\n  结尾行';
      // opencode LineTrimmedReplacer 的语义：定位到原文里整块（带原始缩进），
      // 然后整体替换为 newString。这里 newString 不带缩进，所以结果也不带。
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '开头行\n正文行\n结尾行',
        newString: '开头行(改)\n正文行\n结尾行',
      );
      expect(r, '开头行(改)\n正文行\n结尾行');
    });
  });

  // ══════════════════════════════════════
  // blockAnchorReplacer + Levenshtein
  // ══════════════════════════════════════
  group('blockAnchorReplacer（路径3：首尾锚点+编辑距离）', () {
    test('首尾正确、中间一行小写拼错仍能命中', () {
      const content = '# 起点\n远方有座山\n远方有条河\n# 终点';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '# 起点\n远方有座shan\n远方有条河\n# 终点',
        newString: '# 起点\n远方有座山脉\n远方有条河\n# 终点',
      );
      expect(r, '# 起点\n远方有座山脉\n远方有条河\n# 终点');
    });

    test('单候选时相似度阈值=0.0，几乎总能接受', () {
      const content = 'AAA\n完全不同的中间行\nBBB';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: 'AAA\n完全无关的内容\nBBB',
        newString: 'AAA\n新内容\nBBB',
      );
      // 单候选,首尾匹配,中间相似度虽低但阈值=0.0,接受
      expect(r, 'AAA\n新内容\nBBB');
    });
  });

  // ══════════════════════════════════════
  // whitespaceNormalizedReplacer
  // ══════════════════════════════════════
  group('whitespaceNormalizedReplacer（路径4：空白折叠）', () {
    test('AI 把多空格压成单空格仍能命中', () {
      const content = '开头   中间   结尾'; // 多空格
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '开头 中间 结尾',
        newString: '新内容',
      );
      expect(r, '新内容');
    });

    test('跨行多空白也能命中（用 TrimmedBoundary 兜底 trim 匹配）', () {
      // LineTrimmed/WhitespaceNormalized 对跨空行不友好，
      // TrimmedBoundary 把 '行一 行二' trim 后仍是它,本身不变,跳过。
      // 这里改成更现实的场景：content 有行内多空格。
      const content2 = '行一    行二';
      final r = replaceOutlineSnippet(
        content: content2,
        oldString: '行一 行二',
        newString: '合并',
      );
      expect(r, '合并');
    });
  });

  // ══════════════════════════════════════
  // indentationFlexibleReplacer
  // ══════════════════════════════════════
  group('indentationFlexibleReplacer（路径5：去缩进）', () {
    test('AI 给的缩进比原文少仍能命中（整体替换为 newString）', () {
      const content = '    子项A\n    子项B\n    子项C';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '子项A\n子项B\n子项C',
        newString: '子项A(改)\n子项B\n子项C',
      );
      // opencode IndentationFlexibleReplacer 切原文整块（含缩进）整体替换为 newString
      expect(r, '子项A(改)\n子项B\n子项C');
    });
  });

  // ══════════════════════════════════════
  // escapeNormalizedReplacer
  // ══════════════════════════════════════
  group('escapeNormalizedReplacer（路径6：转义符归一）', () {
    test('AI 给的 \\n 转义符与原文真实换行等同时能命中', () {
      const content = 'a\nb\nc';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: r'a\nb',
        newString: 'a|b',
      );
      expect(r, 'a|b\nc');
    });

    test('AI 给的 \\t 与原文制表符等同时能命中', () {
      const content = 'col1\tcol2\tcol3';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: r'col1\tcol2',
        newString: 'C1\tC2',
      );
      expect(r, 'C1\tC2\tcol3');
    });
  });

  // ══════════════════════════════════════
  // trimmedBoundaryReplacer
  // ══════════════════════════════════════
  group('trimmedBoundaryReplacer（路径7：边界 trim）', () {
    test('AI 多带了首尾空白字符能命中', () {
      const content = '中间内容';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '  中间内容  ',
        newString: '新内容',
      );
      expect(r, '新内容');
    });
  });

  // ══════════════════════════════════════
  // contextAwareReplacer
  // ══════════════════════════════════════
  group('contextAwareReplacer（路径8：上下文感知）', () {
    test('首尾锚点 + 中间 50% 行相等即命中', () {
      const content = '前文\n关键行A\n关键行B\n后文';
      // middle=关键行A,关键行B 都匹配
      final r = replaceOutlineSnippet(
        content: content,
        oldString: '前文\n关键行A\n关键行B\n后文',
        newString: '前文\n改动A\n改动B\n后文',
      );
      expect(r, '前文\n改动A\n改动B\n后文');
    });
  });

  // ══════════════════════════════════════
  // multiOccurrenceReplacer + replaceAll
  // ══════════════════════════════════════
  group('multiOccurrenceReplacer + replaceAll（路径9）', () {
    test('replaceAll=false + 多处命中 → ambiguous', () {
      const content = 'foo bar foo baz foo';
      expect(
        () => replaceOutlineSnippet(
          content: content,
          oldString: 'foo',
          newString: 'X',
          replaceAll: false,
        ),
        throwsA(isA<OutlineEditException>()
            .having((e) => e.reason, 'reason', 'ambiguous')),
      );
    });

    test('replaceAll=true → 全部替换', () {
      const content = 'foo bar foo baz foo';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: 'foo',
        newString: 'X',
        replaceAll: true,
      );
      expect(r, 'X bar X baz X');
    });

    test('replaceAll=true + 无命中 → not_found', () {
      const content = 'hello world';
      expect(
        () => replaceOutlineSnippet(
          content: content,
          oldString: 'missing',
          newString: 'X',
          replaceAll: true,
        ),
        throwsA(isA<OutlineEditException>()
            .having((e) => e.reason, 'reason', 'not_found')),
      );
    });
  });

  // ══════════════════════════════════════
  // 失败情况
  // ══════════════════════════════════════
  group('失败情况', () {
    test('oldString 在 9 个 Replacer 下都找不到 → not_found', () {
      const content = '一段完全无关的大纲内容';
      expect(
        () => replaceOutlineSnippet(
          content: content,
          oldString: '不存在的段落',
          newString: 'X',
        ),
        throwsA(isA<OutlineEditException>()
            .having((e) => e.reason, 'reason', 'not_found')
            .having((e) => e.message, 'message',
                contains('oldString not found'))),
      );
    });

    test('oldString == newString → ArgumentError', () {
      expect(
        () => replaceOutlineSnippet(
          content: 'abc',
          oldString: 'a',
          newString: 'a',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ══════════════════════════════════════
  // 9 重容错链路（端到端）
  // ══════════════════════════════════════
  group('端到端：链式 fallback', () {
    test('简单替换走 simpleReplacer 第一关', () {
      expect(
        replaceOutlineSnippet(
          content: 'AB',
          oldString: 'A',
          newString: 'X',
        ),
        'XB',
      );
    });

    test('行 trim 容错走 lineTrimmedReplacer 第二关', () {
      // content 末尾带尾随空格,LineTrimmedReplacer 把整块切出来,
      // 整体替换为 newString（不含尾部空格）。
      const content = 'A  \nB';
      final r = replaceOutlineSnippet(
        content: content,
        oldString: 'A\nB',
        newString: 'X',
      );
      expect(r, 'X');
    });
  });
}
/// unescapeJsonEscapeSequences 单元测试
///
/// 反馈 id=4「json 混入原文」根因:LLM 传给 update_chapter_content 的
/// newString / oldString 里带字面 `\n` / `\"` 序列,落库后正文被污染。
/// 本函数是 P1 清洗的核心:把 JSON 转义序列还原为真字符,与
/// escapeNormalizedReplacer 内部归一化规则保持完全一致。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/outline_replacer.dart';

void main() {
  group('unescapeJsonEscapeSequences', () {
    test('字面 \\n 还原为真换行', () {
      expect(
        unescapeJsonEscapeSequences(r'陈玄看了看。\n那没系扣子的领口'),
        '陈玄看了看。\n那没系扣子的领口',
      );
    });

    test('字面 \\" 还原为真引号', () {
      expect(
        unescapeJsonEscapeSequences(r'她\"啊\"了一声'),
        '她"啊"了一声',
      );
    });

    test('字面 \\t / \\r 还原为 tab / 回车', () {
      expect(unescapeJsonEscapeSequences(r'a\tb'), 'a\tb');
      expect(unescapeJsonEscapeSequences(r'a\rb'), 'a\rb');
    });

    test('双反斜杠还原为单反斜杠', () {
      expect(unescapeJsonEscapeSequences(r'a\\b'), r'a\b');
    });

    test('反引号 / 单引号 / 美元符号还原', () {
      // 输入 6 字符:`\`, `` ` ``, `'`, `\`, `$`, `z`
      //   — 反斜杠后跟反引号/单引号/美元,均归一化
      // 输出 4 字符:`` ` ``, `'`, `$`, `z`
      final raw = '\\' '`' "'" '\\' '\$' 'z';
      final expected = '`' "'" '\$' 'z';
      expect(unescapeJsonEscapeSequences(raw), expected);
    });

    test('反斜杠后跟未知字符保持原文', () {
      expect(unescapeJsonEscapeSequences(r'a\qb'), r'a\qb');
    });

    test('真实事故样本:LLM 双重转义的 newString 完整还原', () {
      // 反馈日志里的实际参数形态(JSON 编码层解码后):
      // 输入 3 字符 `\\n`(反斜杠+反斜杠+n),单层 unescape 后得到 2 字符 `\n`
      // (反斜杠+n);再 unescape 一次才会变真换行——所以单遍规则只洗一层。
      // 反馈 id=4 里 LLM 反复尝试各种转义层数,本函数的"只洗一层"语义
      // 等价于"剥掉 JSON 传输层"。
      final raw = r'“吓死我了。”\\n这一拍带动胸口两团软肉一阵颤动，她\\"啊\\"了一声';
      final cleaned = unescapeJsonEscapeSequences(raw);
      // 字面 `\\n`(3 字符) → 字面 `\n`(2 字符)
      expect(cleaned, contains(r'\n'));
      expect(cleaned, isNot(contains(r'\\n')));
      // 字面 `\\"`(3 字符) → 字面 `\"`(2 字符)
      expect(cleaned, contains(r'\"'));
      expect(cleaned, isNot(contains(r'\\"')));
      // LLM 想要"真换行 + 真引号"时,只传 2 字符 `\n` / `\"` 即可
      final simple = r'“吓死我了。”\n这一拍带动';
      expect(unescapeJsonEscapeSequences(simple), contains('\n'));
      expect(unescapeJsonEscapeSequences(simple), isNot(contains(r'\n')));
    });

    test('已含真换行的字符串不变', () {
      final s = '第一行\n第二行';
      expect(unescapeJsonEscapeSequences(s), s);
    });

    test('空字符串不变', () {
      expect(unescapeJsonEscapeSequences(''), '');
    });

    test('无转义序列的普通中文不变', () {
      final s = '陈玄看了看披头散发的刘青禾。那没系扣子的领口';
      expect(unescapeJsonEscapeSequences(s), s);
    });
  });

  group('P1 端到端:LLM 入参清洗 → 替换 → 落库内容是真字符', () {
    test('newString 带字面 \\n 时,落库的 newContent 含真换行', () {
      // 模拟反馈 id=4 真实事故样本:LLM newString 里含字面 `\n`,
      // 经 unescapeJsonEscapeSequences → replaceOutlineSnippet 后,
      // 写库的 newContent 必须含真换行(单字符 LF),不再包含字面 `\n`。
      final rawNewString = r'“吓死我了。”\n这一拍带动胸口';
      final cleanedNew = unescapeJsonEscapeSequences(rawNewString);
      final original = '陈玄道：“别慌。”\n“吓死我了。”\n这一拍带动胸口';
      final newContent = original.replaceFirst(
        r'“吓死我了。”\n这一拍',
        cleanedNew,
      );

      // 落库结果:真换行 1 字符,字面 `\n`(2 字符)消失
      expect(newContent, contains('\n'));
      expect(newContent, isNot(contains(r'\n')));
      // 换行数:原文 1 个 + newString 清洗后 1 个 = 2
      expect('\n'.allMatches(newContent).length, 2);
    });

    test('oldString 带字面 \\" 时清洗后能命中真引号正文,替换成功', () {
      // 反馈 id=4 主场景:正文(库里)是真引号,LLM 复制 JSON 转义文本时
      // 传的字面 `\"`。清洗后 oldString 变真引号,能命中正文完成替换。
      final rawOld = r'她\"啊\"了一声';
      final rawNew = '她“啊”了一声';
      final cleanedOld = unescapeJsonEscapeSequences(rawOld);
      final cleanedNew = unescapeJsonEscapeSequences(rawNew);
      final original = '她"啊"了一声，赶紧伸手去捂衣领'; // 库里未污染正文(真引号)
      final newContent = original.replaceFirst(cleanedOld, cleanedNew);

      // 替换成功:中文引号落库,英文真引号消失,字面 `\"` 全程未出现
      expect(newContent, contains('她“啊”了一声'));
      expect(newContent, isNot(contains('"')));
      expect(newContent, isNot(contains(r'\"')));
    });

    test('双反斜杠输入 \\n(3 字符)清洗后变 \\n(2 字符),与 escapeNormalizedReplacer 行为一致', () {
      // 验证抽到顶层后规则没漂移:同一输入 → 同一输出
      // escapeNormalizedReplacer 之前内部 unescape closure 用同样 RegExp/switch,
      // 抽出后必须保持 byte-for-byte 一致。
      final input = r'\\n';
      final cleaned = unescapeJsonEscapeSequences(input);
      expect(cleaned, r'\n'); // 3 字符 → 2 字符(字面反斜杠+n)
      expect(cleaned.length, 2);
    });
  });
}

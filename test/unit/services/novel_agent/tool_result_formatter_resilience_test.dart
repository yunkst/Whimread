/// ToolResultFormatter 抗崩溃回归测试
///
/// 背景：agent 分析 OCR / 提取网页内容时，工具结果常含超长字符串 + 大量特殊字符
/// （裸双引号 / 反斜杠 / 换行 / PUA 私用区字符 / HTML 标签）。formatter 硬截断时
/// 必须保证产出合法 JSON，否则 _withMeta 的 jsonDecode 报
/// `FormatException: Unterminated string`，导致整个 agent 循环中断。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/tool_result_formatter.dart';

void main() {
  group('ToolResultFormatter 抗崩溃回归（OCR / HTML / 特殊字符）', () {
    test('PUA 字符 + 超长单字段 + meta → llm 合法 JSON', () {
      // 模拟番茄字体反爬 OCR 还原后的正文：60000 个 PUA 私用区字符
      final pua = String.fromCharCodes(
        List.generate(60000, (i) => 0xE000 + (i % 0x1000)),
      );
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({'raw': pua, '__meta': {'run_id': 'r-1'}});

      // 修复前：_withMeta 的 jsonDecode 抛 Unterminated string
      expect(() => jsonDecode(result.llm), returnsNormally,
          reason: 'PUA 超长字段 + meta 必须产出合法 JSON');
      final decoded = jsonDecode(result.llm) as Map<String, dynamic>;
      expect(decoded['__meta'], {'run_id': 'r-1'});
      expect((decoded['raw'] as String).length, greaterThan(0));
    });

    test('HTML 原文（裸引号/反斜杠/换行）+ 超长 → llm 合法 JSON', () {
      // exec js 提取出的 HTML，含大量 " \n < > 触发 jsonEncode 转义膨胀
      final html = StringBuffer();
      for (var i = 0; i < 5000; i++) {
        html.write(
          '<div class="row" data-id="$i" title=\'a\\b\'>\n'
          '  <p>line $i "quoted" \\backslash</p>\n'
          '</div>',
        );
      }
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({'html': html.toString()});

      expect(() => jsonDecode(result.llm), returnsNormally,
          reason: 'HTML 含特殊字符超长字段必须产出合法 JSON');
      expect(result.llm.length, lessThanOrEqualTo(50000));
    });

    test('多字段混合（短+长+特殊字符） → llm 合法且短字段完整', () {
      final weird = '"quoted" \\backslash \nnewline ${'\$' * 30000}';
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({
        'novelId': 42, // 短字段必须保留
        'title': '番茄', // 短字段
        'content': weird, // 长字段 + 特殊字符
        '__meta': {'run_id': 'r-2'},
      });

      expect(() => jsonDecode(result.llm), returnsNormally);
      final decoded = jsonDecode(result.llm) as Map<String, dynamic>;
      expect(decoded['novelId'], 42);
      expect(decoded['title'], '番茄');
      expect(decoded['__meta'], {'run_id': 'r-2'});
    });

    test('极端：单字段超超长（80 万字） → llm 合法且截断', () {
      final huge = 'X' * 800000;
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({'raw': huge, '__meta': {'run_id': 'r-3'}});

      expect(() => jsonDecode(result.llm), returnsNormally,
          reason: '80 万字极端场景必须产出合法 JSON');
      expect(result.llm.length, lessThanOrEqualTo(50000));
    });

    test('控制字符（换行/制表符）混杂 → llm 合法 JSON', () {
      final s = 'line1\nline2\tcol\r\nline3' * 5000;
      final f = ToolResultFormatter(maxChars: 30000);
      final result = f.format({'content': s});

      expect(() => jsonDecode(result.llm), returnsNormally);
    });
  });
}

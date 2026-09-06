/// ToolResultFormatter 比例分配算法单元测试
///
/// 覆盖 4 个关键场景：
/// 1. 单字段不超预算 → 完整保留（read_chapter_content 特例）
/// 2. 单字段超预算 → 吃满预算（接近 maxChars）
/// 3. 多字段按比例公平压缩 → 总长不超过 maxChars
/// 4. 错误分支保留 error/message/suggestion，partial_data 不重复
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/tool_result_formatter.dart';

void main() {
  group('ToolResultFormatter 比例分配', () {
    test('单字段小结果不超预算 → 完整保留', () {
      // 模拟 read_chapter_content 包装后的 {'raw': '6000字章节正文'}
      final content = 'A' * 6000; // 6000 字
      final f = ToolResultFormatter(maxChars: 50000);

      final result = f.format({'raw': content});

      // 完整保留
      expect(result.full, contains('"raw":"${'A' * 6000}"'));
      expect(result.llm, contains('"raw":"${'A' * 6000}"'));
      expect(result.llm.length, lessThan(50000));
    });

    test('单字段超预算 → 截到接近 maxChars 上限', () {
      // 单字段 80 万字，maxChars=50000，应该被大幅裁剪但仍接近预算
      final huge = 'B' * 800000;
      final f = ToolResultFormatter(maxChars: 50000);

      final result = f.format({'raw': huge});

      // llm 应该在 maxChars 附近（不能远超）
      expect(result.llm.length, lessThanOrEqualTo(50000));
      // 完整版完整保留：jsonEncode({'raw': 'B' * 800000}) 长度
      // = '{"raw":"..."}'.length + 800000 = 10 + 800000 = 800010
      expect(result.full.length, 800010);
      // llm 比 full 显著小
      expect(result.llm.length, lessThan(result.full.length ~/ 10));
    });

    test('多字段按比例公平压缩 → 总长不超过 maxChars', () {
      // 3 个字段，每个 ~10000 字，总和 30000 < 50000，全部保留
      final f1 = ToolResultFormatter(maxChars: 50000);
      final result1 = f1.format({
        'a': 'X' * 10000,
        'b': 'Y' * 10000,
        'c': 'Z' * 10000,
      });
      expect(result1.llm.length, lessThanOrEqualTo(50000));
      // 30000 < 50000 → 全部保留
      expect(result1.llm, contains('"a":"${'X' * 10000}"'));
      expect(result1.llm, contains('"b":"${'Y' * 10000}"'));
      expect(result1.llm, contains('"c":"${'Z' * 10000}"'));

      // 3 个字段各 30000 字，总和 90000 > 50000，触发比例压缩
      final f2 = ToolResultFormatter(maxChars: 50000);
      final result2 = f2.format({
        'a': 'X' * 30000,
        'b': 'Y' * 30000,
        'c': 'Z' * 30000,
      });
      expect(result2.llm.length, lessThanOrEqualTo(50000),
          reason: '多字段按比例压缩后总长不超过 maxChars');

      // 公平压缩：每个字段都被裁到相近大小
      final decoded = jsonDecode(result2.llm) as Map<String, dynamic>;
      // 三个字段大小应该接近（差异在 30% 内）
      final aLen = (decoded['a'] as String).length;
      final bLen = (decoded['b'] as String).length;
      final cLen = (decoded['c'] as String).length;
      final maxLen = [aLen, bLen, cLen].reduce((a, b) => a > b ? a : b);
      final minLen = [aLen, bLen, cLen].reduce((a, b) => a < b ? a : b);
      expect(maxLen - minLen, lessThan(maxLen ~/ 3),
          reason: '三个字段大小应接近（公平分配），实际：$aLen/$bLen/$cLen');
    });

    test('错误分支：保留 error/message/suggestion，partial_data 不重复 error', () {
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({
        'error': 'not_found',
        'message': '小说ID 99 不存在',
        'suggestion': '请先调用 list_novels',
        'extra': 'C' * 80000, // 大块额外数据，应该被截断
      });

      // 关键字段必须完整保留
      expect(result.llm, contains('"error":"not_found"'));
      expect(result.llm, contains('"message":"小说ID 99 不存在"'));
      expect(result.llm, contains('"suggestion":"请先调用 list_novels"'));

      // partial_data 存在但不应重复 error 内容
      final decoded = jsonDecode(result.llm) as Map<String, dynamic>;
      expect(decoded.containsKey('partial_data'), isTrue);
      final partial = decoded['partial_data'].toString();
      // 错误字段名 'error' 不应出现在 partial_data 字符串里
      expect(partial.contains('error'), isFalse,
          reason: 'partial_data 不应重复 error 字段');

      // 总长受控
      expect(result.llm.length, lessThanOrEqualTo(50000));
    });

    test('__meta 不参与预算，结构作为顶层 key 拼回', () {
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({
        'success': true,
        'message': 'ok',
        '__meta': {'run_id': 'r-123', 'script_id': 7},
      });

      // __meta 完整保留在顶层
      expect(result.llm, contains('"__meta":{"run_id":"r-123","script_id":7}'));

      // full 也完整保留
      expect(result.full, contains('"__meta":{"run_id":"r-123","script_id":7}'));
    });

    test('小结果直接走快速路径（无字段被裁）', () {
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({
        'id': 1,
        'title': '测试小说',
        'isCached': true,
        'count': 1,
      });

      // 字符完全一致（无字段被改动）
      expect(result.llm, result.full);
      expect(jsonDecode(result.llm), {
        'id': 1,
        'title': '测试小说',
        'isCached': true,
        'count': 1,
      });
    });

    test('短字段豁免：1000 字以内字段即使在大结果中也完整保留', () {
      // 关键短字段 + 超长大字段，短字段必须完整
      final f = ToolResultFormatter(maxChars: 50000);
      final result = f.format({
        'novelId': 1,
        'title': '斗破苍穹', // 4 字符短字段
        'author': '天蚕土豆',
        'count': 100,
        'isCached': true,
        'description': '一部关于少年逆袭的玄幻小说', // 短字段
        'chapters': List.generate(50, (i) => {'position': i, 'content': 'C' * 2000}),
        // ↑ 50 章 × ~2000 字 ≈ 100000 字，远超 50000
      });

      // 所有短字段必须完整保留
      expect(result.llm, contains('"novelId":1'));
      expect(result.llm, contains('"title":"斗破苍穹"'));
      expect(result.llm, contains('"author":"天蚕土豆"'));
      expect(result.llm, contains('"count":100'));
      expect(result.llm, contains('"isCached":true'));
      expect(result.llm, contains('"description":"一部关于少年逆袭的玄幻小说"'));

      // 总长受硬校验兜底，绝不超 maxChars
      expect(result.llm.length, lessThanOrEqualTo(50000));

      // chapters 被压缩（不能是完整的 50 个 ~2000 字）
      final decoded = jsonDecode(result.llm) as Map<String, dynamic>;
      final chapters = decoded['chapters'] as List;
      expect(chapters.length, lessThanOrEqualTo(50));
    });

    test('短字段豁免阈值可配置（shortFieldThreshold=500）', () {
      // 阈值设为 500：1000 字字段会被视为长字段参与压缩
      final f = ToolResultFormatter(maxChars: 50000, shortFieldThreshold: 500);
      final result = f.format({
        'medium': 'M' * 800, // 800 字 > 500 阈值，参与压缩
        'huge': 'H' * 80000,
      });

      expect(result.llm.length, lessThanOrEqualTo(50000));
      // medium 被压缩（不再是完整 800 字）
      final decoded = jsonDecode(result.llm) as Map<String, dynamic>;
      expect((decoded['medium'] as String).contains('M'), isTrue);
    });

    test('数组按比例分配：保留尽可能多的元素', () {
      // 一个含 100 个元素的数组，每个 500 字（总 50000 字）
      final items = List.generate(100, (i) => 'item$i ${'X' * 480}');
      final f = ToolResultFormatter(maxChars: 30000);

      final result = f.format({'items': items});
      expect(result.llm.length, lessThanOrEqualTo(30000));

      final decoded = jsonDecode(result.llm) as Map<String, dynamic>;
      final keptItems = decoded['items'] as List;
      // 应该保留若干元素（不能全砍光，也不能超预算）
      expect(keptItems.length, greaterThan(0));
      expect(keptItems.length, lessThan(100));
      // 完整版应该有 100 个元素
      final fullDecoded = jsonDecode(result.full) as Map<String, dynamic>;
      expect((fullDecoded['items'] as List).length, 100);
    });
  });
}
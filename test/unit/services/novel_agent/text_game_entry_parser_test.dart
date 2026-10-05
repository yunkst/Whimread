/// parseTextGameEntry 解析器单元测试
///
/// 验证 create_text_game 工具结果 JSON 的解析逻辑（纯函数，无依赖）。
/// 覆盖：null、非法 JSON、success=false、gameId 缺失/非数字、完整有效
/// 数据（int / num 两种 gameId、gameTitle 缺省）。
///
/// 运行：
///   flutter test test/unit/services/novel_agent/text_game_entry_parser_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/agent_chat/text_game_entry_card.dart';

void main() {
  group('parseTextGameEntry - 边界返回 null', () {
    test('null 输入返回 null', () {
      expect(parseTextGameEntry(null), isNull);
    });

    test('空字符串返回 null', () {
      expect(parseTextGameEntry(''), isNull);
    });

    test('非 JSON 字符串返回 null', () {
      expect(parseTextGameEntry('not a json'), isNull);
    });

    test('非 Map 的 JSON 返回 null', () {
      expect(parseTextGameEntry('[1,2,3]'), isNull);
    });

    test('success=false 返回 null（失败结果不出入口卡）', () {
      final json = jsonEncode({'success': false, 'error': 'missing_title'});
      expect(parseTextGameEntry(json), isNull);
    });

    test('gameId 缺失返回 null', () {
      final json = jsonEncode({'success': true, 'gameTitle': '流云试炼'});
      expect(parseTextGameEntry(json), isNull);
    });

    test('gameId 非数字返回 null', () {
      final json = jsonEncode({'success': true, 'gameId': 'abc'});
      expect(parseTextGameEntry(json), isNull);
    });
  });

  group('parseTextGameEntry - 正常解析', () {
    test('完整载荷 → gameId / gameTitle', () {
      final json = jsonEncode(
          {'success': true, 'gameId': 42, 'gameTitle': '流云试炼'});
      final data = parseTextGameEntry(json);
      expect(data, isNotNull);
      expect(data!.gameId, 42);
      expect(data.gameTitle, '流云试炼');
    });

    test('gameId 为 num（double）也能取整', () {
      final json = jsonEncode({'success': true, 'gameId': 7.0});
      expect(parseTextGameEntry(json)!.gameId, 7);
    });

    test('gameTitle 缺失 → 缺省「文字游戏」', () {
      final json = jsonEncode({'success': true, 'gameId': 3});
      final data = parseTextGameEntry(json);
      expect(data!.gameTitle, '文字游戏');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/character.dart';

void main() {
  group('Character.firstAppearanceChapter', () {
    test('进出 toMap/fromMap', () {
      final c = Character(
        novelUrl: 'n',
        name: '甲',
        firstAppearanceChapter: 8,
      );
      final m = c.toMap();
      expect(m['firstAppearanceChapter'], 8);

      final c2 = Character.fromMap({
        'id': 1,
        'novelUrl': 'n',
        'name': '甲',
        'firstAppearanceChapter': 8,
        'createdAt': 0,
      });
      expect(c2.firstAppearanceChapter, 8);
    });

    test('默认 null(视为 §0 登场)', () {
      final c = Character(novelUrl: 'n', name: '甲');
      expect(c.firstAppearanceChapter, isNull);
      expect(c.toMap()['firstAppearanceChapter'], isNull);
    });

    test('copyWith 保留并更新', () {
      final c = Character(
        novelUrl: 'n',
        name: '甲',
        firstAppearanceChapter: 5,
      );
      expect(c.copyWith(name: '乙').firstAppearanceChapter, 5);
      expect(c.copyWith(firstAppearanceChapter: 10).firstAppearanceChapter, 10);
    });
  });

  group('Character 近况演化新字段（speechStyle / currentState）', () {
    test('toMap/fromMap 往返保留新字段', () {
      final c = Character(
        novelUrl: 'n',
        name: '甲',
        speechStyle: '冷峻，惯用短句',
        currentState: '重伤初愈，暂避城南',
      );
      final m = c.toMap();
      expect(m['speechStyle'], '冷峻，惯用短句');
      expect(m['currentState'], '重伤初愈，暂避城南');

      final c2 = Character.fromMap({
        'novelUrl': 'n',
        'name': '甲',
        'speechStyle': '冷峻，惯用短句',
        'currentState': '重伤初愈，暂避城南',
        'createdAt': 0,
      });
      expect(c2.speechStyle, '冷峻，惯用短句');
      expect(c2.currentState, '重伤初愈，暂避城南');
    });

    test('旧数据缺新字段列 → 解析为 null 不抛（列是后加的，存量行没有）', () {
      final c = Character.fromMap({
        'novelUrl': 'n',
        'name': '甲',
        'createdAt': 0,
      });
      expect(c.speechStyle, isNull);
      expect(c.currentState, isNull);
    });
  });

  group('Character.aliases 容错', () {
    test('JSON 列表往返', () {
      final c = Character(novelUrl: 'n', name: '甲', aliases: ['乙', '丙']);
      final m = c.toMap();
      expect(m['aliases'], '["乙","丙"]');

      final c2 = Character.fromMap({
        'novelUrl': 'n',
        'name': '甲',
        'aliases': '["乙","丙"]',
        'createdAt': 0,
      });
      expect(c2.aliases, ['乙', '丙']);
    });

    test('空列表序列化为 null（列保持空）', () {
      final c = Character(novelUrl: 'n', name: '甲', aliases: []);
      expect(c.toMap()['aliases'], isNull);
    });

    test('坏 JSON → 解析为 null，不抛（agent 写入的 JSON 允许脏数据）', () {
      for (final bad in ['not-json', '{', '[1,"unclosed', '123']) {
        final c = Character.fromMap({
          'novelUrl': 'n',
          'name': '甲',
          'aliases': bad,
          'createdAt': 0,
        });
        expect(c.aliases, isNull, reason: '输入: $bad');
      }
    });

    test('null/空串 → null', () {
      expect(
        Character.fromMap({
          'novelUrl': 'n', 'name': '甲', 'createdAt': 0,
        }).aliases,
        isNull,
      );
      expect(
        Character.fromMap({
          'novelUrl': 'n', 'name': '甲', 'aliases': '', 'createdAt': 0,
        }).aliases,
        isNull,
      );
    });
  });
}

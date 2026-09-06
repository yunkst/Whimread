import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/relation_type.dart';

void main() {
  group('RelationType', () {
    test('枚举共有 109 个值', () {
      expect(RelationType.values.length, 109);
    });

    test('forward 与 reverse 非空', () {
      for (final t in RelationType.values) {
        expect(t.forward, isNotEmpty, reason: '${t.name}.forward 为空');
        expect(t.reverse, isNotEmpty, reason: '${t.name}.reverse 为空');
      }
    });

    test('对称类型 forward == reverse', () {
      for (final t in RelationType.values) {
        if (t.symmetric) {
          expect(t.forward, t.reverse,
              reason: '${t.name} 标记对称但正反词不同');
        }
      }
    });

    test('masterDisciple 不对称且词条正确', () {
      expect(RelationType.masterDisciple.symmetric, isFalse);
      expect(RelationType.masterDisciple.forward, '师父');
      expect(RelationType.masterDisciple.reverse, '徒弟');
    });

    test('friend 对称且词条正确', () {
      expect(RelationType.friend.symmetric, isTrue);
      expect(RelationType.friend.forward, '朋友');
      expect(RelationType.friend.reverse, '朋友');
    });

    test('labelFor 按方向返回词条', () {
      expect(RelationType.masterDisciple.labelFor(isSource: true), '师父');
      expect(RelationType.masterDisciple.labelFor(isSource: false), '徒弟');
      expect(RelationType.friend.labelFor(isSource: false), '朋友');
    });

    test('颜色非透明', () {
      for (final t in RelationType.values) {
        expect(t.color.alpha, greaterThan(0), reason: '${t.name}.color 透明');
      }
    });

    test('byName 能从字符串还原(用于 DB 读入)', () {
      const name = 'masterDisciple';
      final t = RelationType.values.byName(name);
      expect(t, RelationType.masterDisciple);
    });
  });
}

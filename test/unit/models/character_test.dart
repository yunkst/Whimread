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
}

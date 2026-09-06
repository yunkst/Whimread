import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/character_relationship.dart';
import 'package:novel_app/models/relation_type.dart';

void main() {
  group('CharacterRelationship v2', () {
    test('toMap 包含全部新字段', () {
      final r = CharacterRelationship(
        sourceCharacterId: 1,
        targetCharacterId: 2,
        relationType: RelationType.masterDisciple,
        strength: 4,
        startChapter: 8,
        endChapter: null,
        novelUrl: 'novel_a',
      );
      final m = r.toMap();
      expect(m['relation_type'], 'masterDisciple');
      expect(m['strength'], 4);
      expect(m['start_chapter'], 8);
      expect(m['end_chapter'], isNull);
      expect(m['novel_url'], 'novel_a');
      expect(m['source_character_id'], 1);
      expect(m['target_character_id'], 2);
    });

    test('strength 默认为 3', () {
      final r = CharacterRelationship(
        sourceCharacterId: 1,
        targetCharacterId: 2,
        relationType: RelationType.friend,
        startChapter: 0,
        novelUrl: 'novel_a',
      );
      expect(r.strength, 3);
    });

    test('fromMap 还原枚举与字段', () {
      final m = {
        'id': 1,
        'source_character_id': 1,
        'target_character_id': 2,
        'relation_type': 'masterDisciple',
        'strength': 5,
        'start_chapter': 8,
        'end_chapter': 50,
        'description': '拜师',
        'novel_url': 'novel_a',
        'created_at': 0,
        'updated_at': null,
      };
      final r = CharacterRelationship.fromMap(m);
      expect(r.id, 1);
      expect(r.relationType, RelationType.masterDisciple);
      expect(r.strength, 5);
      expect(r.endChapter, 50);
      expect(r.description, '拜师');
      expect(r.novelUrl, 'novel_a');
    });

    test('fromMap strength 缺省回退到 3', () {
      final m = {
        'source_character_id': 1,
        'target_character_id': 2,
        'relation_type': 'friend',
        'start_chapter': 0,
        'novel_url': 'n',
        'created_at': 0,
      };
      expect(CharacterRelationship.fromMap(m).strength, 3);
    });

    test('copyWith 更新 endChapter 与 strength', () {
      final r = CharacterRelationship(
        sourceCharacterId: 1,
        targetCharacterId: 2,
        relationType: RelationType.friend,
        startChapter: 0,
        novelUrl: 'n',
      );
      final r2 = r.copyWith(endChapter: 79, strength: 5);
      expect(r2.endChapter, 79);
      expect(r2.strength, 5);
      expect(r2.sourceCharacterId, 1);
      expect(r2.relationType, RelationType.friend);
    });

    test('toString 含区间信息', () {
      final r = CharacterRelationship(
        sourceCharacterId: 1,
        targetCharacterId: 2,
        relationType: RelationType.masterDisciple,
        startChapter: 8,
        endChapter: null,
        novelUrl: 'n',
      );
      final s = r.toString();
      expect(s, contains('masterDisciple'));
      expect(s, contains('§8'));
    });
  });
}

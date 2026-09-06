import 'character.dart';
import 'character_relationship.dart';

/// 关系图在某章节的快照。
///
/// [characters] 为该章节已登场的人物, [relationships] 为该章节生效的关系。
class RelationshipGraphSnapshot {
  final List<Character> characters;
  final List<CharacterRelationship> relationships;
  final int chapter;

  const RelationshipGraphSnapshot({
    required this.characters,
    required this.relationships,
    required this.chapter,
  });

  bool get isEmpty => characters.isEmpty && relationships.isEmpty;
}

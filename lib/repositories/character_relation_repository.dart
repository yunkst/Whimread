import 'package:sqflite/sqflite.dart';
import '../models/character.dart';
import '../models/character_relationship.dart';
import '../models/relationship_graph_snapshot.dart';
import '../services/logger_service.dart';
import '../core/interfaces/repositories/i_character_relation_repository.dart';
import 'base_repository.dart';

/// 人物关系仓库 v2(区间模型)。
///
/// 关系采用区间模型(见 [CharacterRelationship] 的 startChapter/endChapter)。
/// [getGraphSnapshot] 提供按章节过滤的图快照,支撑时间轴交互。
class CharacterRelationRepository extends BaseRepository
    implements ICharacterRelationRepository {
  CharacterRelationRepository({required super.dbConnection});

  // ========== 基础 CRUD ==========

  @override
  Future<int> createRelationship(CharacterRelationship relationship) async {
    // 校验
    if (relationship.startChapter < 0) {
      throw ArgumentError.value(relationship.startChapter, 'startChapter',
          'startChapter 不能小于 0');
    }
    if (relationship.endChapter != null &&
        relationship.endChapter! < relationship.startChapter) {
      throw ArgumentError.value(
          relationship.endChapter, 'endChapter', 'endChapter 不能小于 startChapter');
    }

    try {
      final db = await database;

      // 对称类型:source/target 双向查重(避免 (A,B) 与 (B,A) 双份)
      if (relationship.relationType.symmetric) {
        final exists = await db.query(
          'character_relationships',
          where:
              'relation_type = ? AND start_chapter = ? AND novel_url = ? AND ('
              '(source_character_id = ? AND target_character_id = ?) OR '
              '(source_character_id = ? AND target_character_id = ?))',
          whereArgs: [
            relationship.relationType.name,
            relationship.startChapter,
            relationship.novelUrl,
            relationship.sourceCharacterId,
            relationship.targetCharacterId,
            relationship.targetCharacterId,
            relationship.sourceCharacterId,
          ],
          limit: 1,
        );
        if (exists.isNotEmpty) {
          throw StateError('对称关系已存在: ${relationship.relationType.name} '
              'between ${relationship.sourceCharacterId} and '
              '${relationship.targetCharacterId} at §${relationship.startChapter}');
        }
      }

      final id = await db.insert(
        'character_relationships',
        relationship.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      LoggerService.instance.i(
        '创建关系成功: $id (${relationship.relationType.name})',
        category: LogCategory.character,
        tags: ['relationship', 'create', 'success'],
      );
      return id;
    } on ArgumentError {
      rethrow;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '创建关系失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['relationship', 'create', 'error'],
      );
      rethrow;
    }
  }

  @override
  Future<int> updateRelationship(CharacterRelationship relationship) async {
    if (relationship.id == null) {
      throw ArgumentError('关系 ID 不能为空');
    }
    try {
      final db = await database;
      final count = await db.update(
        'character_relationships',
        relationship.toMap(),
        where: 'id = ?',
        whereArgs: [relationship.id],
      );
      LoggerService.instance.i(
        '更新关系成功: ${relationship.id}',
        category: LogCategory.character,
        tags: ['relationship', 'update', 'success'],
      );
      return count;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新关系失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['relationship', 'update', 'error'],
      );
      rethrow;
    }
  }

  @override
  Future<int> deleteRelationship(int relationshipId) async {
    try {
      final db = await database;
      final count = await db.delete(
        'character_relationships',
        where: 'id = ?',
        whereArgs: [relationshipId],
      );
      LoggerService.instance.i(
        '删除关系成功: $relationshipId',
        category: LogCategory.character,
        tags: ['relationship', 'delete', 'success'],
      );
      return count;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除关系失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['relationship', 'delete', 'error'],
      );
      rethrow;
    }
  }

  // ========== 图快照查询 ==========

  @override
  Future<RelationshipGraphSnapshot> getGraphSnapshot(
      String novelUrl, int chapter) async {
    final db = await database;

    // 已登场人物:firstAppearanceChapter 为空(视为§0)或 <= chapter
    final charMaps = await db.query(
      'characters',
      where:
          'novelUrl = ? AND (firstAppearanceChapter IS NULL OR firstAppearanceChapter <= ?)',
      whereArgs: [novelUrl, chapter],
      orderBy: 'createdAt ASC',
    );

    // 当前生效关系:start <= chapter AND (end 为空 OR end >= chapter)
    final relMaps = await db.query(
      'character_relationships',
      where:
          'novel_url = ? AND start_chapter <= ? AND (end_chapter IS NULL OR end_chapter >= ?)',
      whereArgs: [novelUrl, chapter, chapter],
      orderBy: 'created_at DESC',
    );

    return RelationshipGraphSnapshot(
      characters: charMaps.map(Character.fromMap).toList(),
      relationships: relMaps.map(CharacterRelationship.fromMap).toList(),
      chapter: chapter,
    );
  }

  @override
  Future<List<CharacterRelationship>> getAllRelationships(
      String novelUrl) async {
    final db = await database;
    final maps = await db.query(
      'character_relationships',
      where: 'novel_url = ?',
      whereArgs: [novelUrl],
      orderBy: 'start_chapter ASC, created_at DESC',
    );
    return maps.map(CharacterRelationship.fromMap).toList();
  }
}

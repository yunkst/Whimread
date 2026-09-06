import '../../../models/character_relationship.dart';
import '../../../models/relationship_graph_snapshot.dart';

/// 人物关系仓库接口(v2,区间模型 + 章节快照)。
///
/// 关系采用区间模型:每条关系有 [CharacterRelationship.startChapter]/
/// [CharacterRelationship.endChapter] 定义生效区间;时间轴某章节 c 下,
/// 关系生效当且仅当 `start <= c && (end == null || end >= c)`。
abstract class ICharacterRelationRepository {
  /// 创建关系。
  ///
  /// 校验:startChapter >= 0、(endChapter == null || endChapter >= startChapter);
  /// 对称类型([CharacterRelationship.relationType] 的 symmetric=true)在
  /// source/target 双向去重。冲突时抛异常(唯一约束或显式检查)。
  Future<int> createRelationship(CharacterRelationship relationship);

  /// 更新关系(必须含 id)。
  Future<int> updateRelationship(CharacterRelationship relationship);

  /// 删除关系。
  Future<int> deleteRelationship(int relationshipId);

  /// 取小说在指定章节的关系图快照:已登场人物 + 当前生效关系。
  Future<RelationshipGraphSnapshot> getGraphSnapshot(
      String novelUrl, int chapter);

  /// 取小说的全部关系(全部章节,用于编辑/管理)。
  Future<List<CharacterRelationship>> getAllRelationships(String novelUrl);
}

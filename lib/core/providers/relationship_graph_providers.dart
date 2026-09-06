import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:riverpod/riverpod.dart';
import '../../models/relationship_graph_snapshot.dart';
import 'database_providers.dart';

part 'relationship_graph_providers.g.dart';

/// 当前章节进度(0-based index)。
///
/// 默认取阅读进度 [NovelRepository.getLastReadChapter];关系图页面可通过
/// 手动滑块覆盖(覆盖值由 UI 层持有,不存于此 provider)。
@riverpod
Future<int> currentChapter(Ref ref, String novelUrl) async {
  final novelRepo = ref.watch(novelRepositoryProvider);
  return novelRepo.getLastReadChapter(novelUrl);
}

/// 关系图快照(按小说 + 章节)。
///
/// 返回该章节下已登场人物 + 生效关系的快照。
@riverpod
Future<RelationshipGraphSnapshot> relationshipGraph(
  Ref ref,
  String novelUrl,
  int chapter,
) async {
  final relationRepo = ref.watch(characterRelationRepositoryProvider);
  return relationRepo.getGraphSnapshot(novelUrl, chapter);
}

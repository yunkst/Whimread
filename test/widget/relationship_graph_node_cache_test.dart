import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/character_relationship.dart';
import 'package:novel_app/models/relation_type.dart';
import 'package:novel_app/models/relationship_graph_snapshot.dart';
import 'package:novel_app/widgets/relationship/relationship_graph_view.dart';

/// 验证 RelationshipGraphView 的增量 diff 行为:
/// - 切章节时已登场人物复用同一 Node(位置稳定)
/// - 已消失人物从 graph 移除但保留在 cache(再次出现复用)
void main() {
  testWidgets(
      '切章节时已登场人物复用同一 Node(位置稳定)',
      (tester) async {
    Character char(int id, String name, int firstChapter) => Character(
          id: id,
          novelUrl: 'n',
          name: name,
          firstAppearanceChapter: firstChapter,
        );

    final snap1 = RelationshipGraphSnapshot(
      chapter: 0,
      characters: [char(1, '甲', 0), char(2, '乙', 0)],
      relationships: [
        CharacterRelationship(
          sourceCharacterId: 1,
          targetCharacterId: 2,
          relationType: RelationType.friend,
          startChapter: 0,
          novelUrl: 'n',
        ),
      ],
    );
    final snap2 = RelationshipGraphSnapshot(
      chapter: 8,
      characters: [char(1, '甲', 0), char(2, '乙', 0), char(3, '丙', 8)],
      relationships: [
        CharacterRelationship(
          sourceCharacterId: 1,
          targetCharacterId: 2,
          relationType: RelationType.friend,
          startChapter: 0,
          novelUrl: 'n',
        ),
        CharacterRelationship(
          sourceCharacterId: 1,
          targetCharacterId: 3,
          relationType: RelationType.masterDisciple,
          startChapter: 8,
          novelUrl: 'n',
        ),
      ],
    );

    final innerKey = GlobalKey<State<RelationshipGraphView>>();
    var current = snap1;
    late StateSetter setStateOuter;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          setStateOuter = setState;
          return Material(
            child: RelationshipGraphView(key: innerKey, snapshot: current),
          );
        },
      ),
    ));
    await tester.pump();

    GraphViewState state() =>
        innerKey.currentState! as GraphViewState;

    final firstNodes = state().debugNodes();
    expect(firstNodes.length, 2);
    final firstNodeA =
        firstNodes.firstWhere((n) => n.data.id == 1);
    final firstNodeB =
        firstNodes.firstWhere((n) => n.data.id == 2);
    final firstPosA = firstNodeA.position.clone();

    // 切到 snap2(丙登场)
    setStateOuter(() => current = snap2);
    await tester.pump();

    final secondNodes = state().debugNodes();
    expect(secondNodes.length, 3, reason: '甲乙丙');
    final secondNodeA =
        secondNodes.firstWhere((n) => n.data.id == 1);
    final secondNodeB =
        secondNodes.firstWhere((n) => n.data.id == 2);
    // 关键断言:已登场人物复用同一 Node
    expect(identical(firstNodeA, secondNodeA), isTrue,
        reason: '甲复用同一 Node;fix 前会每次重建');
    expect(identical(firstNodeB, secondNodeB), isTrue,
        reason: '乙复用同一 Node');
    expect(secondNodeA.position, firstPosA,
        reason: 'position 字段一致(reuse 同一 Node)');
    // 新登场人物应是新 Node
    final secondNodeC =
        secondNodes.firstWhere((n) => n.data.id == 3);
    expect(identical(firstNodeA, secondNodeC), isFalse);
  });

  testWidgets(
      '已消失人物从 graph 移除但保留在 cache(再次出现复用)',
      (tester) async {
    Character char(int id, String name, int firstChapter) => Character(
          id: id,
          novelUrl: 'n',
          name: name,
          firstAppearanceChapter: firstChapter,
        );

    final snapFull = RelationshipGraphSnapshot(
      chapter: 0,
      characters: [char(1, '甲', 0), char(2, '乙', 0)],
      relationships: [],
    );
    final snapEmpty = RelationshipGraphSnapshot(
      chapter: 99,
      characters: [],
      relationships: [],
    );
    final snapBack = RelationshipGraphSnapshot(
      chapter: 100,
      characters: [char(1, '甲', 0), char(2, '乙', 0)],
      relationships: [],
    );

    final innerKey = GlobalKey<State<RelationshipGraphView>>();
    var current = snapFull;
    late StateSetter setStateOuter;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          setStateOuter = setState;
          return Material(
            child: RelationshipGraphView(key: innerKey, snapshot: current),
          );
        },
      ),
    ));
    await tester.pump();

    GraphViewState state() =>
        innerKey.currentState! as GraphViewState;

    final nodeA1 =
        state().debugNodes().firstWhere((n) => n.data.id == 1);
    final posA1 = nodeA1.position.clone();

    setStateOuter(() => current = snapEmpty);
    await tester.pump();
    expect(state().debugNodes(), isEmpty,
        reason: '空 snapshot 时 graph 无节点');

    setStateOuter(() => current = snapBack);
    await tester.pump();
    final nodeA3 = state()
        .debugNodes()
        .firstWhere((n) => n.data.id == 1);
    // 关键:再次出现应复用 cache 中的同一 Node
    expect(identical(nodeA1, nodeA3), isTrue,
        reason: '消失后再次出现应复用 cache 中的同一 Node');
    expect(nodeA3.position, posA1);
  });
}

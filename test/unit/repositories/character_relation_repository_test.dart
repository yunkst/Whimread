import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../../helpers/in_memory_db.dart';
import 'package:novel_app/core/interfaces/i_database_connection.dart';
import 'package:novel_app/repositories/character_relation_repository.dart';
import 'package:novel_app/models/character_relationship.dart';
import 'package:novel_app/models/relation_type.dart';

/// 直接包装 in-memory Database 的连接实现,用于测试。
class _TestConn implements IDatabaseConnection {
  final Database db;
  _TestConn(this.db);

  @override
  Future<Database> get database => Future.value(db);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  bool get isInitialized => true;
}

void main() {
  late Database db;
  late CharacterRelationRepository repo;

  setUp(() async {
    db = await setupInMemoryDb();
    repo = CharacterRelationRepository(dbConnection: _TestConn(db));
    // 造 3 个角色:甲(§0)、乙(§8)、丙(§45)
    await db.insert('characters', {
      'novelUrl': 'n',
      'name': '甲',
      'firstAppearanceChapter': 0,
      'createdAt': 0,
    });
    await db.insert('characters', {
      'novelUrl': 'n',
      'name': '乙',
      'firstAppearanceChapter': 8,
      'createdAt': 0,
    });
    await db.insert('characters', {
      'novelUrl': 'n',
      'name': '丙',
      'firstAppearanceChapter': 45,
      'createdAt': 0,
    });
  });
  tearDown(() async => db.close());

  test('§0 快照:只有甲登场,无关系', () async {
    final snap = await repo.getGraphSnapshot('n', 0);
    expect(snap.characters.map((c) => c.name), ['甲']);
    expect(snap.relationships, isEmpty);
    expect(snap.chapter, 0);
  });

test('区间重叠:朋友 §25-79 / 恋人 §80+,§50 取朋友、§80 取恋人', () async {
    await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 3,
      relationType: RelationType.friend,
      startChapter: 25,
      endChapter: 79,
      novelUrl: 'n',
    ));
    await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 3,
      relationType: RelationType.lover,
      startChapter: 80,
      novelUrl: 'n',
    ));
    expect(
        (await repo.getGraphSnapshot('n', 50)).relationships.single.relationType,
        RelationType.friend);
    expect(
        (await repo.getGraphSnapshot('n', 80)).relationships.single.relationType,
        RelationType.lover);
    expect((await repo.getGraphSnapshot('n', 24)).relationships, isEmpty);
    // end_chapter 闭区间
    expect(
        (await repo.getGraphSnapshot('n', 79)).relationships.single.relationType,
        RelationType.friend);
  });

test('校验:endChapter<startChapter 拒绝', () async {
    expect(
        () => repo.createRelationship(CharacterRelationship(
              sourceCharacterId: 1,
              targetCharacterId: 2,
              relationType: RelationType.friend,
              startChapter: 10,
              endChapter: 5,
              novelUrl: 'n',
            )),
        throwsA(isA<ArgumentError>()));
  });
}

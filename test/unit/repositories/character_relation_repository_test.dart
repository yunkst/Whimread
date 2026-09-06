import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../../helpers/in_memory_db.dart';
import 'package:novel_app/core/interfaces/i_database_connection.dart';
import 'package:novel_app/repositories/character_relation_repository.dart';
import 'package:novel_app/models/character.dart';
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

  test('§8 快照:甲乙登场,师徒关系生效', () async {
    await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 2,
      relationType: RelationType.masterDisciple,
      startChapter: 8,
      novelUrl: 'n',
    ));
    final snap = await repo.getGraphSnapshot('n', 8);
    expect(snap.characters.map((c) => c.name), containsAll(['甲', '乙']));
    expect(snap.relationships.length, 1);
    expect(snap.relationships.first.relationType, RelationType.masterDisciple);
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

  test('校验:startChapter<0 拒绝', () async {
    expect(
        () => repo.createRelationship(CharacterRelationship(
              sourceCharacterId: 1,
              targetCharacterId: 2,
              relationType: RelationType.friend,
              startChapter: -1,
              novelUrl: 'n',
            )),
        throwsA(isA<ArgumentError>()));
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

  test('对称关系去重:(A,B,friend) 与 (B,A,friend) 视为已存在', () async {
    await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 2,
      relationType: RelationType.friend,
      startChapter: 0,
      novelUrl: 'n',
    ));
    expect(
        () => repo.createRelationship(CharacterRelationship(
              sourceCharacterId: 2,
              targetCharacterId: 1,
              relationType: RelationType.friend,
              startChapter: 0,
              novelUrl: 'n',
            )),
        throwsA(isA<Object>()));
  });

  test('getAllRelationships 返回全部章节关系', () async {
    await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 2,
      relationType: RelationType.masterDisciple,
      startChapter: 8,
      novelUrl: 'n',
    ));
    await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 3,
      relationType: RelationType.rival,
      startChapter: 50,
      novelUrl: 'n',
    ));
    final all = await repo.getAllRelationships('n');
    expect(all.length, 2);
  });

  test('级联删除:删角色连带删关系', () async {
    await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 2,
      relationType: RelationType.friend,
      startChapter: 0,
      novelUrl: 'n',
    ));
    await db.delete('characters', where: 'id = ?', whereArgs: [1]);
    final snap = await repo.getGraphSnapshot('n', 99);
    expect(snap.relationships, isEmpty);
  });

  test('deleteRelationship 删除指定关系', () async {
    final id = await repo.createRelationship(CharacterRelationship(
      sourceCharacterId: 1,
      targetCharacterId: 2,
      relationType: RelationType.friend,
      startChapter: 0,
      novelUrl: 'n',
    ));
    final affected = await repo.deleteRelationship(id);
    expect(affected, 1);
    expect((await repo.getAllRelationships('n')), isEmpty);
  });
}

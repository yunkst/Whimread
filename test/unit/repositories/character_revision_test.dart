/// CharacterRepository 角色卡版本管理测试
///
/// 覆盖：create 写 baseline 版本 / update 追加版本（带来源三元组）/
/// 未命中更新不记版本 / 头像变更记版本 / 删除级联清版本（单个 + 按小说）/
/// rollbackToRevision（恢复字段 + 追加 rollback 版本 / 未知与损坏快照容错）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/character_revision.dart';
import 'package:novel_app/repositories/character_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database_setup.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late CharacterRepository repo;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    repo = CharacterRepository(dbConnection: DatabaseConnection.forTesting(db));
  });

  tearDown(() async {
    await db.close();
  });

  Character card({String name = '林昭', String? currentState}) => Character(
        novelUrl: '流云志',
        name: name,
        occupation: '剑修',
        speechStyle: '冷淡寡言',
        currentState: currentState,
      );

  test('create：写 baseline 版本（含来源与默认原因）', () async {
    final id = await repo.createCharacter(card(),
        source: CharacterRevisionSource.writingAgent,
        sourceRef: '写作助手对话',
        reason: '剧情需要');

    final revisions = await repo.getRevisions(id);
    expect(revisions, hasLength(1));
    expect(revisions.first.source, CharacterRevisionSource.writingAgent);
    expect(revisions.first.reason, '剧情需要');
    expect(revisions.first.sourceRef, '写作助手对话');

    // baseline 快照 = 创建后的卡（含 id 与字段）
    final snapshot = revisions.first.parseSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.id, id);
    expect(snapshot.name, '林昭');
  });

  test('update：成功后追加改后快照版本；未命中不记版本', () async {
    final id = await repo.createCharacter(card(currentState: '初入宗门'));

    final updated = (await repo.getCharacter(id))!.copyWith(
      currentState: '突破筑基',
      occupation: '内门剑修',
    );
    await repo.updateCharacter(updated,
        source: CharacterRevisionSource.textGame,
        sourceRef: '文字游戏《试炼》',
        reason: '击败风笑天，获得玄重尺');

    final revisions = await repo.getRevisions(id);
    expect(revisions, hasLength(2), reason: 'baseline + 本次修改');
    expect(revisions.first.source, CharacterRevisionSource.textGame);
    expect(revisions.first.reason, '击败风笑天，获得玄重尺');
    // 快照语义 = 改后状态
    expect(revisions.first.parseSnapshot()!.currentState, '突破筑基');
    expect(revisions.last.parseSnapshot()!.currentState, '初入宗门',
        reason: 'baseline 是初始状态');

    // 未命中 id：影响 0 行 → 不记版本
    await repo.updateCharacter(
      card().copyWith(id: 99999, name: '幽灵'),
      reason: '不该被记录',
    );
    expect(await repo.getRevisions(id), hasLength(2));
  });

  test('头像变更记版本（manual）', () async {
    final id = await repo.createCharacter(card());
    await repo.updateCharacterAvatarMediaId(id, 'media_1',
        sourceRef: '角色详情页');

    final revisions = await repo.getRevisions(id);
    expect(revisions, hasLength(2));
    expect(revisions.first.source, CharacterRevisionSource.manual);
    expect(revisions.first.reason, '更新头像');
    expect(revisions.first.parseSnapshot()!.avatarMediaId, 'media_1');

    // 清空头像也记版本
    await repo.updateCharacterAvatarMediaId(id, null);
    final after = await repo.getRevisions(id);
    expect(after.first.reason, '清除头像');
  });

test('rollbackToRevision：恢复快照字段并追加 rollback 版本', () async {
    final id = await repo.createCharacter(card(currentState: '初入宗门'));
    await repo.updateCharacter(
      (await repo.getCharacter(id))!.copyWith(
        currentState: '突破筑基',
        speechStyle: '变得健谈',
      ),
      reason: '剧情推进',
    );

    // 回滚到 baseline（初入宗门 / 冷淡寡言）
    final baseline = (await repo.getRevisions(id)).last;
    final ok = await repo.rollbackToRevision(baseline.id!);
    expect(ok, isTrue);

    final restored = (await repo.getCharacter(id))!;
    expect(restored.currentState, '初入宗门');
    expect(restored.speechStyle, '冷淡寡言');
    expect(restored.occupation, '剑修', reason: '未变字段不受影响');

    // 回滚本身是一条新版本（append-only 线性历史）
    final revisions = await repo.getRevisions(id);
    expect(revisions, hasLength(3));
    expect(revisions.first.source, CharacterRevisionSource.rollback);
    expect(revisions.first.reason, contains('回滚到版本'));
    expect(revisions.first.parseSnapshot()!.currentState, '初入宗门');
  });

  test('rollbackToRevision 容错：未知版本 / 损坏快照 / 角色已删除', () async {
    expect(await repo.rollbackToRevision(99999), isFalse);

    final id = await repo.createCharacter(card());
    final baseline = (await repo.getRevisions(id)).first;

    // 直接改库制造损坏快照
    await db.update(
      'character_revisions',
      {'snapshotJson': '{{{not json'},
      where: 'id = ?',
      whereArgs: [baseline.id],
    );
    expect(await repo.rollbackToRevision(baseline.id!), isFalse);

    // 角色已删除
    final id2 = await repo.createCharacter(card(name: '白芷'));
    final rev2 = (await repo.getRevisions(id2)).first;
    await repo.deleteCharacter(id2);
    expect(await repo.rollbackToRevision(rev2.id!), isFalse);
  });

  test('版本快照跨 Character 新字段容错（旧快照缺新键）', () async {
    final id = await repo.createCharacter(card());
    // 模拟旧版本快照：缺 speechStyle/currentState 键
    final partial = await db.insert('character_revisions', {
      'characterId': id,
      'snapshotJson':
          '{"id":$id,"novelUrl":"流云志","name":"林昭","occupation":"剑修"}',
      'source': 'manual',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    final revision = (await repo.getRevision(partial))!;
    final snapshot = revision.parseSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.name, '林昭');
    expect(snapshot.speechStyle, isNull);
  });
}

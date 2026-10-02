/// TextGameRepository + GameSettings 测试
///
/// 覆盖：CRUD / getByChatSessionId / 排序 / delete 级联删会话与消息 /
/// GameSettings JSON 往返（参战名单 + 玩家卡引用）/ 容错解析。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/chat_message_record.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/models/text_game.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/repositories/text_game_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database_setup.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late TextGameRepository repo;
  late ChatSessionRepository sessionRepo;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    repo = TextGameRepository(dbConnection: DatabaseConnection.forTesting(db));
    sessionRepo = ChatSessionRepository(dbConnection: DatabaseConnection.forTesting(db));
  });

  tearDown(() async {
    await db.close();
  });

  GameSettings settings({String worldview = '修仙世界'}) => GameSettings(
        worldview: worldview,
        opening: '山雨欲来',
        characterIds: const [101, 102],
        playerCharacterId: 102,
        rules: const GameRules(
          narrativeStyle: '古龙式短句',
          contentBoundary: '无露骨内容',
          choicesCount: 3,
          imagePolicy: GameImagePolicy.auto,
        ),
      );

  Future<int> insertSession(String title) => sessionRepo.createSession(
        ChatSession(scenarioId: 'text_game', title: title),
      );

  Future<int> insertGame(String title, int sessionId,
          {DateTime? lastPlayedAt,
          DateTime? createdAt,
          String? settingsJson}) =>
      repo.create(TextGame(
        title: title,
        sourceNovelId: 7,
        sourceNovelTitle: '流云志',
        settings: settingsJson != null
            ? GameSettings.fromJsonString(settingsJson)
            : settings(),
        chatSessionId: sessionId,
        lastPlayedAt: lastPlayedAt,
        createdAt: createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ));

  test('create + getById 往返：字段与设定 JSON 完整还原', () async {
    final sessionId = await insertSession('流云志·试炼');
    final id = await insertGame('流云志·试炼', sessionId);

    final game = await repo.getById(id);
    expect(game, isNotNull);
    expect(game!.title, '流云志·试炼');
    expect(game.sourceNovelId, 7);
    expect(game.chatSessionId, sessionId);
    expect(game.status, TextGameStatus.active);
    expect(game.settings.worldview, '修仙世界');
    expect(game.settings.characterIds, [101, 102]);
    expect(game.settings.playerCharacterId, 102);
    expect(game.settings.rules.choicesCount, 3);
    expect(game.settings.rules.imagePolicy, GameImagePolicy.auto);
  });

  test('getByChatSessionId 反查命中与未命中', () async {
    final sessionId = await insertSession('s1');
    await insertGame('游戏一', sessionId);

    final hit = await repo.getByChatSessionId(sessionId);
    expect(hit, isNotNull);
    expect(hit!.title, '游戏一');

    final miss = await repo.getByChatSessionId(999999);
    expect(miss, isNull);
  });

  test('listAll：按 lastPlayedAt DESC 排序，未游玩的排最后', () async {
    final now = DateTime.now();
    final s1 = await insertSession('a');
    final s2 = await insertSession('b');
    final s3 = await insertSession('c');
    await insertGame('早玩的', s1, lastPlayedAt: now.subtract(const Duration(hours: 3)));
    await insertGame('刚玩的', s2, lastPlayedAt: now);
    // 从未游玩过（lastPlayedAt 为 NULL）且回退 createdAt 也很旧 → 排最后
    await insertGame('从没玩过', s3,
        createdAt: now.subtract(const Duration(hours: 10)));

    final games = await repo.listAll();
    expect(games.map((g) => g.title).toList(), ['刚玩的', '早玩的', '从没玩过']);
  });

  test('update / updateStatus / touchLastPlayed 生效', () async {
    final sessionId = await insertSession('s1');
    final id = await insertGame('旧标题', sessionId);

    final game = (await repo.getById(id))!;
    await repo.update(game.copyWith(
        title: '新标题',
        settings: settings(worldview: '末世废土').copyWith(opening: '山雨欲来')));
    final updated = (await repo.getById(id))!;
    expect(updated.title, '新标题');
    expect(updated.settings.worldview, '末世废土');

    await repo.updateStatus(id, TextGameStatus.finished);
    expect((await repo.getById(id))!.status, TextGameStatus.finished);

    await repo.touchLastPlayed(id);
    expect((await repo.getById(id))!.lastPlayedAt, isNotNull);
  });

  test('delete 级联删除关联会话与消息，不影响其它会话', () async {
    final doomedSession = await insertSession(' doomed');
    final otherSession = await insertSession('other');
    final gameId = await insertGame('将被删除', doomedSession);

    await sessionRepo.appendMessage(ChatMessageRecord(
      sessionId: doomedSession,
      role: 'user',
      content: '开始游戏',
      timestamp: DateTime.now(),
      agentMsgIndex: 0,
    ));

    final affected = await repo.delete(gameId);
    expect(affected, 1);
    expect(await repo.getById(gameId), isNull);
    expect(await sessionRepo.getSession(doomedSession), isNull);
    expect(await sessionRepo.listMessages(doomedSession), isEmpty);
    expect(await sessionRepo.getSession(otherSession), isNotNull);
  });

  test('GameSettings JSON 往返与容错解析', () async {
    final original = settings().copyWith(worldNotes: const ['寻母线索指向北境', '血煞宗追杀令']);
    final restored = GameSettings.fromJsonString(original.toJsonString());
    expect(restored.worldview, original.worldview);
    expect(restored.opening, original.opening);
    expect(restored.characterIds, [101, 102]);
    expect(restored.playerCharacterId, 102);
    expect(restored.worldNotes, ['寻母线索指向北境', '血煞宗追杀令']);
    expect(restored.rules.narrativeStyle, '古龙式短句');
    expect(restored.rules.imagePolicy, GameImagePolicy.auto);

    // withCharacter 去重追加
    expect(original.withCharacter(102).characterIds, [101, 102],
        reason: '重复 id 不追加');
    expect(original.withCharacter(103).characterIds, [101, 102, 103]);

    // 容错：坏 JSON / 空串不抛异常，回退默认设定
    final bad = GameSettings.fromJsonString('{{{not json');
    expect(bad.worldview, isEmpty);
    expect(bad.characterIds, isEmpty);
    expect(bad.playerCharacterId, isNull);
    expect(bad.worldNotes, isEmpty);
    expect(bad.rules.choicesCount, 3);
    expect(GameSettings.fromJsonString('').rules.imagePolicy, GameImagePolicy.auto);

    // 未知枚举名回退默认值；缺 playerCharacterId/worldNotes 容忍
    final unknown = GameSettings.fromJsonString(
        '{"characterIds":[5],"rules":{"imagePolicy":"sometimes"}}');
    expect(unknown.rules.imagePolicy, GameImagePolicy.auto);
    expect(unknown.characterIds, [5]);
    expect(unknown.playerCharacterId, isNull);
    expect(unknown.worldNotes, isEmpty);
  });
}

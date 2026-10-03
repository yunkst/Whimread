/// TextGameExecutor（create/list/update_text_game）测试
///
/// 覆盖：必绑小说（source_novel_id）/ 参战名单缺省取绑定小说全部角色卡、
/// 显式传名圈定子集（名字在绑定小说内解析为行 id，取不到即报错）/
/// 创建联动落库（chat_session + text_game 双行）/ 参数校验 /
/// 同名允许（仅日志）/ 列表 / 部分字段更新 / 参战名单替换 / 未知 id。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite.dart' show Database;

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/text_game.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/services/novel_agent/tool_executor/text_game_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

final _executorProvider =
    Provider<TextGameExecutor>((ref) => TextGameExecutor(ref));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ProviderContainer container;
  late TextGameExecutor executor;
  late int novelId;
  late int npcId;
  late int npc2Id;
  late int playerId;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
    ]);
    executor = container.read(_executorProvider);

    // 绑定小说 + 角色卡（含另一本小说的干扰角色）
    final novelRepo =
        container.read(novelRepositoryProvider) as NovelRepository;
    await novelRepo.createNovel(
        title: '流云志', author: '佚名', backgroundSetting: '修仙世界');
    final novel = (await novelRepo.getNovelByUrl('流云志'))!;
    novelId = novel.id!;
    final charRepo = container.read(characterRepositoryProvider);
    npcId = await charRepo.createCharacter(Character(
        novelUrl: novel.url, name: '林昭', speechStyle: '冷淡寡言'));
    npc2Id = await charRepo.createCharacter(Character(
        novelUrl: novel.url, name: '白芷', backgroundStory: '药谷传人'));
    playerId = await charRepo.createCharacter(
        Character(novelUrl: novel.url, name: '沈砚', occupation: '书生'));
    await novelRepo.createNovel(title: '他山志', author: '佚名');
    final other = (await novelRepo.getNovelByUrl('他山志'))!;
    await charRepo.createCharacter(
        Character(novelUrl: other.url, name: '外乡人'));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Map<String, dynamic> validArgs() => {
        'title': '流云试炼',
        'source_novel_id': novelId,
        'opening': '山雨欲来，主角立于山门之前',
        // 参战名单缺省 = 绑定小说全部角色卡；仅显式传名时圈定子集
        'player_character_name': '沈砚',
        'worldview': '', // 空 = 回退小说背景设定
        'narrativeStyle': '古龙式短句',
        'contentBoundary': '无露骨内容',
        'choicesCount': 7, // 越界应被钳制到 4
        'imagePolicy': 'manual',
      };

  test('create_text_game：会话与游戏双行落库，缺省参战名单取全部角色卡', () async {
    final out = jsonDecode(await executor.createTextGame(validArgs()))
        as Map<String, dynamic>;
    expect(out['success'], true);
    final gameId = out['gameId'] as int;

    final game = (await container.read(textGameRepositoryProvider).getById(gameId))!;
    expect(game.title, '流云试炼');
    // 绑定小说由 source_novel_id 指定，标题自动取小说真实标题
    expect(game.sourceNovelId, novelId);
    expect(game.sourceNovelTitle, '流云志');
    expect(game.status, TextGameStatus.active);
    expect(game.chatSessionId, greaterThan(0));

    // 会话行：scenarioId=text_game、标题同游戏
    final session =
        await container.read(chatSessionRepositoryProvider).getSession(game.chatSessionId);
    expect(session, isNotNull);
    expect(session!.scenarioId, 'text_game');
    expect(session.title, '流云试炼');

    // 设定：未传参战名单 → 绑定小说全部角色卡入列；choicesCount 钳制到 4
    final s = game.settings;
    expect(s.characterIds, containsAll([npcId, npc2Id, playerId]));
    expect(s.playerCharacterId, playerId);
    expect(s.rules.choicesCount, 4);
    expect(s.rules.imagePolicy, GameImagePolicy.manual);
    expect(s.rules.narrativeStyle, '古龙式短句');
  });

  test('create_text_game：显式传 character_names 圈定子集', () async {
    final out = jsonDecode(await executor.createTextGame(validArgs()
      ..['character_names'] = ['林昭'])) as Map<String, dynamic>;
    expect(out['success'], true);
    final gameId = out['gameId'] as int;
    final game = (await container.read(textGameRepositoryProvider).getById(gameId))!;
    // 只留林昭，白芷不入列；玩家自动入名单
    expect(game.settings.characterIds, [npcId, playerId]);
    expect(game.settings.playerCharacterId, playerId);
  });

  test('create_text_game：必填与名字解析校验返回引导错误', () async {
    final noTitle = await executor
        .createTextGame(validArgs()..remove('title'));
    expect(noTitle, contains('missing_title'));

    final noNovel = await executor
        .createTextGame(validArgs()..remove('source_novel_id'));
    expect(noNovel, contains('missing_source_novel'));

    final badNovel = await executor
        .createTextGame(validArgs()..['source_novel_id'] = 999);
    expect(badNovel, contains('novel_not_found'));

    final noPlayer = await executor
        .createTextGame(validArgs()..remove('player_character_name'));
    expect(noPlayer, contains('missing_player_character'));

    // 绑定小说下没有的角色名 → character_not_found
    final unknownName = await executor
        .createTextGame(validArgs()..['character_names'] = ['林昭', '柳七']);
    expect(unknownName, contains('character_not_found'));

    final unknownPlayer = await executor
        .createTextGame(validArgs()..['player_character_name'] = '柳七');
    expect(unknownPlayer, contains('player_character_not_found'));

    // 外乡人属于另一本小说：名字解析限定在绑定小说内 → 同样找不到
    final foreign = await executor
        .createTextGame(validArgs()..['character_names'] = ['林昭', '外乡人']);
    expect(foreign, contains('character_not_found'));
  });

  test('同名游戏允许创建（不阻断）', () async {
    await executor.createTextGame(validArgs());
    final out =
        jsonDecode(await executor.createTextGame(validArgs())) as Map<String, dynamic>;
    expect(out['success'], true);
    expect(await container.read(textGameRepositoryProvider).listAll(), hasLength(2));
  });

  test('list_text_games：返回已创建游戏', () async {
    await executor.createTextGame(validArgs());
    final out = jsonDecode(await executor.listTextGames()) as Map<String, dynamic>;
    expect(out['count'], 1);
    expect((out['games'] as List).first['title'], '流云试炼');
    expect((out['games'] as List).first['source'], 'novel:流云志');
  });

  test('update_text_game：只改传入字段，其余保持', () async {
    final created =
        jsonDecode(await executor.createTextGame(validArgs())) as Map<String, dynamic>;
    final gameId = created['gameId'] as int;

    final out = jsonDecode(
      await executor.updateTextGame({
        'game_id': gameId,
        'title': '改名之后',
        'narrativeStyle': '压迫悬疑',
        'imagePolicy': 'auto',
        'choicesCount': 2,
      }),
    ) as Map<String, dynamic>;
    expect(out['success'], true);

    final game = (await container.read(textGameRepositoryProvider).getById(gameId))!;
    expect(game.title, '改名之后');
    expect(game.settings.rules.narrativeStyle, '压迫悬疑');
    expect(game.settings.rules.imagePolicy, GameImagePolicy.auto);
    expect(game.settings.rules.choicesCount, 2);
    // 未传字段保持
    expect(game.settings.opening, '山雨欲来，主角立于山门之前');
    expect(game.settings.characterIds, containsAll([npcId, npc2Id]));
    expect(game.sourceNovelId, novelId);
  });

  test('update_text_game：按角色名替换参战名单与玩家角色', () async {
    final created =
        jsonDecode(await executor.createTextGame(validArgs())) as Map<String, dynamic>;
    final gameId = created['gameId'] as int;

    // 只留林昭，玩家换成林昭（自动入名单）
    final out = jsonDecode(await executor.updateTextGame({
      'game_id': gameId,
      'character_names': ['林昭'],
      'player_character_name': '林昭',
    })) as Map<String, dynamic>;
    expect(out['success'], true);

    final game = (await container.read(textGameRepositoryProvider).getById(gameId))!;
    expect(game.settings.characterIds, [npcId]);
    expect(game.settings.playerCharacterId, npcId);
  });

  test('update_text_game：按角色名增量调整参战名单，玩家不可移出', () async {
    final created =
        jsonDecode(await executor.createTextGame(validArgs())) as Map<String, dynamic>;
    final gameId = created['gameId'] as int;

    // 先移除白芷再追加回来，验证两个方向
    final remove = jsonDecode(await executor.updateTextGame({
      'game_id': gameId,
      'remove_character_names': ['白芷'],
    })) as Map<String, dynamic>;
    expect(remove['success'], true);
    var game = (await container.read(textGameRepositoryProvider).getById(gameId))!;
    expect(game.settings.characterIds, [npcId, playerId],
        reason: '移除白芷，玩家角色保留');

    final add = jsonDecode(await executor.updateTextGame({
      'game_id': gameId,
      'add_character_names': ['白芷'],
    })) as Map<String, dynamic>;
    expect(add['success'], true);
    game = (await container.read(textGameRepositoryProvider).getById(gameId))!;
    expect(game.settings.characterIds, containsAll([npcId, npc2Id, playerId]));

    // 移除玩家角色 → 引导错误
    final removePlayer = await executor.updateTextGame({
      'game_id': gameId,
      'remove_character_names': ['沈砚'],
    });
    expect(removePlayer, contains('player_cannot_be_removed'));

    // 整体替换与增量互斥
    final conflict = await executor.updateTextGame({
      'game_id': gameId,
      'character_names': ['林昭'],
      'add_character_names': ['白芷'],
    });
    expect(conflict, contains('conflicting_cast_args'));

    // 追加绑定小说下不存在的角色名 → character_not_found
    final unknownAdd = await executor.updateTextGame({
      'game_id': gameId,
      'add_character_names': ['柳七'],
    });
    expect(unknownAdd, contains('character_not_found'));

    // 移除不存在的名字宽容处理（视为无操作）
    final removeUnknown = jsonDecode(await executor.updateTextGame({
      'game_id': gameId,
      'remove_character_names': ['柳七'],
    })) as Map<String, dynamic>;
    expect(removeUnknown['success'], true);
  });

  test('update_text_game：未知 id / 缺 game_id 报错', () async {
    expect(await executor.updateTextGame({'game_id': 999}),
        contains('game_not_found'));
    expect(await executor.updateTextGame({}), contains('missing_game_id'));
  });
}

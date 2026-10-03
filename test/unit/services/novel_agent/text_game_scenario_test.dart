/// TextGameScenario 测试
///
/// 覆盖：场景注册与工厂构造（共享角色卡加载）/ 工具面 / 静态系统提示词
/// （不含设定数据）/ 动态上下文设定块（角色卡渲染 + 世界观回退）/
/// narrate / speak / present_choices 校验 / update_game_state 写角色卡
/// currentState（版本记录 source=text_game）/ 游戏内 create_character
/// （建卡入名单）/ roll_random_event 概率判定（权重抽取 + 参数校验）/
/// onNoToolCalls 协议提醒。
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/character_revision.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/models/text_game.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/repositories/text_game_repository.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/agent_scenario_factory.dart';
import 'package:novel_app/services/novel_agent/scenarios/text_game_scenario.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../helpers/test_database_setup.dart';

/// 纯逻辑测试用（不触达 ref 的工具/提示词/动态上下文）
TextGameScenario _scenario({
  TextGame? game,
  Novel? novel,
  List<Character> cast = const [],
  Random? random,
}) =>
    TextGameScenario(
      _FakeRef(),
      game ?? _game(),
      novel: novel,
      cast: cast,
      random: random,
    );

/// 固定随机序列：nextDouble 恒返回 [value]（概率判定的可复现断言）
class _FixedRandom implements Random {
  final double value;
  const _FixedRandom(this.value);

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// 内存游戏对象（无 DB；角色引用用占位 id）
TextGame _game({GameImagePolicy imagePolicy = GameImagePolicy.auto}) =>
    TextGame(
      id: 1,
      title: '流云试炼',
      sourceNovelId: 10,
      sourceNovelTitle: '流云志',
      settings: GameSettings(
        worldview: '修仙世界，灵气衰竭',
        opening: '山雨欲来，主角立于山门之前',
        characterIds: const [101, 102],
        playerCharacterId: 102,
        rules: GameRules(
          narrativeStyle: '古龙式短句',
          contentBoundary: '无露骨内容',
          choicesCount: 3,
          imagePolicy: imagePolicy,
        ),
      ),
      chatSessionId: 100,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

/// 测试角色卡（与 _game 的占位 id 对应）
Character _card(int id, String name,
    {String? occupation,
    String? speechStyle,
    String? currentState,
    String? backgroundStory,
    List<String>? aliases}) {
  return Character(
    id: id,
    novelUrl: '流云志',
    name: name,
    occupation: occupation,
    speechStyle: speechStyle,
    currentState: currentState,
    backgroundStory: backgroundStory,
    aliases: aliases,
  );
}

Novel _novel() => Novel(
      id: 10,
      title: '流云志',
      author: '佚名',
      url: '流云志',
      backgroundSetting: '修仙世界，灵气衰竭',
    );

/// 场景测试不触达 ref（生图/状态/建卡工具走容器版测试），占位实现
class _FakeRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('场景注册', () {
    test('text_game 已注册：showInChatMenu=false / supportsMemory=false', () {
      final info = AgentScenarioFactory.availableScenarios
          .where((i) => i.id == ScenarioIds.textGame)
          .firstOrNull;
      expect(info, isNotNull);
      expect(info!.displayName, '文字游戏');
      expect(info.showInChatMenu, isFalse, reason: '游玩走专属页面，不出现在聊天菜单');
      expect(info.supportsMemory, isFalse);
    });

    test('其余场景默认 showInChatMenu=true（不回归）', () {
      final writing = AgentScenarioFactory.availableScenarios
          .firstWhere((i) => i.id == ScenarioIds.writing);
      expect(writing.showInChatMenu, isTrue);
    });
  });

  group('工厂构造（共享角色卡加载）', () {
    late Database db;
    late ProviderContainer container;
    late TextGameRepository repo;
    late int novelId;
    late int npcId;
    late int playerId;

    setUp(() async {
      db = await TestDatabaseSetup.createInMemoryDatabase();
      container = ProviderContainer(overrides: [
        databaseConnectionProvider
            .overrideWithValue(DatabaseConnection.forTesting(db)),
      ]);
      repo = container.read(textGameRepositoryProvider);

      final novelRepo =
          container.read(novelRepositoryProvider) as NovelRepository;
      // createNovel 返回对象不带 id → 回读取落库行
      await novelRepo.createNovel(title: '流云志', author: '佚名',
          backgroundSetting: '修仙世界，灵气衰竭');
      final novel = (await novelRepo.getNovelByUrl('流云志'))!;
      novelId = novel.id!;
      final charRepo = container.read(characterRepositoryProvider);
      npcId = await charRepo.createCharacter(
          Character(novelUrl: novel.url, name: '林昭'));
      playerId = await charRepo.createCharacter(
          Character(novelUrl: novel.url, name: '沈砚'));
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> createGameRow(List<int> castIds, int playerId) async {
      final sessionRepo = container.read(chatSessionRepositoryProvider);
      final sessionId = await sessionRepo.createSession(ChatSession(
        scenarioId: ScenarioIds.textGame,
        title: '流云试炼',
      ));
      final id = await repo.create(TextGame(
        title: '流云试炼',
        sourceNovelId: novelId,
        sourceNovelTitle: '流云志',
        settings: GameSettings(
          worldview: '',
          opening: '开场',
          characterIds: castIds,
          playerCharacterId: playerId,
        ),
        chatSessionId: sessionId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      final created = (await repo.getById(id))!;
      await repo.update(created.copyWith(chatSessionId: sessionId));
      return id;
    }

    Future<AgentScenario> buildScenario(int gameId) {
      final buildProvider = FutureProvider<AgentScenario>((ref) async {
        return AgentScenarioFactory(ref).build(
          ScenarioIds.textGame,
          AgentScenarioContext(
            scenarioId: ScenarioIds.textGame,
            textGameId: gameId,
          ),
        );
      });
      return container.read(buildProvider.future);
    }

    test('缺 textGameId → ArgumentError', () async {
      final buildProvider = FutureProvider<AgentScenario>((ref) async {
        return AgentScenarioFactory(ref).build(
          ScenarioIds.textGame,
          const AgentScenarioContext(scenarioId: ScenarioIds.textGame),
        );
      });
      await expectLater(
        container.read(buildProvider.future),
        throwsArgumentError,
      );
    });

    test('游戏存在 → 构造 TextGameScenario（动态块渲染共享角色卡）', () async {
      final gameId = await createGameRow([npcId, playerId], playerId);
      final scenario = await buildScenario(gameId);
      expect(scenario, isA<TextGameScenario>());
      expect(scenario.id, ScenarioIds.textGame);
      expect(scenario.streamableToolNames, {'narrate', 'speak'});

      final block =
          scenario.buildDynamicContext(const AgentScenarioContext());
      expect(block, contains('- 林昭'), reason: '参战名单角色卡被渲染');
      expect(block, contains('- 沈砚'), reason: '玩家角色卡被渲染');
      expect(block, contains('修仙世界'),
          reason: 'worldview 空 → 回退小说背景设定');
      expect(block, contains('玩家本回合'),
          reason: '设定块结尾显式划界：玩家输入不再与规则列表粘连');
    });

    test('小说被删除 → 构造不失败，动态块给出降级提示', () async {
      final gameId = await createGameRow([npcId, playerId], playerId);
      await (container.read(novelRepositoryProvider) as NovelRepository)
          .removeFromBookshelf('流云志');
      final removed = await (container.read(novelRepositoryProvider) as NovelRepository)
          .getNovelByUrl('流云志');
      expect(removed, isNull);
      final scenario = await buildScenario(gameId);
      final block =
          scenario.buildDynamicContext(const AgentScenarioContext());
      expect(block, contains('绑定的小说已不存在'));
    });
  });

  group('工具面', () {
    test('7 个回合工具（含生图/状态回写/游戏内建卡/概率判定）', () {
      final names =
          _scenario().tools.map((t) => t['function']['name'] as String).toSet();
      expect(names, {
        'narrate',
        'speak',
        'present_choices',
        'create_scene_image',
        'update_game_state',
        'create_character',
        'roll_random_event',
      });
    });

    test('manual 策略不含生图工具，其余工具仍在', () {
      final names = _scenario(game: _game(imagePolicy: GameImagePolicy.manual))
          .tools
          .map((t) => t['function']['name'] as String)
          .toSet();
      expect(names, isNot(contains('create_scene_image')));
      expect(names, contains('roll_random_event'));
    });
  });

  group('静态系统提示词', () {
    test('包含身份/协议/指针，不包含设定数据（数据走动态块）', () {
      final prompt = _scenario(
        novel: _novel(),
        cast: [_card(101, '林昭', occupation: '剑修')],
      ).buildSystemPrompt(const AgentScenarioContext());
      // 身份与协议
      expect(prompt, contains('流云试炼'));
      expect(prompt, contains('游戏主持人'));
      expect(prompt, contains('游戏当前状态'), reason: '指针：设定数据在动态块');
      expect(prompt, contains('narrate'));
      expect(prompt, contains('speak'));
      expect(prompt, contains('present_choices'));
      expect(prompt, contains('create_scene_image'));
      expect(prompt, contains('update_game_state'));
      expect(prompt, contains('create_character'), reason: '游戏内建新角色指引');
      expect(prompt, contains('roll_random_event'), reason: '概率判定指引');
      expect(prompt, contains('同步'));
      expect(prompt, contains('重大且持久'), reason: '状态回写的触发阈值');
      // 设定数据不得出现在静态提示词（保证前缀稳定可缓存）
      expect(prompt, isNot(contains('修仙世界，灵气衰竭')));
      expect(prompt, isNot(contains('林昭')));
    });
  });

  group('动态上下文设定块', () {
    test('完整渲染角色卡档案/近况条目/玩家卡/世界与剧情线', () {
      final game = _game().copyWith(
          settings: _game()
              .settings
              .copyWith(worldNotes: const ['寻母线索指向北境雪城']));
      final block = _scenario(
        novel: _novel(),
        game: game,
        cast: [
          _card(101, '林昭',
              occupation: '剑修',
              speechStyle: '冷淡寡言',
              currentState: '历经草原一行，开始信任主角'),
          _card(102, '沈砚',
              occupation: '书生',
              backgroundStory: '寻母',
              currentState: '魂力二十级\n携一封残信'),
        ],
      ).buildDynamicContext(const AgentScenarioContext());
      expect(block, contains('游戏当前状态'));
      expect(block, contains('修仙世界，灵气衰竭'));
      expect(block, contains('山雨欲来，主角立于山门之前'));
      expect(block, contains('- 林昭：剑修（说话风格：冷淡寡言）'));
      expect(block, contains('近况：'));
      expect(block, contains('· 历经草原一行，开始信任主角'), reason: '近况逐条渲染');
      expect(block, contains('- 沈砚：书生；来历与目标：寻母'));
      expect(block, contains('· 魂力二十级'), reason: '多行条目逐条渲染');
      expect(block, contains('· 携一封残信'));
      expect(block, contains('3 个选项'));
      expect(block, contains('古龙式短句'));
      expect(block, contains('无露骨内容'));
      expect(block, contains('《流云志》'));
      expect(block, contains('主动调用 create_scene_image'));
      // 玩家卡不出现在可扮演角色列表
      expect(block, contains('不要代其行动'));
      // 世界与剧情线小节
      expect(block, contains('世界与剧情线'));
      expect(block, contains('· 寻母线索指向北境雪城'));
    });

    test('worldview 空 → 回退小说背景设定；worldNotes 空 → 提示记录方式', () {
      final game = _game().copyWith(
          settings: _game()
              .settings
              .copyWith(worldview: '', characterIds: [101], playerCharacterId: 102));
      final block = _scenario(
        novel: _novel(),
        game: game,
        cast: [_card(101, '林昭'), _card(102, '沈砚')],
      ).buildDynamicContext(const AgentScenarioContext());
      expect(block, contains('修仙世界，灵气衰竭'), reason: '来自 novel.backgroundSetting');
      expect(block, contains('暂无记录'));
      expect(block, contains('target="world"'));
    });

    test('manual 策略：插图规则为仅玩家要求时调用', () {
      final block = _scenario(
        game: _game(imagePolicy: GameImagePolicy.manual),
        novel: _novel(),
        cast: [_card(101, '林昭'), _card(102, '沈砚')],
      ).buildDynamicContext(const AgentScenarioContext());
      expect(block, contains('仅当玩家明确要求插图时才调用'));
    });
  });

  group('executeTool', () {
    test('narrate：正常 ok / 空 text 报错', () async {
      final s = _scenario(
        novel: _novel(),
        cast: [_card(101, '林昭'), _card(102, '沈砚')],
      );
      expect(await s.executeTool('narrate', {'text': '风起了'}), '{"ok":true}');
      final bad = await s.executeTool('narrate', {'text': '  '});
      expect(bad, contains('empty_text'));
    });

    test('speak：已知角色（含别名）ok / 未知角色报错并列出可选', () async {
      final s = _scenario(
        novel: _novel(),
        cast: [
          _card(101, '林昭', aliases: ['林师姐']),
          _card(102, '沈砚'),
        ],
      );
      expect(
        await s.executeTool('speak', {'character': '林昭', 'text': '拔剑。'}),
        '{"ok":true}',
      );
      expect(
        await s.executeTool('speak', {'character': '林师姐', 'text': '拔剑。'}),
        '{"ok":true}',
        reason: '别名也算已知角色',
      );
      final unknown = await s.executeTool('speak', {'character': '路人甲', 'text': '嘿'});
      expect(unknown, contains('unknown_character'));
      expect(unknown, contains('林昭'));
    });

    test('present_choices：2-4 项 ok / 1 项太少 / 5 项太多 / 字符串数组宽容', () async {
      final s = _scenario();
      final two = await s.executeTool('present_choices', {
        'choices': [
          {'label': '拔剑'},
          {'label': '转身离开', 'hint': '风险低'},
        ],
      });
      expect(two, contains('"ok":true'));

      final few = await s.executeTool('present_choices', {
        'choices': [
          {'label': '只有一个'},
        ],
      });
      expect(few, contains('too_few_choices'));

      final many = await s.executeTool('present_choices', {
        'choices': [
          {'label': 'a'},
          {'label': 'b'},
          {'label': 'c'},
          {'label': 'd'},
          {'label': 'e'},
        ],
      });
      expect(many, contains('too_many_choices'));

      final lenient = await s.executeTool('present_choices', {
        'choices': ['选项一', '选项二'],
      });
      expect(lenient, contains('"ok":true'));
    });

    test('未知工具报错', () async {
      final s = _scenario();
      final out = await s.executeTool('list_novels', {});
      expect(out, contains('unknown_tool'));
    });
  });

  group('roll_random_event 概率判定', () {
    List<Map<String, dynamic>> branches() => const [
          {'label': '战斗胜利', 'weight': 70},
          {'label': '战斗失败', 'weight': 30},
        ];

    test('纯函数边界：权重 70/30，point 落点决定分支', () {
      final events = [
        const WeightedEvent(label: '胜利', weight: 70),
        const WeightedEvent(label: '失败', weight: 30),
      ];
      expect(pickWeightedEvent(events, 0).label, '胜利');
      expect(pickWeightedEvent(events, 69.9).label, '胜利');
      expect(pickWeightedEvent(events, 70).label, '失败');
      expect(pickWeightedEvent(events, 99.999).label, '失败');
      // 三分支等权重
      final three = [
        const WeightedEvent(label: 'a', weight: 1),
        const WeightedEvent(label: 'b', weight: 1),
        const WeightedEvent(label: 'c', weight: 1),
      ];
      expect(pickWeightedEvent(three, 2).label, 'c');
    });

    test('正常判定：固定随机 0.0 → 命中首个分支，百分比归一化', () async {
      final s = _scenario(random: const _FixedRandom(0.0));
      final out = jsonDecode(await s.executeTool('roll_random_event', {
        'events': branches(),
        'reason': '主角挑战守山弟子',
      })) as Map<String, dynamic>;
      expect(out['ok'], true);
      expect(out['selected'], '战斗胜利');
      expect(out['selectedPercent'], '70%');
      expect((out['branches'] as List), hasLength(2));
      expect((out['branches'] as List)[1]['percent'], '30%');
      expect(out['note'], contains('战斗胜利'));
      expect(out['note'], contains('不得改写'));
    });

    test('固定随机 0.99 → 落点越过首个分支权重，命中后者', () async {
      final s = _scenario(random: const _FixedRandom(0.99));
      final out = jsonDecode(
          await s.executeTool('roll_random_event', {'events': branches()}))
          as Map<String, dynamic>;
      expect(out['selected'], '战斗失败');
    });

    test('权重省略视为 1（等概率）；字符串数字权重宽容解析', () async {
      final s = _scenario(random: const _FixedRandom(0.0));
      final equal = jsonDecode(await s.executeTool('roll_random_event', {
        'events': [
          {'label': '发现密道'},
          {'label': '一无所获'},
        ],
      })) as Map<String, dynamic>;
      expect(equal['ok'], true);
      expect(equal['selectedPercent'], '50%');

      final stringWeight = jsonDecode(await s.executeTool('roll_random_event', {
        'events': [
          {'label': '触发陷阱', 'weight': '20'},
          {'label': '安全通过', 'weight': '80'},
        ],
      })) as Map<String, dynamic>;
      expect(stringWeight['ok'], true);
      expect(stringWeight['selected'], '触发陷阱');
      expect(stringWeight['selectedPercent'], '20%');
    });

    test('参数校验：缺 events / 单分支 / 超量 / 非法权重 / 缺 label', () async {
      final s = _scenario();
      final missing = await s.executeTool('roll_random_event', {});
      expect(missing, contains('missing_events'));

      final few = await s.executeTool('roll_random_event', {
        'events': [
          {'label': '只有一个', 'weight': 5},
        ],
      });
      expect(few, contains('too_few_events'));

      final many = await s.executeTool('roll_random_event', {
        'events': List.generate(7, (i) => {'label': '分支$i'}),
      });
      expect(many, contains('too_many_events'));

      final badWeight = await s.executeTool('roll_random_event', {
        'events': [
          {'label': '胜利', 'weight': 0},
          {'label': '失败', 'weight': -1},
        ],
      });
      expect(badWeight, contains('invalid_weight'));

      final badParse = await s.executeTool('roll_random_event', {
        'events': [
          {'label': '胜利', 'weight': '很多'},
          {'label': '失败', 'weight': 1},
        ],
      });
      expect(badParse, contains('invalid_weight'));

      final noLabel = await s.executeTool('roll_random_event', {
        'events': [
          {'weight': 1},
          {'label': '失败', 'weight': 1},
        ],
      });
      expect(noLabel, contains('invalid_event'));
    });
  });

  group('update_game_state 账本 + create_character', () {
    late Database db;
    late ProviderContainer container;
    late TextGameRepository repo;

    setUp(() async {
      db = await TestDatabaseSetup.createInMemoryDatabase();
      container = ProviderContainer(overrides: [
        databaseConnectionProvider
            .overrideWithValue(DatabaseConnection.forTesting(db)),
      ]);
      repo = container.read(textGameRepositoryProvider);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    /// 建小说 + 角色卡 + 库中游戏，返回经工厂构造的场景（与生产同路径加载卡）
    Future<(TextGameScenario, TextGame, int, int)> makeScenario() async {
      final novelRepo =
          container.read(novelRepositoryProvider) as NovelRepository;
      await novelRepo.createNovel(title: '流云志', author: '佚名');
      final novel = (await novelRepo.getNovelByUrl('流云志'))!;
      final charRepo = container.read(characterRepositoryProvider);
      final npcId = await charRepo.createCharacter(Character(
        novelUrl: novel.url,
        name: '林昭',
        occupation: '剑修',
        speechStyle: '冷淡寡言',
        currentState: '历经草原一行，开始信任主角',
      ));
      final playerId = await charRepo.createCharacter(Character(
        novelUrl: novel.url,
        name: '沈砚',
        occupation: '书生',
        backgroundStory: '寻母',
      ));

      final sessionRepo = container.read(chatSessionRepositoryProvider);
      final sessionId = await sessionRepo.createSession(ChatSession(
        scenarioId: ScenarioIds.textGame,
        title: '流云试炼',
      ));
      final gameId = await repo.create(TextGame(
        title: '流云试炼',
        sourceNovelId: novel.id,
        sourceNovelTitle: '流云志',
        settings: GameSettings(
          worldview: '修仙世界，灵气衰竭',
          opening: '开场',
          characterIds: [npcId, playerId],
          playerCharacterId: playerId,
          rules: const GameRules(choicesCount: 3),
        ),
        chatSessionId: sessionId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final buildProvider = FutureProvider<AgentScenario>((ref) async {
        return AgentScenarioFactory(ref).build(
          ScenarioIds.textGame,
          AgentScenarioContext(
            scenarioId: ScenarioIds.textGame,
            textGameId: gameId,
          ),
        );
      });
      final scenario =
          await container.read(buildProvider.future) as TextGameScenario;
      final game = (await repo.getById(gameId))!;
      return (scenario, game, npcId, playerId);
    }

    test('角色账本：add 新增条目（旧散文为既有条目，不覆盖丢失）+ 版本记录', () async {
      final (s, game, npcId, _) = await makeScenario();
      final out = jsonDecode(await s.executeTool('update_game_state', {
        'character_name': '林昭',
        'add_facts': ['击败风笑天，获玄重尺'],
        'reason': '大斗魂场首胜',
      })) as Map<String, dynamic>;
      expect(out['ok'], true);
      expect(out['changed'], true);
      // 旧散文退化为条目 + 新条目共存
      expect(out['currentFacts'],
          containsAll(['历经草原一行，开始信任主角', '击败风笑天，获玄重尺']));

      final charRepo = container.read(characterRepositoryProvider);
      final npc = (await charRepo.getCharacter(npcId))!;
      expect(npc.currentState,
          '历经草原一行，开始信任主角\n击败风笑天，获玄重尺');
      final revisions = await charRepo.getRevisions(npcId);
      expect(revisions.first.source, CharacterRevisionSource.textGame);
      expect(revisions.first.reason, '大斗魂场首胜');
      expect(game.id, isNotNull);
    });

    test('remove 按包含匹配划掉条目；未命中进入引导', () async {
      final (s, _, npcId, playerId) = await makeScenario();
      final out = jsonDecode(await s.executeTool('update_game_state', {
        'character_name': '林昭',
        'remove_facts': ['草原一行'], // 包含匹配「历经草原一行，开始信任主角」
        'add_facts': ['对朝廷敌意更深'],
      })) as Map<String, dynamic>;
      expect(out['ok'], true);
      expect(out['removed'], ['历经草原一行，开始信任主角']);
      expect(out['currentFacts'], ['对朝廷敌意更深']);

      final charRepo = container.read(characterRepositoryProvider);
      expect((await charRepo.getCharacter(npcId))!.currentState, '对朝廷敌意更深');

      // 未命中：changed=false（只有 remove 且没命中）+ 引导
      final miss = jsonDecode(await s.executeTool('update_game_state',
          {'character_name': '林昭', 'remove_facts': ['不存在的条目']}))
          as Map<String, dynamic>;
      expect(miss['ok'], true);
      expect(miss['changed'], false);
      expect(miss['note'], contains('remove 未命中'));
      expect(miss['currentFacts'], ['对朝廷敌意更深']);

      // 玩家卡不受影响
      expect(
          (await charRepo.getCharacter(playerId))!.currentState, isNull);
    });

    test('玩家状态：省略 character_name 写玩家卡；去重不重复添加', () async {
      final (s, _, _, playerId) = await makeScenario();
      final out = jsonDecode(await s.executeTool('update_game_state', {
        'add_facts': ['魂力突破二十级'],
      })) as Map<String, dynamic>;
      expect(out['ok'], true);

      final again = jsonDecode(await s.executeTool('update_game_state', {
        'add_facts': ['魂力突破二十级'],
      })) as Map<String, dynamic>;
      expect(again['changed'], false, reason: '精确去重');

      final charRepo = container.read(characterRepositoryProvider);
      expect((await charRepo.getCharacter(playerId))!.currentState,
          '魂力突破二十级');
    });

    test('条目上限：超过 8 条进入 notAdded 引导', () async {
      final (s, _, npcId, _) = await makeScenario();
      final facts = List.generate(9, (i) => '事实${i + 1}');
      final out = jsonDecode(await s.executeTool('update_game_state', {
        'character_name': '林昭',
        'add_facts': facts,
      })) as Map<String, dynamic>;
      expect(out['ok'], true);
      expect((out['currentFacts'] as List), hasLength(8));
      expect(out['note'], contains('上限'));
      expect(out['note'], contains('事实9'));

      final charRepo = container.read(characterRepositoryProvider);
      expect(
          gameStateEntries((await charRepo.getCharacter(npcId))!.currentState),
          hasLength(8));
    });

    test('world 目标：写 settings_json.worldNotes；与 character_name 冲突报错', () async {
      final (s, game, _, _) = await makeScenario();
      final out = jsonDecode(await s.executeTool('update_game_state', {
        'target': 'world',
        'add_facts': ['皇斗战队开始注意到沈砚'],
        'reason': '首胜引关注',
      })) as Map<String, dynamic>;
      expect(out['ok'], true);

      final fresh = (await repo.getById(game.id!))!;
      expect(fresh.settings.worldNotes, ['皇斗战队开始注意到沈砚']);

      final conflict = await s.executeTool('update_game_state', {
        'target': 'world',
        'character_name': '林昭',
        'add_facts': ['x'],
      });
      expect(conflict, contains('conflicting_target'));
    });

    test('空参数 / 超长条目 / 未知角色报错', () async {
      final (s, _, npcId, _) = await makeScenario();
      final empty = await s.executeTool('update_game_state', {});
      expect(empty, contains('empty_facts'));

      final tooLong = await s.executeTool('update_game_state', {
        'add_facts': ['长' * 61],
      });
      expect(tooLong, contains('fact_too_long'));

      final unknown = await s.executeTool('update_game_state', {
        'character_name': '路人甲',
        'add_facts': ['x'],
      });
      expect(unknown, contains('unknown_character'));

      // 校验失败不落库
      final charRepo = container.read(characterRepositoryProvider);
      expect((await charRepo.getCharacter(npcId))!.currentState,
          '历经草原一行，开始信任主角');
    });

    test('create_character：建卡入名单 + 版本记录', () async {
      final (s, game, _, _) = await makeScenario();
      final out = jsonDecode(await s.executeTool('create_character', {
        'name': '韩铁匠',
        'identity': '铁匠',
        'speech_style': '粗声粗气',
        'reason': '剧情引入：武器店老板',
      })) as Map<String, dynamic>;
      expect(out['ok'], true);

      // 卡已建（含版本记录）
      final charRepo = container.read(characterRepositoryProvider);
      final card =
          await charRepo.findCharacterByName('流云志', '韩铁匠');
      expect(card, isNotNull);
      expect(card!.occupation, '铁匠');
      final revisions = await charRepo.getRevisions(card.id!);
      expect(revisions.first.source, CharacterRevisionSource.textGame);
      expect(revisions.first.reason, '剧情引入：武器店老板');

      // 已加入参战名单
      final fresh = (await repo.getById(game.id!))!;
      expect(fresh.settings.characterIds, contains(card.id));
    });

    test('create_character：同名已有卡 → 复用并加入名单，不重复建卡', () async {
      final (s, game, npcId, _) = await makeScenario();
      final out = jsonDecode(await s.executeTool('create_character',
          {'name': '林昭', 'reason': '误报的新角色'})) as Map<String, dynamic>;
      expect(out['ok'], true);
      expect(out['characterId'], npcId, reason: '复用已有卡');

      final charRepo = container.read(characterRepositoryProvider);
      expect((await charRepo.getCharacters('流云志')).where((c) => c.name == '林昭'),
          hasLength(1));

      final fresh = (await repo.getById(game.id!))!;
      expect(fresh.settings.characterIds, contains(npcId));
    });
  });

  group('onNoToolCalls 协议提醒', () {
    test('首次返回带标记的提醒，之后不再注入', () async {
      final s = _scenario();
      final first = await s.onNoToolCalls(const []);
      expect(first, isNotNull);
      expect(first, contains(kGameProtocolNudge));
      expect(first, contains('narrate'));
      expect(first, contains('present_choices'));
      final second = await s.onNoToolCalls(const []);
      expect(second, isNull);
    });
  });
}

/// SideStoryScenario 场景测试
///
/// 覆盖：
/// - 工具面锁定：白名单 7 个工具，未知名返回 unknown_tool
/// - factory：sideStoryTarget 缺失抛 ArgumentError；注入后正确构造并绑定宿主 id
/// - create_side_story：真建番外行（isSideStory=1、锚点正确）+ 同 run 防重复
/// - list_chapters / read_chapter_content：锁定宿主上下文的返回形态
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/agent_scenario_factory.dart';
import 'package:novel_app/services/novel_agent/scenarios/side_story_scenario.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Database db;
  late int anchorNovelId;

  const target = SideStoryTarget(
    anchorNovelUrl: 'custom://side-anchor-test',
    anchorNovelTitle: '宿主小说',
    anchorChapterUrl: 'custom://side-anchor-test#ch1',
    anchorChapterTitle: '第1章 女主登场',
    requirement: '写女主的童年往事',
  );

  /// Ref 注入桩：与 set_novel_cover_test 同模式
  final scenarioFactoryProvider =
      Provider<AgentScenarioFactory>((ref) => AgentScenarioFactory(ref));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
    ]);
    anchorNovelId = await container
        .read(bookshelfMutationProvider.notifier)
        .addNovel(
          Novel(title: '宿主小说', author: '作者', url: 'custom://side-anchor-test'),
        );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  SideStoryScenario buildScenario() {
    final scenarioProvider = Provider<AgentScenario>(
        (ref) => SideStoryScenario(ref, target));
    final scenario =
        container.read(scenarioProvider) as SideStoryScenario;
    scenario.bindAnchorNovelId(anchorNovelId);
    return scenario;
  }

  group('工具面锁定', () {
    test('白名单恰为 7 个工具，无改写/删除宿主章节的能力', () {
      final scenario = buildScenario();
      final names =
          scenario.tools.map((t) => t['function']['name'] as String).toSet();
      expect(names, {
        'read_chapter_content',
        'list_chapters',
        'list_characters',
        'create_side_story',
        'save_chapter',
        'list_prompt_tags',
        'get_prompt_tag',
      });
      expect(names.contains('update_chapter_content'), isFalse,
          reason: '番外场景不能改宿主章节');
      expect(names.contains('delete_chapter'), isFalse);
      expect(names.contains('create_chapter'), isFalse,
          reason: 'create_chapter 已移除：正文由 Agent 在回复中直接写出');
    });

    test('executeTool 未知名返回 unknown_tool', () async {
      final scenario = buildScenario();
      final result = await scenario.executeTool('hack_the_host', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'unknown_tool');
    });

    test('executeTool save_chapter 在未建番外时返回 no_side_story 引导', () async {
      final scenario = buildScenario();
      final result = await scenario.executeTool('save_chapter', {
        'position': 1,
        'content': '正文' * 200,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_side_story');
      expect(json['suggested_tool'], 'create_side_story');
    });
  });

  group('factory 构造', () {
    test('availableScenarios 注册 side_story 且不在聊天菜单出现', () {
      final info = AgentScenarioFactory.availableScenarios
          .firstWhere((i) => i.id == ScenarioIds.sideStory);
      expect(info.displayName, '番外创作');
      expect(info.showInChatMenu, isFalse,
          reason: '程序化启动场景，不进手动场景菜单');
      expect(info.supportsMemory, isFalse,
          reason: '无 patch_memory，复用写作场景记忆（只读）');
    });

    test('缺 sideStoryTarget 时抛 ArgumentError', () async {
      final factory = container.read(scenarioFactoryProvider);
      expect(
        () => factory.build(ScenarioIds.sideStory, const AgentScenarioContext()),
        throwsArgumentError,
      );
    });

    test('注入 target 后构造场景并绑定宿主 id（list_characters 走宿主）', () async {
      final factory = container.read(scenarioFactoryProvider);
      final scenario = await factory.build(
        ScenarioIds.sideStory,
        const AgentScenarioContext(sideStoryTarget: target),
      );
      expect(scenario, isA<SideStoryScenario>());
      // 绑定成功：list_characters 解析宿主 id 而非返回 no_current_novel
      final result = await scenario.executeTool('list_characters', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json.containsKey('error'), isFalse,
          reason: '宿主 id 已绑定，应正常返回（空角色列表）');
    });
  });

  group('create_side_story', () {
    test('建番外行（isSideStory=1、锚点正确）并写入宿主 novelUrl 下', () async {
      final scenario = buildScenario();
      final result = await scenario
          .executeTool('create_side_story', {'title': '闺蜜往事'});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['sideStoryTitle'], '闺蜜往事');
      expect(json['sideStoryUrl'], startsWith('custom://sidestory/'));

      final rows = await db.query(
        'bookshelf',
        where: 'isSideStory = 1',
      );
      expect(rows, hasLength(1));
      expect(rows.single['title'], '闺蜜往事');
      expect(rows.single['anchorNovelUrl'], target.anchorNovelUrl);
      expect(rows.single['anchorChapterUrl'], target.anchorChapterUrl);
      expect(rows.single['description'], target.requirement,
          reason: '需求描述落库，供跨回合幂等查库复用');
    });

    test('同 run 二次调用返回 already_created，不重复建行', () async {
      final scenario = buildScenario();
      await scenario.executeTool('create_side_story', {'title': '闺蜜往事'});
      final again = await scenario
          .executeTool('create_side_story', {'title': '另一个名字'});
      final json = jsonDecode(again) as Map<String, dynamic>;
      expect(json['error'], 'already_created');

      final rows = await db.query('bookshelf', where: 'isSideStory = 1');
      expect(rows, hasLength(1), reason: '不产生第二个番外');
    });

    test('跨 run 幂等：场景重建后同需求查库复用已建番外', () async {
      // 第一回合：建番外
      final first = buildScenario();
      final r1 = await first.executeTool('create_side_story', {'title': '闺蜜往事'});
      final j1 = jsonDecode(r1) as Map<String, dynamic>;
      // 第二回合：fresh 场景实例（模拟 factory 每 run 重建）
      final second = buildScenario();
      final r2 = await second.executeTool('create_side_story', {'title': '新标题'});
      final j2 = jsonDecode(r2) as Map<String, dynamic>;
      expect(j2['success'], isTrue);
      expect(j2['sideStoryId'], j1['sideStoryId'],
          reason: '相同锚点章+相同需求 → 复用已有番外，不重复创建');
      final rows = await db.query('bookshelf', where: 'isSideStory = 1');
      expect(rows, hasLength(1));
    });
  });

  group('save_chapter 落库链路', () {
    /// 建番外并返回场景（上下文已切到番外）
    Future<AgentScenario> createThenBuild() async {
      final scenario = buildScenario();
      await scenario.executeTool('create_side_story', {'title': '闺蜜往事'});
      return scenario;
    }

    test('正文达标 → 落库到番外（宿主章节不受影响）', () async {
      final scenario = await createThenBuild();
      final content = '第一章正文。\n\n${'林晚与苏晴的往事段落。' * 40}';
      final result = await scenario.executeTool('save_chapter', {
        'position': 1,
        'title': '初遇',
        'content': content,
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: 'result=$result');
      expect(json['chapterTitle'], '初遇');
      expect(json['position'], 1);

      // 章节落在番外 novelUrl 下，宿主小说无新增章节
      final sideChapters = await db.query(
        'novel_chapters',
        where: 'chapterUrl = ?',
        whereArgs: [json['chapterUrl']],
      );
      expect(sideChapters, hasLength(1));
      expect(sideChapters.single['title'], '初遇');
      expect(sideChapters.single['novelUrl'], startsWith('custom://sidestory/'));

      final hostChapters = await db.query(
        'novel_chapters',
        where: 'novelUrl = ?',
        whereArgs: [target.anchorNovelUrl],
      );
      expect(hostChapters, isEmpty,
          reason: '宿主小说（测试夹具未种子章节）不应新增章节');
    });

    test('正文低于 300 字下限 → content_too_short，不落库', () async {
      final scenario = await createThenBuild();
      final result = await scenario.executeTool('save_chapter', {
        'position': 1,
        'title': '初遇',
        'content': '太短的正文。',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'content_too_short');
      expect(json['message'], contains('300'));

      final chapters = await db.query('novel_chapters');
      expect(chapters, isEmpty, reason: '残缺正文不得入库');
    });

    test('position 越界 → position_out_of_range 引导', () async {
      final scenario = await createThenBuild();
      final result = await scenario.executeTool('save_chapter', {
        'position': 2, // 番外尚无章节，有效位置只有 1
        'content': '第一章正文。\n\n${'段落。' * 60}',
      });
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'position_out_of_range');
      expect(json['suggested_tool'], 'list_chapters');
    });
  });

  group('宿主上下文锁定', () {
    test('list_chapters 返回宿主章节列表并标注番外不可见', () async {
      final scenario = buildScenario();
      final result = await scenario.executeTool('list_chapters', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['novelTitle'], '宿主小说');
      expect(json['anchorChapter'], '第1章 女主登场');
      expect((json['chapters'] as List), isEmpty);
      expect(json['note'], contains('番外'));
    });

    test('read_chapter_content 锚点章未缓存时返回 not_cached', () async {
      final scenario = buildScenario();
      final result = await scenario.executeTool('read_chapter_content', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'not_cached');
    });
  });
}

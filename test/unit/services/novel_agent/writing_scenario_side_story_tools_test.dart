/// 主聊番外创作工具链路测试（create_side_story / save_side_story_chapter /
/// list_side_stories —— 番外创作并入主聊后的核心行为）
///
/// 覆盖：
/// - create：阅读态锚点 / anchorChapterPosition 锚点 / 无锚点引导 /
///   幂等复用 / 宿主表零写入
/// - save：写番外命名空间（宿主正文不变）/ 无目标 no_side_story / 300 字
///   下限闸门 / 结果携带 sideStoryChapterCount
/// - writing 场景分支：create 后 _syncSideStoryTarget → 同场景实例的
///   save 立即可用（同轮后续工具调用）
/// - list：列出已建番外
///
/// 运行:
///   cd novel_builder
///   flutter test test/unit/services/novel_agent/writing_scenario_side_story_tools_test.dart
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/reading_context_providers.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/scenarios/writing_scenario.dart';
import 'package:novel_app/services/novel_agent/tool_executor/chapter_read_executor.dart';
import 'package:novel_app/services/novel_agent/tool_executor/chapter_write_executor.dart';
import 'package:novel_app/services/novel_agent/tool_executor/side_story_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

final _sideStoryExecutorProvider = Provider<SideStoryExecutor>((ref) {
  return SideStoryExecutor(ref);
});

final _chapterReadExecutorProvider = Provider<ChapterReadExecutor>((ref) {
  return ChapterReadExecutor(ref);
});

final _chapterWriteExecutorProvider = Provider<ChapterWriteExecutor>((ref) {
  return ChapterWriteExecutor(ref);
});

final _writingScenarioProvider = Provider<WritingScenario>((ref) {
  return WritingScenario(ref);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Database db;
  late int hostNovelId;
  const hostUrl = 'custom://side-tools-test';
  const hostChapterUrl = '$hostUrl#ch1';
  const hostChapterContent = '第 1 章正文。苏晴啧了一声。\n她的左腕旧伤未愈。';

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider.overrideWithValue(
        DatabaseConnection.forTesting(db),
      ),
      // 阅读态：锚点 = 宿主第 1 章
      readingContextProvider.overrideWith((ref) => const ReadingContext(
            novelTitle: '宿主小说',
            chapterTitle: '第1章 女主登场',
            novelUrl: hostUrl,
            chapterUrl: hostChapterUrl,
          )),
    ]);

    hostNovelId = await container
        .read(bookshelfMutationProvider.notifier)
        .addNovel(Novel(title: '宿主小说', author: '作者', url: hostUrl));

    await db.insert('novel_chapters', {
      'novelUrl': hostUrl,
      'chapterUrl': hostChapterUrl,
      'title': '第1章 女主登场',
      'chapterIndex': 0,
    });
    await db.insert('chapter_cache', {
      'novelUrl': hostUrl,
      'chapterUrl': hostChapterUrl,
      'title': '第1章 女主登场',
      'content': hostChapterContent,
      'chapterIndex': 0,
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  AgentScenarioContext hostCtx() => AgentScenarioContext(
        scenarioId: ScenarioIds.writing,
        currentNovelId: hostNovelId,
        currentNovelTitle: '宿主小说',
      );

  Future<List<Map<String, dynamic>>> sideStoryRows() async =>
      db.query('bookshelf', where: 'isSideStory = 1');

  group('create_side_story', () {
    test('阅读态锚点 → 建隐藏行，宿主 novel_chapters 零写入', () async {
      final executor = container.read(_sideStoryExecutorProvider);
      final result = await executor.createSideStory({
        'title': '闺蜜往事',
        'requirement': '写女主与闺蜜的童年往事',
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], isTrue, reason: 'result=$result');
      expect(json['sideStoryId'], isNotNull);
      expect(json['sideStoryUrl'], startsWith('custom://sidestory/'));
      expect(json['anchorChapterTitle'], '第1章 女主登场');
      expect(json['sideStoryChapterCount'], 0);

      final rows = await sideStoryRows();
      expect(rows, hasLength(1));
      expect(rows.single['anchorNovelUrl'], hostUrl);
      expect(rows.single['anchorChapterUrl'], hostChapterUrl);
      expect(rows.single['description'], '写女主与闺蜜的童年往事');

      final hostChapters = await db.query(
        'novel_chapters',
        where: 'novelUrl = ?',
        whereArgs: [hostUrl],
      );
      expect(hostChapters, hasLength(1), reason: '宿主章节不得新增');
    });

    test('幂等：同锚点同需求重调 → 复用已建番外（sideStoryId 相同）', () async {
      final executor = container.read(_sideStoryExecutorProvider);
      final r1 = await executor.createSideStory({
        'title': '闺蜜往事',
        'requirement': '写女主与闺蜜的童年往事',
      }, hostCtx());
      final r2 = await executor.createSideStory({
        'title': '另一个名字',
        'requirement': '写女主与闺蜜的童年往事',
      }, hostCtx());
      final j1 = jsonDecode(r1) as Map<String, dynamic>;
      final j2 = jsonDecode(r2) as Map<String, dynamic>;
      expect(j2['sideStoryId'], j1['sideStoryId']);
      expect(await sideStoryRows(), hasLength(1));
    });

    test('无锚点（非阅读态 + 无 position）→ no_active_reading 引导', () async {
      final bareContainer = ProviderContainer(overrides: [
        databaseConnectionProvider.overrideWithValue(
          DatabaseConnection.forTesting(db),
        ),
        // 默认空 ReadingContext
      ]);
      addTearDown(bareContainer.dispose);
      final executor = bareContainer.read(_sideStoryExecutorProvider);
      final result = await executor.createSideStory({
        'title': '闺蜜往事',
      }, null);
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_active_reading');
      expect(await bareContainer
          .read(sideStoryRepositoryProvider)
          .getSideStories(anchorNovelUrl: hostUrl), isEmpty);
    });

    test('anchorChapterPosition → 解析当前小说指定章为锚点', () async {
      // 非阅读态，但 Agent 传了当前小说的章节位置
      final bareContainer = ProviderContainer(overrides: [
        databaseConnectionProvider.overrideWithValue(
          DatabaseConnection.forTesting(db),
        ),
      ]);
      addTearDown(bareContainer.dispose);
      final executor = bareContainer.read(_sideStoryExecutorProvider);
      final result = await executor.createSideStory({
        'title': '闺蜜往事',
        'anchorChapterPosition': 1,
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: 'result=$result');
      expect(json['anchorChapterTitle'], '第1章 女主登场');
      final rows = await sideStoryRows();
      expect(rows.single['anchorChapterUrl'], hostChapterUrl);
    });
  });

  group('save_side_story_chapter', () {
    /// 建番外并构造带写入目标的 ctx
    Future<(SideStoryExecutor, AgentScenarioContext)> createAndTarget() async {
      final executor = container.read(_sideStoryExecutorProvider);
      final result = await executor.createSideStory({
        'title': '闺蜜往事',
        'requirement': '写女主与闺蜜的童年往事',
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      final target = ActiveSideStoryWritingTarget(
        novelId: json['sideStoryId'] as int,
        novelUrl: json['sideStoryUrl'] as String,
        title: json['sideStoryTitle'] as String,
        anchorChapterTitle: '第1章 女主登场',
      );
      final ctx = AgentScenarioContext(
        scenarioId: ScenarioIds.writing,
        currentNovelId: hostNovelId,
        currentNovelTitle: '宿主小说',
        sideStoryWritingTarget: target,
      );
      return (executor, ctx);
    }

    test('无写入目标 → no_side_story 引导 create_side_story', () async {
      final executor = container.read(_sideStoryExecutorProvider);
      final result = await executor.saveSideStoryChapter({
        'position': 1,
        'content': '正文' * 200,
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_side_story');
      expect(json['suggested_tool'], 'create_side_story');
    });

    test('有目标 → 正文落库番外命名空间，宿主正文不变', () async {
      final (executor, ctx) = await createAndTarget();
      final content = '番外第一章。\n\n${'闺蜜往事段落。' * 60}';
      final result = await executor.saveSideStoryChapter({
        'position': 1,
        'title': '初遇',
        'content': content,
      }, ctx);
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: 'result=$result');
      expect(json['sideStoryTitle'], '闺蜜往事');
      expect(json['sideStoryChapterCount'], 1);

      // 番外命名空间有正文
      final sideChapters = await db.query(
        'chapter_cache',
        where: 'novelUrl LIKE ?',
        whereArgs: ['custom://sidestory/%'],
      );
      expect(sideChapters, hasLength(1));
      expect(sideChapters.single['title'], '初遇');

      // 宿主正文原封不动
      final host = await db.query(
        'chapter_cache',
        where: 'chapterUrl = ?',
        whereArgs: [hostChapterUrl],
      );
      expect(host.single['content'], hostChapterContent);
    });

    test('300 字下限闸门生效（复用 saveChapter 校验链）', () async {
      final (executor, ctx) = await createAndTarget();
      final result = await executor.saveSideStoryChapter({
        'position': 1,
        'content': '太短。',
      }, ctx);
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'content_too_short');
      final sideChapters = await db.query(
        'chapter_cache',
        where: 'novelUrl LIKE ?',
        whereArgs: ['custom://sidestory/%'],
      );
      expect(sideChapters, isEmpty);
    });
  });

  group('writing 场景分支（_syncSideStoryTarget 同轮联动）', () {
    test('create 后同场景实例直接 save → 落库成功（ctx 已同步写入目标）', () async {
      final scenario = container.read(_writingScenarioProvider);
      // buildSystemPrompt 缓存 _currentContext（agent_loop 每 run 调用）
      scenario.buildSystemPrompt(hostCtx());

      final createResult = await scenario.executeTool('create_side_story', {
        'title': '闺蜜往事',
        'requirement': '写女主与闺蜜的童年往事',
      });
      expect(
        (jsonDecode(createResult) as Map<String, dynamic>)['success'],
        isTrue,
      );

      // 同轮（无 session 事件接线参与）直接 save —— _currentContext 已带目标
      final content = '番外第一章。\n\n${'闺蜜往事段落。' * 60}';
      final saveResult = await scenario.executeTool(
        'save_side_story_chapter',
        {'position': 1, 'title': '初遇', 'content': content},
      );
      final saveJson = jsonDecode(saveResult) as Map<String, dynamic>;
      expect(saveJson['success'], isTrue, reason: 'saveResult=$saveResult');
      expect(saveJson['sideStoryChapterCount'], 1);
    });
  });

  group('list_side_stories', () {
    test('列出当前小说全部番外', () async {
      final executor = container.read(_sideStoryExecutorProvider);
      await executor.createSideStory({
        'title': '闺蜜往事',
        'requirement': '写女主与闺蜜的童年往事',
      }, hostCtx());

      final result = await executor.listSideStories({}, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['count'], 1);
      final list = json['sideStories'] as List;
      expect((list.first as Map)['title'], '闺蜜往事');
      expect((list.first as Map)['anchorChapterTitle'], '第1章 女主登场');
    });
  });

  group('sideStoryId 参数越界寻址（list/read/update 复用宿主工具）', () {
    const sideChapterContent =
        '番外第 1 章正文。苏晴与阿岚在巷口吃冰，说到小时候的旧伤。';

    /// 建番外（阅读态锚点）并返回 (sideStoryId, sideStoryUrl)
    Future<(int, String)> createSideStoryAndGetUrl() async {
      final executor = container.read(_sideStoryExecutorProvider);
      final result = await executor.createSideStory({
        'title': '闺蜜往事',
        'requirement': '写女主与闺蜜的童年往事',
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: result);
      final id = json['sideStoryId'] as int;
      final url =
          (await db.query('bookshelf', where: 'id = ?', whereArgs: [id]))
              .single['url'] as String;
      return (id, url);
    }

    /// 直接落库一章番外缓存（绕过 300 字闸门，聚焦寻址行为本身）
    Future<void> seedSideChapter(String sideUrl) async {
      await db.insert('novel_chapters', {
        'novelUrl': sideUrl,
        'chapterUrl': '$sideUrl#ch1',
        'title': '番外第1章',
        'chapterIndex': 0,
      });
      await db.insert('chapter_cache', {
        'novelUrl': sideUrl,
        'chapterUrl': '$sideUrl#ch1',
        'title': '番外第1章',
        'content': sideChapterContent,
        'chapterIndex': 0,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    test('list_chapters(sideStoryId) → 番外章节清单 + sideStoryTitle', () async {
      final (sideStoryId, sideUrl) = await createSideStoryAndGetUrl();
      await seedSideChapter(sideUrl);

      final executor = container.read(_chapterReadExecutorProvider);
      final result =
          await executor.listChapters({'sideStoryId': sideStoryId}, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['sideStoryTitle'], '闺蜜往事');
      expect(json['count'], 1);
      expect((json['chapters'] as List).single['title'], '番外第1章');
    });

    test('read_chapter_content(position, sideStoryId) → 番外正文（纯文本特例）',
        () async {
      final (sideStoryId, sideUrl) = await createSideStoryAndGetUrl();
      await seedSideChapter(sideUrl);

      final executor = container.read(_chapterReadExecutorProvider);
      final result = await executor.readChapterContent({
        'position': 1,
        'sideStoryId': sideStoryId,
      }, hostCtx());

      expect(result, sideChapterContent,
          reason: 'read 是纯文本特例，番外原文应原样直返');
    });

    test('update_chapter_content(sideStoryId) → patch 番外，宿主正文零变化',
        () async {
      final (sideStoryId, sideUrl) = await createSideStoryAndGetUrl();
      await seedSideChapter(sideUrl);

      final executor = container.read(_chapterWriteExecutorProvider);
      final result = await executor.updateChapterContent({
        'position': 1,
        'sideStoryId': sideStoryId,
        'oldString': '巷口吃冰',
        'newString': '江边看灯',
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: 'result=$result');

      final side = await db.query('chapter_cache',
          where: 'chapterUrl = ?', whereArgs: ['$sideUrl#ch1']);
      expect(side.single['content'], contains('江边看灯'));
      expect(side.single['content'], isNot(contains('巷口吃冰')));

      // 宿主命名空间零写入
      final host = await db.query('chapter_cache',
          where: 'chapterUrl = ?', whereArgs: [hostChapterUrl]);
      expect(host.single['content'], hostChapterContent);
    });

    test('宿主正篇 id 冒充 sideStoryId → side_story_not_found，正文未被触碰',
        () async {
      final executor = container.read(_chapterWriteExecutorProvider);
      final result = await executor.updateChapterContent({
        'position': 1,
        'sideStoryId': hostNovelId, // 正篇行，非番外
        'oldString': '苏晴',
        'newString': '苏晴晴',
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'side_story_not_found');
      expect(json['suggested_tool'], 'list_side_stories');

      final host = await db.query('chapter_cache',
          where: 'chapterUrl = ?', whereArgs: [hostChapterUrl]);
      expect(host.single['content'], hostChapterContent);
    });

    test('别的书的番外 id 打不进当前小说（锚点归属校验）', () async {
      // 建第二本正篇 + 其番外
      final otherNovelId = await container
          .read(bookshelfMutationProvider.notifier)
          .addNovel(
              Novel(title: '别的书', author: '作者', url: 'custom://other-book'));
      await db.insert('novel_chapters', {
        'novelUrl': 'custom://other-book',
        'chapterUrl': 'custom://other-book#ch1',
        'title': '别的书第1章',
        'chapterIndex': 0,
      });
      final otherContainer = ProviderContainer(overrides: [
        databaseConnectionProvider.overrideWithValue(
          DatabaseConnection.forTesting(db),
        ),
      ]);
      addTearDown(otherContainer.dispose);
      final otherExecutor = otherContainer.read(_sideStoryExecutorProvider);
      final otherResult = await otherExecutor.createSideStory({
        'title': '别书的番外',
        'anchorChapterPosition': 1,
      }, AgentScenarioContext(
        scenarioId: ScenarioIds.writing,
        currentNovelId: otherNovelId,
        currentNovelTitle: '别的书',
      ));
      final otherJson = jsonDecode(otherResult) as Map<String, dynamic>;
      expect(otherJson['success'], isTrue, reason: otherResult);
      final otherSideStoryId = otherJson['sideStoryId'] as int;

      // 回到宿主上下文，拿别书番外 id 打 patch → 锚点归属不符，拒绝
      final executor = container.read(_chapterWriteExecutorProvider);
      final result = await executor.updateChapterContent({
        'position': 1,
        'sideStoryId': otherSideStoryId,
        'oldString': '任意',
        'newString': '任意改',
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'side_story_not_found');
    });

    test('省略 sideStoryId → 仍作用于宿主（缺省契约回归）', () async {
      final executor = container.read(_chapterWriteExecutorProvider);
      final result = await executor.updateChapterContent({
        'position': 1,
        'oldString': '旧伤未愈',
        'newString': '旧伤已愈',
      }, hostCtx());
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: 'result=$result');

      final host = await db.query('chapter_cache',
          where: 'chapterUrl = ?', whereArgs: [hostChapterUrl]);
      expect(host.single['content'], contains('旧伤已愈'));
    });
  });
}

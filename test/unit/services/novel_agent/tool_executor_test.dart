/// ToolExecutor 工具执行器单元测试 — 真实 SQLite
///
/// 使用内存 SQLite 数据库 + 真实 Repository 实现，
/// 验证 14 个工具端到端的执行逻辑（上下文驱动）：
/// - 正常路径：select_novel → 数据写入 → 工具读取 → 返回正确 JSON
/// - 边界条件：空数据、未缓存章节、角色不存在、大纲不存在
/// - 错误处理：未知工具、position 不存在（含 suggested_tool）、无当前小说
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/novel_agent/tool_executor_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_repository.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/core/interfaces/repositories/i_character_repository.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/interfaces/repositories/i_outline_repository.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/models/outline.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

/// 注册一个测试用 Provider，让 Riverpod 框架提供真正的 Ref
final _toolExecutorProvider = Provider<ToolExecutor>((ref) {
  return ToolExecutor(ref);
});

/// 构造写作场景上下文（含当前小说信息）
AgentScenarioContext _writingContext(int novelId, String title) {
  return AgentScenarioContext(
    currentNovelId: novelId,
    currentNovelTitle: title,
  );
}

/// 空上下文（未选小说）
const _noNovelContext = AgentScenarioContext();

void main() {
  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;
  late INovelRepository novelRepo;
  late IChapterRepository chapterRepo;
  // fixture 准备需要直接调写方法（cacheChapter/cacheNovelChapters 等），
  // 这些方法在 2026-07-29 接口脱钩后已从 IChapterRepository 移除，
  // 仅 ChapterRepository 实现类保留。Fixture 是测试基础设施，绕过 Notifier 收口
  // 直接写库可接受（不需要触发章节列表刷新语义）。
  late ChapterRepository chapterRepoImpl;
  late ICharacterRepository characterRepo;
  late IOutlineRepository outlineRepo;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dbConnection = DatabaseConnection.forTesting(db);
    container = ProviderContainer(
      overrides: [
        databaseConnectionProvider.overrideWithValue(dbConnection),
      ],
    );
    novelRepo = container.read(novelRepositoryProvider);
    chapterRepo = container.read(chapterRepositoryProvider);
    chapterRepoImpl = chapterRepo as ChapterRepository;
    characterRepo = container.read(characterRepositoryProvider);
    outlineRepo = container.read(outlineRepositoryProvider);
    executor = container.read(_toolExecutorProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // ========================================================================
  // 辅助方法
  // ========================================================================

  /// 插入一条测试小说，返回 novelId
  Future<int> insertNovel({
    String title = '测试小说',
    String author = '测试作者',
    String url = 'https://example.com/novel1',
    String? description,
    String? backgroundSetting,
  }) async {
    final novel = Novel(
      title: title,
      author: author,
      url: url,
      description: description,
      backgroundSetting: backgroundSetting,
    );
    await container.read(bookshelfMutationProvider.notifier).addNovel(novel);
    final novels = await novelRepo.getNovels();
    return novels.firstWhere((n) => n.url == url).id!;
  }

  /// 测试用默认小说 URL
  const defaultNovelUrl = 'https://example.com/novel1';

  /// 缓存一条章节（同时写入 chapter_cache 和 novel_chapters），返回章节列表中的 position
  Future<int> insertChapter({
    String novelUrl = defaultNovelUrl,
    String chapterUrl = 'https://example.com/ch1',
    String title = '第一章',
    String content = '段落0\n\n段落1\n\n段落2',
    int chapterIndex = 0,
  }) async {
    await chapterRepoImpl.cacheChapter(
      novelUrl,
      Chapter(
        title: title,
        url: chapterUrl,
        chapterIndex: chapterIndex,
        isCached: true,
      ),
      content,
    );
    await chapterRepoImpl.cacheNovelChapters(novelUrl, [
      Chapter(
        title: title,
        url: chapterUrl,
        chapterIndex: chapterIndex,
        isCached: true,
      ),
    ]);
    // 返回 position（= 当前小说章节总数，因为测试中从 1 开始插入）
    return (await chapterRepo.getCachedNovelChapters(novelUrl)).length;
  }

  /// 构造章节操作的上下文
  AgentScenarioContext _ctx(int novelId, [String title = '测试小说']) =>
      _writingContext(novelId, title);

  /// 插入一条角色
  Future<void> insertCharacter({
    String novelUrl = defaultNovelUrl,
    String name = '李云',
    String appearanceFeatures = '白衣剑客',
  }) async {
    await characterRepo.createCharacter(Character(
      novelUrl: novelUrl,
      name: name,
      appearanceFeatures: appearanceFeatures,
    ));
  }

  /// 插入一条大纲
  Future<void> insertOutline({
    String novelUrl = defaultNovelUrl,
    String title = '全书大纲',
    String content = '第一幕\n第二幕\n第三幕',
  }) async {
    await outlineRepo.saveOutline(Outline(
      novelUrl: novelUrl,
      title: title,
      content: content,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    ));
  }

  // ========================================================================
  // list_novels
  // ========================================================================
  group('list_novels', () {
    test('空书架返回空列表', () async {
      final result = await executor.execute('list_novels', {});
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['count'], 0);
      expect((json['novels'] as List).isEmpty, true);
    });

    test('返回所有小说', () async {
      await insertNovel(title: '小说A', url: 'urlA');
      await insertNovel(title: '小说B', url: 'urlB', description: '简介');

      final result = await executor.execute('list_novels', {});
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['count'], 2);
      final novels = json['novels'] as List;
      expect(novels.any((n) => n['title'] == '小说A'), true);
      expect(novels.any((n) => n['title'] == '小说B'), true);
    });

    test('每本小说返回 id 字段', () async {
      await insertNovel(title: '小说X');
      final result = await executor.execute('list_novels', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      final novels = json['novels'] as List;
      expect(novels.first['id'], isA<int>());
      expect(novels.first['id'], greaterThan(0));
    });

    test('长描述截断到 200 字符', () async {
      await insertNovel(url: 'urlLong', description: 'x' * 300);
      final result = await executor.execute('list_novels', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      final desc = (json['novels'] as List).first['description'] as String?;
      expect(desc!.endsWith('...'), true);
      expect(desc.length, 203);
    });

    test('返回结果中不含 url 字段', () async {
      await insertNovel();
      final result = await executor.execute('list_novels', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      final novel = (json['novels'] as List).first;
      expect(novel.containsKey('url'), false,
          reason: 'AI 不应看到 url 字段');
    });
  });

  // ========================================================================
  // select_novel
  // ========================================================================
  group('select_novel', () {
    test('成功切换小说返回 info', () async {
      final novelId = await insertNovel(title: '凡人修仙传');

      final result = await executor.execute(
        'select_novel',
        {'novelId': novelId},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      expect(json['title'], '凡人修仙传');
      expect(json['novelId'], novelId);
    });

    test('小说不存在 → novel_not_found + suggested_tool', () async {
      final result = await executor.execute(
        'select_novel',
        {'novelId': 99999},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'novel_not_found');
      expect(json['suggested_tool'], 'list_novels');
    });
  });

  // ========================================================================
  // create_novel
  // ========================================================================
  group('create_novel', () {
    test('成功创建小说返回 success + novelId + title', () async {
      final result = await executor.execute(
        'create_novel',
        {'title': '我的新书', 'description': '简介内容'},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      expect(json['title'], '我的新书');
      expect(json['novelId'], isA<int>());
      expect(json['novelId'], greaterThan(0));
      expect(json['message'].toString(), contains('已创建'));
    });

    test('创建的数据库 url 字段为 custom:// 协议（与 UI 一致）', () async {
      final result = await executor.execute(
        'create_novel',
        {'title': '原创书'},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final newId = json['novelId'] as int;

      final novels = await novelRepo.getNovels();
      final created = novels.firstWhere((n) => n.id == newId);
      expect(created.url, startsWith('custom://'));
      expect(created.author, '原创');
    });

    test('description 为空字符串 → 写入 null', () async {
      final result = await executor.execute(
        'create_novel',
        {'title': '空白简介书', 'description': ''},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final newId = json['novelId'] as int;

      final novels = await novelRepo.getNovels();
      final created = novels.firstWhere((n) => n.id == newId);
      expect(created.description, isNull);
    });

    test('title 为空字符串 → empty_param', () async {
      final result = await executor.execute(
        'create_novel',
        {'title': ''},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      // ToolArgParser.requireString 对 trim 后空字符串返回 empty_param
      expect(json['error'], 'empty_param');
      expect(json['message'].toString(), contains('title'));
    });

    test('title 仅含空白 → empty_param', () async {
      final result = await executor.execute(
        'create_novel',
        {'title': '   '},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'empty_param');
    });

    test('title 缺失 → missing_required_param', () async {
      // ToolArgParser.requireString 对缺失参数返回 missing_required_param
      final result = await executor.execute('create_novel', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'missing_required_param');
    });

    test('可连续创建多本小说（间隔 1ms 避免 timestamp 冲突）', () async {
      final r1 = jsonDecode(await executor.execute(
        'create_novel',
        {'title': '书A'},
      )) as Map<String, dynamic>;
      // 让两次 createCustomNovel 生成不同的 timestamp URL
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final r2 = jsonDecode(await executor.execute(
        'create_novel',
        {'title': '书B'},
      )) as Map<String, dynamic>;

      expect(r1['success'], true);
      expect(r2['success'], true);
      expect(r1['novelId'], isNot(r2['novelId']));

      final novels = await novelRepo.getNovels();
      final titles = novels.map((n) => n.title).toList();
      expect(titles, containsAll(['书A', '书B']));
    });

    test('新小说可被 list_novels 列出', () async {
      await executor.execute('create_novel', {'title': '新书'});

      final result = await executor.execute('list_novels', {});
      final json = jsonDecode(result) as Map<String, dynamic>;
      final novels = json['novels'] as List;
      expect(novels.any((n) => n['title'] == '新书'), true);
    });
  });

  // ========================================================================
  // 未选择小说的错误
  // ========================================================================
  group('未选小说时的错误处理', () {
    test('list_chapters 无上下文 → no_current_novel', () async {
      final result = await executor.execute(
        'list_chapters',
        {},
        scenarioContext: _noNovelContext,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_current_novel');
      expect(json['suggested_tool'], 'list_novels');
    });

    test('read_chapter_content 无上下文 → no_current_novel', () async {
      final result = await executor.execute(
        'read_chapter_content',
        {'position': 1},
        scenarioContext: _noNovelContext,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_current_novel');
    });
  });

  // ========================================================================
  // read_chapter_content
  // ========================================================================
  group('read_chapter_content', () {
    test('通过 position 返回章节内容', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '这是章节内容');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'read_chapter_content',
        {'position': 1},
        scenarioContext: ctx,
      );

      expect(result, '这是章节内容');
    });

    test('position 超出范围 → chapter_position_out_of_range', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'read_chapter_content',
        {'position': 999},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'chapter_position_out_of_range');
      expect(json['suggested_tool'], 'list_chapters');
    });
  });

  // ========================================================================
  // list_chapters
  // ========================================================================
  group('list_chapters', () {
    test('返回章节列表（不含 novelId 参数）', () async {
      final novelId = await insertNovel();
      await insertChapter(
          chapterUrl: 'ch1', title: '第一章', chapterIndex: 0);
      await insertChapter(
          chapterUrl: 'ch2', title: '第二章', chapterIndex: 1);
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'list_chapters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['count'], 2);
      final chapters = json['chapters'] as List;
      expect(chapters[0]['title'], '第一章');
      expect(chapters[0]['position'], 1);
      expect(chapters[1]['title'], '第二章');
      expect(chapters[1]['position'], 2);
    });

    test('返回结果中的 position 字段（不再返回 id）', () async {
      final novelId = await insertNovel();
      await insertChapter(chapterUrl: 'ch1');
      await insertChapter(chapterUrl: 'ch2');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'list_chapters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final chapters = json['chapters'] as List;
      for (final ch in chapters) {
        expect(ch['position'], isA<int>());
        // 不返回 id 字段（position 替代了 id 的角色）
        expect(ch.containsKey('url'), false);
      }
    });

    test('返回结果不含 url 字段', () async {
      final novelId = await insertNovel();
      await insertChapter();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'list_chapters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final ch = (json['chapters'] as List).first;
      expect(ch.containsKey('url'), false);
    });

    test('无章节返回空列表', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'list_chapters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['count'], 0);
      expect((json['chapters'] as List).isEmpty, true);
    });
  });

  // ========================================================================
  // search_in_chapters
  // ========================================================================
  group('search_in_chapters', () {
    test('搜索到关键词返回匹配（结果含 position）', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '剑客走在路上');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '剑客'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['count'], greaterThanOrEqualTo(1));
      final results = json['results'] as List;
      expect(results.first['matchedText'].toString(), contains('剑客'));
      expect(results.first['position'], isA<int>());
    });

    test('搜索结果不含 chapterUrl 字段', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '剑客走在路上');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '剑客'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final results = json['results'] as List;
      expect(results.first.containsKey('chapterUrl'), false);
    });

    test('搜索结果包含 novel 上下文', () async {
      final novelId = await insertNovel(title: '凡人修仙传');
      await insertChapter(content: '剑客');
      final ctx = _writingContext(novelId, '凡人修仙传');

      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '剑客'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect((json['novel'] as Map)['title'], '凡人修仙传');
    });

    test('搜不到关键词返回空', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '内容');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '不存在'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['count'], 0);
    });

    test('无当前小说 → no_current_novel + suggested_tool=list_novels', () async {
      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '剑客'},
        scenarioContext: _noNovelContext,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_current_novel');
      expect(json['suggested_tool'], 'list_novels');
    });

    test('多小说隔离：搜当前小说时不返回其他小说的命中', () async {
      // 小说 A：含关键词"剑客"
      final novelIdA = await insertNovel(title: '小说A', url: 'urlA');
      await insertChapter(
        novelUrl: 'urlA',
        chapterUrl: 'https://a/ch1',
        content: '剑客走在路上',
      );
      // 小说 B：同样含关键词"剑客"（隔离测试的前提）
      await insertNovel(title: '小说B', url: 'urlB');
      await insertChapter(
        novelUrl: 'urlB',
        chapterUrl: 'https://b/ch1',
        content: '剑客登场',
      );

      // ctx 指向 A，应只命中 A 的 1 个章节
      final ctx = _writingContext(novelIdA, '小说A');
      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '剑客'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['count'], 1);
      final results = json['results'] as List;
      expect(results.length, 1);
      expect((json['novel'] as Map)['title'], '小说A');
      expect(results.first['matchedText'].toString(), contains('剑客'));
    });

    test('keyword 缺失 → missing_required_param', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        <String, dynamic>{}, // 故意不传 keyword
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'missing_required_param');
      expect(json['param'], 'keyword');
    });

    test('上下文片段含前后内容（非关键词回显）', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '前文内容剑客后文内容');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '剑客'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final first = (json['results'] as List).first as Map<String, dynamic>;
      final snippets = first['snippets'] as List;

      expect(snippets, isNotEmpty);
      final snippet = snippets.first as String;
      expect(snippet, contains('剑客'));
      // 证明带了前后文（不再是关键词自身回显）
      expect(snippet.length, greaterThan('剑客'.length));
      expect(snippet, contains('前文'));
      expect(snippet, contains('后文'));
    });

    test('高频词被采样并标注 truncated', () async {
      final novelId = await insertNovel();
      // 5 个命中点，间隔 100 字符（> 2*radius=160 触发合并？需 >= 2*radius）
      // 2*radius=160，间隔 100 会被合并 → 用 100 不行，要 >= 161
      // 改用 200 字符 padding 确保 5 个独立窗口
      final padding = '甲。' * 100; // 200 chars
      final content = List.generate(5, (_) => '${padding}李明$padding').join();
      await insertChapter(content: content);
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        {'keyword': '李明'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final first = (json['results'] as List).first as Map<String, dynamic>;

      expect(first['matchCount'], 5); // 原始命中数完整
      expect((first['snippets'] as List).length, 3); // 被 cap 到 3
      expect(json['truncated'], true);
    });

    test('章节范围过滤：positionFrom/positionTo', () async {
      final novelId = await insertNovel();
      // 插入 5 章，每章都含"剑客"
      for (var i = 0; i < 5; i++) {
        await insertChapter(
          chapterUrl: 'https://example.com/ch_$i',
          content: '剑客走在路上',
          chapterIndex: i,
        );
      }
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        {
          'keyword': '剑客',
          'positionFrom': 2,
          'positionTo': 4,
        },
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final results = json['results'] as List;

      expect(json['positionFrom'], 2);
      expect(json['positionTo'], 4);
      expect(json['totalChaptersHit'], 3); // 范围内真实命中章数
      expect(json['totalMatches'], 3); // 每章 1 次命中
      expect(results.length, 3);
      for (final r in results) {
        final pos = r['position'] as int;
        expect(pos, greaterThanOrEqualTo(2));
        expect(pos, lessThanOrEqualTo(4));
      }
    });

    test('章节范围非法 from>to → invalid_range', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '剑客');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'search_in_chapters',
        {
          'keyword': '剑客',
          'positionFrom': 5,
          'positionTo': 2,
        },
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'invalid_range');
    });
  });

  // ========================================================================
  // update_chapter_content (edit 风格：字符串替换)
  // ========================================================================
  group('update_chapter_content', () {
    test('oldString 唯一 → 成功，DB 内容已替换', () async {
      final novelId = await insertNovel();
      await insertChapter(content: 'foo bar baz');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {'position': 1, 'oldString': 'bar', 'newString': 'BAR'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      final chapters = await chapterRepo.getCachedNovelChapters(defaultNovelUrl);
      expect(chapters.first.content, 'foo BAR baz');
    });

    test('oldString 找不到 → not_found', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '现成章节内容');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {'position': 1, 'oldString': '不存在的段落', 'newString': 'X'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'not_found');
    });

    test('oldString 多处且未 replaceAll → ambiguous_match', () async {
      final novelId = await insertNovel();
      await insertChapter(content: 'foo bar foo baz');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {'position': 1, 'oldString': 'foo', 'newString': 'X'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'ambiguous_match');
    });

    test('replaceAll=true → 全部替换', () async {
      final novelId = await insertNovel();
      await insertChapter(content: 'foo bar foo baz foo');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {'position': 1, 'oldString': 'foo', 'newString': 'X', 'replaceAll': true},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      final chapters = await chapterRepo.getCachedNovelChapters(defaultNovelUrl);
      expect(chapters.first.content, 'X bar X baz X');
    });

    test('oldString 与 newString 相同 → invalid_param', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '内容');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {'position': 1, 'oldString': '内容', 'newString': '内容'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'invalid_param');
    });

    test('章节未缓存 → not_cached', () async {
      final novelId = await insertNovel();
      // 插入章节列表元数据但不缓存正文内容
      await chapterRepoImpl.cacheNovelChapters(defaultNovelUrl, [
        Chapter(title: '空章', url: 'https://example.com/empty', chapterIndex: 0),
      ]);
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {'position': 1, 'oldString': 'A', 'newString': 'B'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'not_cached');
    });

    test('行 trim 容错：AI 漏了行尾空格仍能命中', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '第一段\n第二段\n第三段');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {
          'position': 1,
          'oldString': '第一段\n第二段',
          'newString': '第一段(改)\n第二段',
        },
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      final chapters = await chapterRepo.getCachedNovelChapters(defaultNovelUrl);
      expect(chapters.first.content, '第一段(改)\n第二段\n第三段');
    });

    test('position 不存在 → chapter_position_out_of_range + suggested_tool', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_chapter_content',
        {'position': 999, 'oldString': 'A', 'newString': 'B'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'chapter_position_out_of_range');
      expect(json['suggested_tool'], 'list_chapters');
    });
  });

  // ========================================================================
  // rewrite_chapter (LLM 全文重写)
  // ========================================================================
  group('rewrite_chapter', () {
    test('通过 position 重写章节 — 未配置 LLM 时返回友好错误', () async {
      final novelId = await insertNovel();
      await insertChapter(content: '旧内容');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'rewrite_chapter',
        {'position': 1, 'rewriteInstruction': '改写为悬疑风格'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      // 测试环境未配置 LLM，position 已正确解析到章节，
      // LLM 调用链因无配置而失败（统一断言非成功）
      expect(json['success'], isNull);
      expect(json.containsKey('error'), isTrue);

      // 原文未被修改
      final chapters = await chapterRepo.getCachedNovelChapters(defaultNovelUrl);
      expect(chapters.first.content, '旧内容');
    });

    test('position 不存在 → chapter_position_out_of_range + suggested_tool', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'rewrite_chapter',
        {'position': 999, 'rewriteInstruction': '新内容'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'chapter_position_out_of_range');
      expect(json['suggested_tool'], 'list_chapters');
    });
  });

  // ========================================================================
  // delete_chapter
  // ========================================================================
  group('delete_chapter', () {
    test('通过 position 删除已有章节后剩余章节 position 自动前移', () async {
      final novelId = await insertNovel();
      // 插入 3 章：chapterIndex=0,1,2，对应 position=1,2,3
      await insertChapter(
          chapterUrl: 'ch1', title: '第一章', chapterIndex: 0);
      await insertChapter(
          chapterUrl: 'ch2', title: '第二章', chapterIndex: 1);
      await insertChapter(
          chapterUrl: 'ch3', title: '第三章', chapterIndex: 2);
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'delete_chapter',
        {'position': 2},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      expect(json['deletedTitle'], '第二章');
      expect(json['deletedPosition'], 2);
      expect(json['remainingChapters'], 2);

      // 验证剩余章节：原 ch1 (index 0) 仍在；原 ch3 重排到 index 1
      final remaining = await chapterRepo.getCachedNovelChapters(defaultNovelUrl);
      expect(remaining.length, 2);
      expect(remaining.map((c) => c.title).toList(), ['第一章', '第三章']);
      expect(remaining.map((c) => c.chapterIndex).toList(), [0, 1]);

      // 验证 chapter_cache 也同步清理
      final ch2Cache = await chapterRepo.getCachedChapter('ch2');
      expect(ch2Cache, isNull);
    });

    test('position 越界时返回 chapter_position_out_of_range 引导', () async {
      final novelId = await insertNovel();
      await insertChapter(chapterIndex: 0);
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'delete_chapter',
        {'position': 99},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'chapter_position_out_of_range');
      expect(json['suggested_tool'], 'list_chapters');

      // 现有章节未被误删
      final remaining = await chapterRepo.getCachedNovelChapters(defaultNovelUrl);
      expect(remaining.length, 1);
    });

    test('未选小说时返回 no_current_novel 引导', () async {
      final result = await executor.execute(
        'delete_chapter',
        {'position': 1},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'no_current_novel');
      expect(json['suggested_tool'], 'list_novels');
    });

    test('position 缺失时返回 missing_required_param', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'delete_chapter',
        <String, dynamic>{},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'missing_required_param');
    });
  });

  // ========================================================================
  // list_characters
  // ========================================================================
  group('list_characters', () {
    test('返回角色列表（不含 novelId 参数）', () async {
      final novelId = await insertNovel();
      await insertCharacter(name: '李云');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'list_characters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['count'], 1);
      expect((json['characters'] as List)[0]['name'], '李云');
    });

    test('返回结果包含 novel 上下文', () async {
      final novelId = await insertNovel(title: '凡人修仙传');
      await insertCharacter();
      final ctx = _writingContext(novelId, '凡人修仙传');

      final result = await executor.execute(
        'list_characters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect((json['novel'] as Map)['title'], '凡人修仙传');
    });

    test('无角色返回空列表', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'list_characters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['count'], 0);
    });

    test('返回 avatarMediaId 且不含旧 avatarUrl', () async {
      final novelId = await insertNovel();
      await characterRepo.createCharacter(Character(
        novelUrl: defaultNovelUrl,
        name: '李云',
        avatarMediaId: 'local_abc_001',
      ));
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'list_characters',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      final c = (json['characters'] as List)[0] as Map<String, dynamic>;

      expect(c['avatarMediaId'], 'local_abc_001');
      expect(c.containsKey('avatarUrl'), isFalse);
    });
  });

  // ========================================================================
  // update_character
  // ========================================================================
  group('update_character', () {
    test('更新已有角色', () async {
      final novelId = await insertNovel();
      await insertCharacter(name: '李云');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_character',
        {'name': '李云', 'description': '新描述'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);

      final updated = await characterRepo.findCharacterByName(
        defaultNovelUrl,
        '李云',
      );
      expect(updated!.appearanceFeatures, '新描述');
    });

    test('角色不存在 → character_not_found + suggested_tool', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_character',
        {'name': '不存在'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'character_not_found');
      expect(json['suggested_tool'], 'list_characters');
    });

    test('更新 avatarMediaId 写入并可读回', () async {
      final novelId = await insertNovel();
      await insertCharacter(name: '李云');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_character',
        {'name': '李云', 'avatarMediaId': 'local_123_456'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], true);

      final updated = await characterRepo.findCharacterByName(
        defaultNovelUrl,
        '李云',
      );
      expect(updated!.avatarMediaId, 'local_123_456');
    });
  });

  // ========================================================================
  // create_character
  // ========================================================================
  group('create_character', () {
    test('创建新角色', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'create_character',
        {'name': '张三', 'description': '侠客'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      expect(json['characterId'], isA<int>());

      final created = await characterRepo.findCharacterByName(
        defaultNovelUrl,
        '张三',
      );
      expect(created, isNotNull);
      expect(created!.appearanceFeatures, '侠客');
    });

    test('角色已存在 → duplicate 错误', () async {
      final novelId = await insertNovel();
      await insertCharacter(name: '李云');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'create_character',
        {'name': '李云'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'duplicate');
      expect(json['message'].toString(), contains('update_character'));
    });
  });

  // ========================================================================
  // delete_character
  // ========================================================================
  group('delete_character', () {
    test('按 name 删除已有角色后角色从列表消失', () async {
      final novelId = await insertNovel();
      await insertCharacter(name: '李云');
      await insertCharacter(name: '张薇');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'delete_character',
        {'name': '李云'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      expect(json['deletedName'], '李云');
      expect(json['message'].toString(), contains('李云'));

      // 角色被删除，list_characters 只剩张薇
      final remaining = await characterRepo.getCharacters(defaultNovelUrl);
      expect(remaining.map((c) => c.name).toList(), ['张薇']);
    });

    test('删除不存在的角色返回 character_not_found 引导', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'delete_character',
        {'name': '不存在的角色'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'character_not_found');
      expect(json['suggested_tool'], 'list_characters');
    });

    test('未选小说时返回 no_current_novel 引导', () async {
      final result = await executor.execute(
        'delete_character',
        {'name': '李云'},
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'no_current_novel');
      expect(json['suggested_tool'], 'list_novels');
    });

    test('name 缺失时返回 missing_required_param', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'delete_character',
        <String, dynamic>{},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'missing_required_param');
    });
  });

  // ========================================================================
  // get_background_setting
  // ========================================================================
  group('get_background_setting', () {
    test('返回已有背景设定全文', () async {
      final novelId = await insertNovel(
        title: '凡人修仙传',
        backgroundSetting: '修仙界分九重天，灵气稀薄。',
      );
      final ctx = _writingContext(novelId, '凡人修仙传');

      final result = await executor.execute(
        'get_background_setting',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['setting'], '修仙界分九重天，灵气稀薄。');
      expect(json['empty'], false);
      expect((json['novel'] as Map)['title'], '凡人修仙传');
    });

    test('背景设定为空 → empty=true 并引导创建', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'get_background_setting',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['empty'], true);
      expect(json['setting'], isNull);
      expect(json['suggested_tool'], 'update_background_setting');
    });

    test('背景设定仅空白 → 视为空', () async {
      final novelId = await insertNovel(backgroundSetting: '   \n  ');
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'get_background_setting',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['empty'], true);
    });

    test('update 后 get 能读回最新内容', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      await executor.execute(
        'update_background_setting',
        {'setting': '赛博朋克都市'},
        scenarioContext: ctx,
      );

      final result = await executor.execute(
        'get_background_setting',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['setting'], '赛博朋克都市');
      expect(json['empty'], false);
    });

    test('无上下文 → no_current_novel', () async {
      final result = await executor.execute(
        'get_background_setting',
        {},
        scenarioContext: _noNovelContext,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_current_novel');
      expect(json['suggested_tool'], 'list_novels');
    });
  });

  // ========================================================================
  // update_background_setting
  // ========================================================================
  group('update_background_setting', () {
    test('更新背景设定后可读取', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'update_background_setting',
        {'setting': '武侠世界'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);

      final setting =
          await novelRepo.getBackgroundSetting(defaultNovelUrl);
      expect(setting, '武侠世界');
    });

    test('无上下文 → no_current_novel', () async {
      final result = await executor.execute(
        'update_background_setting',
        {'setting': 'X'},
        scenarioContext: _noNovelContext,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'no_current_novel');
    });
  });

  // ========================================================================
  // write_outline
  // ========================================================================
  group('write_outline', () {
    test('整篇保存大纲后可读取（标题用当前小说书名兜底）', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'write_outline',
        {'content': '第一幕\n第二幕'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);

      final outline = await outlineRepo.getOutlineByNovelUrl(
        defaultNovelUrl,
      );
      expect(outline, isNotNull);
      expect(outline!.title, '测试小说');
      expect(outline.content, '第一幕\n第二幕');
    });

    test('write_outline 后标记已读，可直接 update_outline 局部编辑', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      // 1. write_outline 写整篇
      await executor.execute(
        'write_outline',
        {'content': '行一\n行二\n行三'},
        scenarioContext: ctx,
      );

      // 2. update_outline 应直接成功（已读标记已生效）
      final r = jsonDecode(await executor.execute(
        'update_outline',
        {'oldString': '行二', 'newString': '行二(改)'},
        scenarioContext: ctx,
      )) as Map<String, dynamic>;
      expect(r['success'], true);

      final outline = await outlineRepo.getOutlineByNovelUrl(defaultNovelUrl);
      expect(outline!.content, '行一\n行二(改)\n行三');
    });
  });

  // ========================================================================
  // update_outline (edit 风格)
  // ========================================================================
  group('update_outline', () {
    test('未先 get_outline 也能 update 成功（已去掉 read-before-write 约束）', () async {
      final novelId = await insertNovel();
      await insertOutline(content: '原内容');
      final ctx = _ctx(novelId);

      // 不调 get_outline，直接 update_outline
      final result = await executor.execute(
        'update_outline',
        {'oldString': '原内容', 'newString': '新内容'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      expect(json['error'], isNull,
          reason: '已去掉 outline_not_read 约束，未读也能 edit');

      final outline = await outlineRepo.getOutlineByNovelUrl(defaultNovelUrl);
      expect(outline!.content, '新内容');
    });

    test('先 get_outline 再 update_outline → 成功，DB 内容已替换', () async {
      final novelId = await insertNovel();
      await insertOutline(content: '原内容');
      final ctx = _ctx(novelId);

      // 先读,标记已读
      await executor.execute('get_outline', {}, scenarioContext: ctx);

      final result = await executor.execute(
        'update_outline',
        {'oldString': '原内容', 'newString': '新内容'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);

      final outline = await outlineRepo.getOutlineByNovelUrl(defaultNovelUrl);
      expect(outline!.content, '新内容');
    });

    test('oldString 找不到 → not_found', () async {
      final novelId = await insertNovel();
      await insertOutline(content: '现成大纲');
      final ctx = _ctx(novelId);
      await executor.execute('get_outline', {}, scenarioContext: ctx);

      final result = await executor.execute(
        'update_outline',
        {'oldString': '不存在的段落', 'newString': 'X'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'not_found');
      expect(json['message'], contains('not found'));
    });

    test('oldString 多处且未 replaceAll → ambiguous_match', () async {
      final novelId = await insertNovel();
      await insertOutline(content: 'foo bar foo baz');
      final ctx = _ctx(novelId);
      await executor.execute('get_outline', {}, scenarioContext: ctx);

      final result = await executor.execute(
        'update_outline',
        {'oldString': 'foo', 'newString': 'X'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'ambiguous_match');
    });

    test('replaceAll=true → 全部替换', () async {
      final novelId = await insertNovel();
      await insertOutline(content: 'foo bar foo baz foo');
      final ctx = _ctx(novelId);
      await executor.execute('get_outline', {}, scenarioContext: ctx);

      final result = await executor.execute(
        'update_outline',
        {'oldString': 'foo', 'newString': 'X', 'replaceAll': true},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);

      final outline = await outlineRepo.getOutlineByNovelUrl(defaultNovelUrl);
      expect(outline!.content, 'X bar X baz X');
    });

    test('oldString 与 newString 相同 → invalid_param', () async {
      final novelId = await insertNovel();
      await insertOutline(content: '内容');
      final ctx = _ctx(novelId);
      await executor.execute('get_outline', {}, scenarioContext: ctx);

      final result = await executor.execute(
        'update_outline',
        {'oldString': '内容', 'newString': '内容'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'invalid_param');
    });

    test('大纲不存在 → not_found，引导用 write_outline', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);
      // 不调 get_outline 直接 update_outline（约束已去，能走到真正的 not_found 分支）
      final result = await executor.execute(
        'update_outline',
        {'oldString': 'A', 'newString': 'B'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'not_found');
      expect(json['suggested_tool'], 'write_outline');
    });

    test('行 trim 容错：AI 漏了行尾空格仍能命中', () async {
      final novelId = await insertNovel();
      await insertOutline(content: '第一幕\n第二幕\n第三幕');
      final ctx = _ctx(novelId);
      await executor.execute('get_outline', {}, scenarioContext: ctx);

      final result = await executor.execute(
        'update_outline',
        {'oldString': '第一幕\n第二幕', 'newString': '第一幕(改)\n第二幕'},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['success'], true);
      final outline = await outlineRepo.getOutlineByNovelUrl(defaultNovelUrl);
      expect(outline!.content, '第一幕(改)\n第二幕\n第三幕');
    });
  });

  // ========================================================================
  // get_outline
  // ========================================================================
  group('get_outline', () {
    test('返回大纲（含 novel 上下文）', () async {
      final novelId = await insertNovel(title: '凡人修仙传');
      await insertOutline(title: '大纲', content: '内容');
      final ctx = _writingContext(novelId, '凡人修仙传');

      final result = await executor.execute(
        'get_outline',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['title'], '大纲');
      expect(json['content'], '内容');
      expect((json['novel'] as Map)['title'], '凡人修仙传');
    });

    test('大纲不存在 → not_found', () async {
      final novelId = await insertNovel();
      final ctx = _ctx(novelId);

      final result = await executor.execute(
        'get_outline',
        {},
        scenarioContext: ctx,
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'not_found');
    });
  });

  // ========================================================================
  // 端到端
  // ========================================================================
  group('端到端流程', () {
    test('select_novel → list_chapters → read_chapter_content 链路', () async {
      // 准备
      final novelUrl = 'https://example.com/chain-test';
      final novel = Novel(
        title: '链路测试',
        author: '作者',
        url: novelUrl,
      );
      await container.read(bookshelfMutationProvider.notifier).addNovel(novel);
      final novelId = (await novelRepo.getNovels())
          .firstWhere((n) => n.url == novelUrl)
          .id!;

      final chapter = Chapter(
        title: '首章',
        url: '$novelUrl/ch1',
        chapterIndex: 0,
        isCached: true,
      );
      await chapterRepoImpl.cacheChapter(novelUrl, chapter, '首章内容');
      await chapterRepoImpl.cacheNovelChapters(novelUrl, [chapter]);

      final ctx = _writingContext(novelId, '链路测试');

      // 1. select_novel
      final r1 = jsonDecode(
        await executor.execute('select_novel', {'novelId': novelId}),
      ) as Map<String, dynamic>;
      expect(r1['success'], true);
      expect(r1['title'], '链路测试');

      // 2. list_chapters
      final r2 = jsonDecode(
        await executor.execute('list_chapters', {}, scenarioContext: ctx),
      ) as Map<String, dynamic>;
      expect((r2['novel'] as Map)['title'], '链路测试');
      final chList = (r2['chapters'] as List);
      expect(chList.first['position'], 1);

      // 3. read_chapter_content
      final r3 = await executor.execute(
        'read_chapter_content',
        {'position': 1},
        scenarioContext: ctx,
      );
      expect(r3, '首章内容');
    });
  });

  // ========================================================================
  // 错误处理
  // ========================================================================
  group('错误处理', () {
    test('未知工具 → unknown_tool 错误', () async {
      final result = await executor.execute('unknown_tool', {});
      final json = jsonDecode(result) as Map<String, dynamic>;

      expect(json['error'], 'unknown_tool');
      expect(json['message'].toString(), contains('unknown_tool'));
    });
  });
}

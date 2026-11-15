/// 章节写入工具的 JSON 污染防线测试（真实 DB 链路）
///
/// 背景（反馈 #16「llm替换文字，出现错乱」）：模型生成入参时 JSON 结构错乱，
/// newString 值吞进工具调用结构尾巴（`正文……", "oldString": "……", "position": 79}`），
/// 整体恰好仍是合法 JSON 而被正常解析落库，正文从此带垃圾。
///
/// 验证：
/// 1. update_chapter_content 的 newString 含 JSON 结构 → json_contaminated_content，
///    数据库正文不变；
/// 2. 干净 newString → 正常替换落库（且片段过 sanitize）；
/// 3. 清理陷阱：正文已有历史污染时，用干净 newString 做清理编辑必须成功
///    （检测只针对模型本次产出的增量，不查全文）；
/// 4. save_chapter 的 content 含 JSON 结构 → 拒绝且不建章；
/// 5. save_chapter 干净正文 → 正常落库。
///
/// 运行:
///   cd novel_builder
///   flutter test test/unit/services/novel_agent/chapter_write_json_contamination_test.dart
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

final _toolExecutorProvider = Provider<ToolExecutor>((ref) {
  return ToolExecutor(ref);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;
  late int novelId;
  const novelUrl = 'custom://json-contamination-test';
  const chapterUrl = '$novelUrl#ch1';

  /// 反馈 #16 实际形态：正文 + 工具调用结构尾巴
  const contaminatedNewString =
      '许曼璃抱着陈北的胳膊往店里走去。\n她柔软的身子紧紧贴着陈北的手臂，'
      '让陈北心头微微一荡。", "oldString": "许曼璃抱着陈北的胳膊往店里走去。", '
      '"position": 1}';

  final cleanOriginal = '许曼璃抱着陈北的胳膊往店里走去。\n她点了一份烤茄子。';

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider.overrideWithValue(
        DatabaseConnection.forTesting(db),
      ),
    ]);
    executor = container.read(_toolExecutorProvider);

    novelId = await container
        .read(bookshelfMutationProvider.notifier)
        .addNovel(
          Novel(title: '测试书', author: '作者', url: novelUrl),
        );

    // 直接种入章节行 + 缓存正文（走 ChapterMutation 需要完整 NovelChapter
    // 对象，测试里直插两表等价且更直白）
    await db.insert('novel_chapters', {
      'novelUrl': novelUrl,
      'chapterUrl': chapterUrl,
      'title': '第1章',
      'chapterIndex': 0,
    });
    await db.insert('chapter_cache', {
      'novelUrl': novelUrl,
      'chapterUrl': chapterUrl,
      'title': '第1章',
      'content': cleanOriginal,
      'chapterIndex': 0,
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  AgentScenarioContext makeCtx() =>
      AgentScenarioContext(currentNovelId: novelId);

  Future<String> chapterContentInDb() async {
    final rows = await db.query(
      'chapter_cache',
      where: 'chapterUrl = ?',
      whereArgs: [chapterUrl],
    );
    return rows.single['content'] as String;
  }

  group('update_chapter_content JSON 污染防线', () {
    test('newString 含结构尾巴 → json_contaminated_content，DB 不变', () async {
      final result = await executor.execute(
        'update_chapter_content',
        {
          'position': 1,
          'oldString': '她点了一份烤茄子。',
          'newString': contaminatedNewString,
        },
        scenarioContext: makeCtx(),
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'json_contaminated_content');
      expect(json['message'], contains('JSON'));
      // 拒写：数据库正文保持原样
      expect(await chapterContentInDb(), cleanOriginal);
    });

    test('干净 newString → 正常替换落库（markdown 标记被 sanitize）', () async {
      final result = await executor.execute(
        'update_chapter_content',
        {
          'position': 1,
          'oldString': '她点了一份烤茄子。',
          'newString': '她点了一份烤茄子，**加了两串腰子**，还多要了一瓶啤酒。',
        },
        scenarioContext: makeCtx(),
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: 'result=$result');

      final content = await chapterContentInDb();
      expect(content, contains('加了两串腰子'));
      expect(content, isNot(contains('**')), reason: 'markdown 标记应被剥除');
    });

    test('清理陷阱：正文已有历史污染，干净 newString 清理 → 必须成功', () async {
      // 把历史污染种进正文（模拟上一版 bug 已落库的垃圾）
      final polluted = '$cleanOriginal\n'
          '她软成一滩水。", "oldString": "她点了一份烤茄子。", "position": 1}';
      await db.update(
        'chapter_cache',
        {'content': polluted},
        where: 'chapterUrl = ?',
        whereArgs: [chapterUrl],
      );

      // 模型把污染段连同尾巴整体替换为干净文字（oldString 含 JSON 尾巴是
      // 逐字匹配原文的正当要求，newString 干净）
      final result = await executor.execute(
        'update_chapter_content',
        {
          'position': 1,
          'oldString': '她点了一份烤茄子。\n'
              '她软成一滩水。", "oldString": "她点了一份烤茄子。", "position": 1}',
          'newString': '她点了一份烤茄子，心满意足。',
        },
        scenarioContext: makeCtx(),
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue,
          reason: '清理编辑不得被历史污染拦死: result=$result');
      expect(await chapterContentInDb(),
          '许曼璃抱着陈北的胳膊往店里走去。\n她点了一份烤茄子，心满意足。');
    });

    test('oldString 含污染尾巴但 newString 干净 → 放行（逐字匹配正当要求）',
        () async {
      // 与上一条互补：只要增量干净，oldString 里有什么都不关检测的事
      final result = await executor.execute(
        'update_chapter_content',
        {
          'position': 1,
          'oldString': cleanOriginal,
          'newString': '新的开头。\n新的第二段。',
        },
        scenarioContext: makeCtx(),
      );
      expect(
        (jsonDecode(result) as Map<String, dynamic>)['success'],
        isTrue,
      );
    });
  });

  group('save_chapter JSON 污染防线', () {
    test('content 含结构尾巴 → json_contaminated_content，不建章', () async {
      final before = await db.query(
        'novel_chapters',
        where: 'novelUrl = ?',
        whereArgs: [novelUrl],
      );
      final result = await executor.execute(
        'save_chapter',
        {
          'position': 2,
          'title': '第2章',
          'content': '第二章正文开头。\n\n${'剧情段落。' * 40}'
              '", "oldString": "第一章内容", "position": 2}',
        },
        scenarioContext: makeCtx(),
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['error'], 'json_contaminated_content');

      final after = await db.query(
        'novel_chapters',
        where: 'novelUrl = ?',
        whereArgs: [novelUrl],
      );
      expect(after.length, before.length, reason: '垃圾不得建章');
    });

    test('整体即 JSON 的 content → 拒绝', () async {
      final result = await executor.execute(
        'save_chapter',
        {
          'position': 2,
          'content': '{"title": "第2章", "content": "${'正文段落。' * 40}"}',
        },
        scenarioContext: makeCtx(),
      );
      expect(
        (jsonDecode(result) as Map<String, dynamic>)['error'],
        'json_contaminated_content',
      );
    });

    test('干净正文（≥300 字）→ 正常建章', () async {
      final result = await executor.execute(
        'save_chapter',
        {
          'position': 2,
          'title': '第2章',
          'content': '第二章正文。\n\n${'夜色渐深，烧烤店里人声鼎沸。' * 30}',
        },
        scenarioContext: makeCtx(),
      );
      final json = jsonDecode(result) as Map<String, dynamic>;
      expect(json['success'], isTrue, reason: 'result=$result');
      expect(json['chapterTitle'], '第2章');
    });
  });
}

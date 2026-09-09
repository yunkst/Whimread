/// 复现 bug：同一轮 LLM 发出多个章节读取工具调用时，只有第一个成功，
/// 后续工具调用全部卡住。
///
/// 完全模拟 AgentLoop.run 第 5 步的串行 for 循环模式
/// （lib/services/novel_agent/agent_loop.dart）：
///   for (final call in toolCalls) {
///     messages.add(await _executeSingleTool(call, ...));
///   }
/// 即严格 await 前一个工具完成后再执行下一个。
///
/// 每个工具调用包一层超时护栏，若复现卡死，测试会精确报告卡在第几个调用、
/// 卡在哪个工具上，而不是无限挂起。
///
/// 运行:
///   flutter test test/bug/chapter_read_multi_tool_hang_test.dart
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_repository.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../helpers/test_database_setup.dart' as test_db;

/// 单个工具调用的超时护栏。
///
/// 生产环境的 read_chapter_content 在真实设备上是百毫秒级；
/// 桌面 ffi 内存库更快。10s 还不返回即可判定为「卡住」而非「慢」。
const _perToolTimeout = Duration(seconds: 10);

/// 单章正文的模拟大小（~4KB，接近真实小说章节 3000-8000 字）
String _chapterContent(int chapterIndex, {String? keyword}) {
  final buf = StringBuffer();
  for (var p = 0; p < 80; p++) {
    buf.write('这是第$chapterIndex章的第$p个段落，讲述主角的冒险经历与心理活动。');
  }
  if (keyword != null) {
    buf.write('关键词锚点：$keyword。');
  }
  return buf.toString();
}

final _toolExecutorProvider = Provider<ToolExecutor>((ref) {
  return ToolExecutor(ref);
});

void main() {
  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;
  late INovelRepository novelRepo;
  late IChapterRepository chapterRepo;
  late ChapterRepository chapterRepoImpl;

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
    executor = container.read(_toolExecutorProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  const defaultNovelUrl = 'https://example.com/novel1';

  Future<int> seedNovelWithChapters({
    int chapterCount = 50,
    String keyword = '剑客',
  }) async {
    final novel = Novel(
      title: '卡死复现小说',
      author: '测试作者',
      url: defaultNovelUrl,
    );
    await container.read(bookshelfMutationProvider.notifier).addNovel(novel);
    final novelId = (await novelRepo.getNovels())
        .firstWhere((n) => n.url == defaultNovelUrl)
        .id!;

    final chapters = <Chapter>[];
    for (var i = 0; i < chapterCount; i++) {
      final url = '$defaultNovelUrl/ch$i';
      final content = _chapterContent(i, keyword: i.isEven ? keyword : null);
      chapters.add(Chapter(
        title: '第${i + 1}章',
        url: url,
        chapterIndex: i,
        isCached: true,
      ));
      await chapterRepoImpl.cacheChapter(defaultNovelUrl, chapters.last, content);
    }
    await chapterRepoImpl.cacheNovelChapters(defaultNovelUrl, chapters);
    return novelId;
  }

  /// 模拟 AgentLoop 同一轮串行执行多个工具调用。
  /// 返回每个调用的 (工具名, 耗时ms, 是否超时)。
  Future<List<(String, int, bool)>> runRoundTools(
    List<(String, Map<String, dynamic>)> calls,
    AgentScenarioContext ctx,
  ) async {
    final timings = <(String, int, bool)>[];
    for (final (name, args) in calls) {
      final sw = Stopwatch()..start();
      var timedOut = false;
      try {
        await executor.execute(name, args, scenarioContext: ctx)
            .timeout(_perToolTimeout);
      } on TimeoutException {
        timedOut = true;
      }
      sw.stop();
      timings.add((name, sw.elapsedMilliseconds, timedOut));
      if (timedOut) break; // 复现卡死即停，报告卡点
    }
    return timings;
  }

  void expectNoHang(List<(String, int, bool)> timings, List<String> names) {
    for (var i = 0; i < names.length; i++) {
      final done = i < timings.length && !timings[i].$3;
      expect(done, true,
          reason: '同轮第 ${i + 1} 个工具 ${names[i]} 卡住（超时 '
              '${_perToolTimeout.inSeconds}s 未返回）。'
              '已完成: ${timings.map((t) => '${t.$1}=${t.$2}ms${t.$3 ? "[超时!]" : ""}').join(', ')}');
    }
  }

  group('同一轮多个 read_chapter_content（模拟 AgentLoop 串行 for 循环）', () {
    test('3 个 read_chapter_content 依次全部成功，无卡死', () async {
      final novelId = await seedNovelWithChapters(chapterCount: 50);
      final ctx = AgentScenarioContext(
        currentNovelId: novelId,
        currentNovelTitle: '卡死复现小说',
      );

      final names = ['read#1', 'read#2', 'read#3'];
      final timings = await runRoundTools(const [
        ('read_chapter_content', {'position': 1}),
        ('read_chapter_content', {'position': 2}),
        ('read_chapter_content', {'position': 3}),
      ], ctx);

      // ignore: avoid_print
      print('串行 read×3 耗时: ${timings.map((t) => '${t.$1}=${t.$2}ms').join(', ')}');
      expectNoHang(timings, names);
    });

    test('混合负载：list_chapters + read×2 + search_in_chapters', () async {
      final novelId = await seedNovelWithChapters(chapterCount: 50);
      final ctx = AgentScenarioContext(
        currentNovelId: novelId,
        currentNovelTitle: '卡死复现小说',
      );

      final names = ['list_chapters', 'read#1', 'read#2', 'search'];
      final timings = await runRoundTools(const [
        ('list_chapters', {}),
        ('read_chapter_content', {'position': 10}),
        ('read_chapter_content', {'position': 20}),
        ('search_in_chapters', {'keyword': '剑客'}),
      ], ctx);

      // ignore: avoid_print
      print('混合负载耗时: ${timings.map((t) => '${t.$1}=${t.$2}ms').join(', ')}');
      expectNoHang(timings, names);
    });

    test('大规模：200 章真实内容体量下的同轮串行调用', () async {
      final novelId = await seedNovelWithChapters(chapterCount: 200);
      final ctx = AgentScenarioContext(
        currentNovelId: novelId,
        currentNovelTitle: '卡死复现小说',
      );

      final names = ['read#1', 'list_chapters', 'search', 'read#2'];
      final timings = await runRoundTools(const [
        ('read_chapter_content', {'position': 100}),
        ('list_chapters', {}),
        ('search_in_chapters', {'keyword': '剑客'}),
        ('read_chapter_content', {'position': 150}),
      ], ctx);

      // ignore: avoid_print
      print('200章大规模耗时: ${timings.map((t) => '${t.$1}=${t.$2}ms').join(', ')}');
      expectNoHang(timings, names);
    });
  });
}

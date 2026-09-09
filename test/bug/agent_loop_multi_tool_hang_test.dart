/// 进阶复现：使用真实 AgentLoop + 真实 WritingScenario + 真实 SQLite
/// + 可编程假 LLM（一轮发 3 个 read_chapter_content tool_calls），
/// 验证「第一个成功，后续卡死」是否在 AgentLoop 流式消费的链路里。
///
/// 之前的 chapter_read_multi_tool_hang_test 仅跑了 ToolExecutor 的纯链路，
/// 全部通过。本测试把 AgentLoop.run 的全部机制接进来：
///   LLM 流订阅（streamSub + streamCompleter）→ 工具聚合 → 串行 for 循环
///   → 工具执行 → emit 事件 → 下一轮 LLM 调用
///
/// 假 LLM 第一轮发 3 个 read_chapter_content，第二轮发 stop。
/// 若「第一个成功、后续卡死」真实存在，第二轮永远进不去，本测试会精确报告
/// 卡在哪个工具上。
///
/// 运行:
///   flutter test test/bug/agent_loop_multi_tool_hang_test.dart
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_chapter_repository.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/chapter_repository.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_config.dart';
import 'package:novel_app/services/dsl_engine/llm_provider_core.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_loop.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/scenarios/writing_scenario.dart';
import '../helpers/test_database_setup.dart' as test_db;

class _NoopHttp implements LlmHttpClient {
  @override
  Future<String> postJson(String url, Map<String, String> headers, String body) {
    throw UnimplementedError();
  }

  @override
  Stream<String> postJsonStream(
      String url, Map<String, String> headers, String body) {
    throw UnimplementedError();
  }
}

/// 可编程假 LLM：每次 chatStreamWithTools 调用消耗一个脚本（chunk 列表）。
/// Round 1 脚本：3 个 read_chapter_content + finish=tool_calls
/// Round 2 脚本：空内容 + finish=stop（结束）
class _FakeLlm extends LlmProvider {
  _FakeLlm(this._rounds)
      : super(
          const LlmConfig(
              baseUrl: 'http://test',
              apiKey: 'fake',
              defaultModel: 'fake'),
          httpClient: _NoopHttp(),
        );

  /// 每轮一个脚本（按调用顺序消费）
  final List<List<LlmStreamChunk>> _rounds;
  int _roundIndex = 0;
  final List<String> _consumedRounds = [];

  List<String> get consumedRounds => List.unmodifiable(_consumedRounds);

  @override
  Stream<LlmStreamChunk> chatStreamWithTools({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
  }) async* {
    if (_roundIndex >= _rounds.length) {
      throw StateError('FakeLlm: 第 ${_roundIndex + 1} 轮没有准备脚本，'
          '可能是 hang 导致 loop 不停向 LLM 发请求');
    }
    final idx = _roundIndex++;
    _consumedRounds.add('round ${idx + 1} (msgs=${messages.length})');
    for (final c in _rounds[idx]) {
      await Future<void>.delayed(Duration.zero); // 让出事件循环
      yield c;
    }
  }
}

/// 通过 provider 拿到带真实 Ref 的 WritingScenario
final _writingScenarioProvider =
    Provider<WritingScenario>((ref) => WritingScenario(ref));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
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
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> seedNovelWithChapters({
    int chapterCount = 5,
    String keyword = '剑客',
  }) async {
    const novelUrl = 'https://example.com/novel_loop';
    final novel = Novel(
      title: 'Loop测试',
      author: 't',
      url: novelUrl,
    );
    await container.read(bookshelfMutationProvider.notifier).addNovel(novel);
    final novelId = (await novelRepo.getNovels())
        .firstWhere((n) => n.url == novelUrl)
        .id!;

    final chapters = <Chapter>[];
    for (var i = 0; i < chapterCount; i++) {
      final url = '$novelUrl/ch$i';
      chapters.add(Chapter(
        title: '第${i + 1}章',
        url: url,
        chapterIndex: i,
        isCached: true,
      ));
      await chapterRepoImpl.cacheChapter(
          novelUrl, chapters.last, '内容: $keyword 第${i + 1}章');
    }
    await chapterRepoImpl.cacheNovelChapters(novelUrl, chapters);
    return novelId;
  }

  /// 收集所有 emit 出来的事件 + 监控 hang
  Future<List<AgentEvent>> runAgent(
    _FakeLlm llm,
    int novelId, {
    Duration overallTimeout = const Duration(seconds: 30),
  }) async {
    final events = <AgentEvent>[];
    final completer = Completer<void>();

    final scenario = container.read(_writingScenarioProvider);
    // _currentContext 通过 buildSystemPrompt 注入（与真实调用一致）
    scenario.buildSystemPrompt(AgentScenarioContext(
      currentNovelId: novelId,
      currentNovelTitle: 'Loop测试',
    ));

    final loop = AgentLoop(
      llm: llm,
      scenario: scenario,
      config: const AgentLoopConfig(
        maxRounds: 5,
        llmStreamTimeout: Duration(seconds: 5),
      ),
    );

    // 兜底：超过 overallTimeout 仍未结束则报 hang
    Timer(overallTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(
          'AgentLoop.run 超过 ${overallTimeout.inSeconds}s 未结束 → 复现 hang',
        ));
      }
    });

    unawaited(loop.run(
      initialMessages: const [
        ChatMessage(role: 'user', content: '请读三章'),
      ],
      systemPrompt: '你是写作助手。',
      emit: events.add,
    ).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    }));

    await completer.future;
    return events;
  }

  /// 第一轮发 3 个 read_chapter_content（position 1/2/3），第二轮发 stop。
  List<List<LlmStreamChunk>> multiReadScript() => [
        [
          LlmStreamChunk(
            toolCallDeltas: [
              {
                'index': 0,
                'id': 'call_a',
                'function': {
                  'name': 'read_chapter_content',
                  'arguments': jsonEncode({'position': 1}),
                },
              },
              {
                'index': 1,
                'id': 'call_b',
                'function': {
                  'name': 'read_chapter_content',
                  'arguments': jsonEncode({'position': 2}),
                },
              },
              {
                'index': 2,
                'id': 'call_c',
                'function': {
                  'name': 'read_chapter_content',
                  'arguments': jsonEncode({'position': 3}),
                },
              },
            ],
            finishReason: 'tool_calls',
          ),
        ],
        // Round 2: 正常结束
        [
          const LlmStreamChunk(contentChunk: '已读完三章。', finishReason: 'stop'),
        ],
      ];

  /// dump 出 ToolCall start/end/done/error 事件序列（按发生顺序）
  String summarize(List<AgentEvent> events) {
    final sw = StringBuffer();
    for (final e in events) {
      if (e is ToolCallStartEvent) {
        sw.write('[START ${e.name}]');
      } else if (e is ToolCallEndEvent) {
        sw.write('[END ${e.name} ok=${e.success}]');
      } else if (e is AgentDoneEvent) {
        sw.write('[AgentDone]');
      } else if (e is AgentErrorEvent) {
        sw.write('[Error: ${e.error}]');
      }
    }
    return sw.toString();
  }

  test('AgentLoop: 一轮 3 个 read_chapter_content 应全部完成 + 进入下一轮 stop', () async {
    final novelId = await seedNovelWithChapters(chapterCount: 3);
    final llm = _FakeLlm(multiReadScript());

    final events = await runAgent(llm, novelId);

    final readStarts = events
        .whereType<ToolCallStartEvent>()
        .where((e) => e.name == 'read_chapter_content')
        .toList();
    final readEnds = events
        .whereType<ToolCallEndEvent>()
        .where((e) => e.name == 'read_chapter_content')
        .toList();

    // ignore: avoid_print
    print('事件序列: ${summarize(events)}');
    // ignore: avoid_print
    print('LLM 消费轮数: ${llm.consumedRounds}');

    expect(llm.consumedRounds.length, 2,
        reason: '进入第 2 轮 stop 说明第 1 轮的 3 个工具全部完成并回到 loop；'
            '只消耗 1 轮 = hang 在工具执行阶段。实际: ${llm.consumedRounds}');

    expect(readStarts.length, 3,
        reason: '第 1 轮 LLM 发了 3 个 read_chapter_content，'
            '应为每个 emit 一次 ToolCallStartEvent。事件序列: ${summarize(events)}');
    expect(readEnds.length, 3,
        reason: '每个 read_chapter_content 都应 emit 一次 ToolCallEndEvent；'
            '不足 3 = 后续工具卡死。事件序列: ${summarize(events)}');

    expect(readEnds.every((e) => e.success), true,
        reason: '每个工具都应该成功。事件序列: ${summarize(events)}');

    expect(
        events.whereType<AgentDoneEvent>().length,
        greaterThanOrEqualTo(1),
        reason: '应最终 emit AgentDoneEvent；没有 = loop 没结束。'
            '事件序列: ${summarize(events)}');
  });
}

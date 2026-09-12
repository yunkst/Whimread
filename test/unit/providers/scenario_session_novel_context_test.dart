/// ScenarioSession「当前小说上下文」生命周期测试
///
/// 锁定 2026-09-05 修复的两个问题：
/// 1. hydrate 不再无条件清空 currentNovel：
///    - 修复前：空会话（0 条消息）下每次 sendMessage → _ensureSessionId →
///      hydrateIfNeeded → clearCurrentNovel: true + _currentNovel = null，
///      用户刚选的小说瞬间被清空，Agent 被迫重新 list_novels + select_novel。
///    - 修复后：内存已有值优先（防 fire-and-forget hydrate 竞态），否则从
///      DB 持久值（chat_sessions.currentNovelId）恢复，都没有才清空。
/// 2. adoptSession 切换会话时小说上下文跟随目标会话从 DB 恢复。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/providers/scenario_session_novel_context_test.dart
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/current_novel_provider.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';

import '../../helpers/test_database_setup.dart';

/// 直接从容器拿 Ref，用于构造独立的 ScenarioSession（不经过
/// scenarioSessionsProvider，避免 fire-and-forget hydrate 的不确定性）。
final _refProvider = Provider<Ref>((ref) => ref);

/// INovelRepository 最小 fake：只实现 selectCurrentNovel 需要的 getNovelById。
class _FakeNovelRepository implements INovelRepository {
  final Map<int, Novel> _byId;

  /// 非 null 时对 [delayedNovelId] 的查询延迟返回，
  /// 用于制造 hydrateIfNeeded 的 await 时间窗（issue #22 交叉时序）。
  Duration? getNovelDelay;
  int? delayedNovelId;

  _FakeNovelRepository(Map<int, Novel> byId) : _byId = byId;

  @override
  Future<Novel?> getNovelById(int id) async {
    final delay = getNovelDelay;
    if (delay != null && id == delayedNovelId) {
      await Future<void>.delayed(delay);
    }
    return _byId[id];
  }

  @override
  Future<List<Novel>> getNovels() async => _byId.values.toList();

  @override
  Future<bool> isInBookshelf(String novelUrl) => throw UnimplementedError();

  @override
  Future<int> updateLastReadChapter(String novelUrl, int chapterIndex) =>
      throw UnimplementedError();

  @override
  Future<int> updateBackgroundSetting(
          String novelUrl, String? backgroundSetting) =>
      throw UnimplementedError();

  @override
  Future<String?> getBackgroundSetting(String novelUrl) =>
      throw UnimplementedError();

  @override
  Future<int> getLastReadChapter(String novelUrl) => throw UnimplementedError();

  @override
  Future<Novel?> getNovelByTitle(String title) => throw UnimplementedError();

  @override
  Future<Novel?> getNovelByUrl(String novelUrl) => throw UnimplementedError();

  @override
  Future<String?> getNovelUrlById(int id) => throw UnimplementedError();

  @override
  Future<int> updateBackgroundSettingById(int id, String? setting) =>
      throw UnimplementedError();

  @override
  Future<int> updateCoverMediaIdById(int id, String? mediaId) =>
      throw UnimplementedError();
}

/// MockNovelAgentService：让 sendMessage 跑通完整回合（TextDelta + Done），
/// 并记录每轮收到的 scenarioContext.currentNovelId（LLM 实际看到的上下文）。
class _MockNovelAgentService implements NovelAgentService {
  final _controller = StreamController<AgentEvent>.broadcast();

  /// 每轮 sendMessage 收到的 currentNovelId（按调用顺序）
  final List<int?> contextNovelIds = [];

  @override
  Ref get ref => throw UnimplementedError();

  @override
  bool get isRunning => false;

  @override
  bool isRunningFor(String scenarioId) => false;

  @override
  Stream<AgentEvent> get events => _controller.stream;

  @override
  Future<void> sendMessage({
    required String userInput,
    required List<dynamic> history,
    required String scenarioId,
    required AgentScenarioContext scenarioContext,
    String? runId,
  }) async {
    contextNovelIds.add(scenarioContext.currentNovelId);
    // 等一帧让 ScenarioSession 的事件监听先注册上
    await Future<void>.delayed(Duration.zero);
    _controller.add(TextDeltaEvent('回复: $userInput'));
    _controller.add(const AgentDoneEvent());
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> resumeFromMessages({
    required String scenarioId,
    required List<dynamic> initialMessages,
    required AgentScenarioContext scenarioContext,
    String? runId,
  }) async {
    contextNovelIds.add(scenarioContext.currentNovelId);
    await Future<void>.delayed(Duration.zero);
    _controller.add(TextDeltaEvent('续写回复'));
    _controller.add(const AgentDoneEvent());
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void cancelFor(String scenarioId) {}

  @override
  void cancelAll() {}

  @override
  void addEvent(AgentEvent event) => _controller.add(event);

  @override
  void dispose() => _controller.close();

  @override
  void injectUserMessage(String scenarioId, String text) {}
}

void main() {
  late ProviderContainer container;
  late Ref ref;
  late ChatSessionRepository repo;
  late _MockNovelAgentService mock;
  late _FakeNovelRepository novelRepo;

  setUp(() async {
    final db = await TestDatabaseSetup.createInMemoryDatabase();
    repo = ChatSessionRepository(dbConnection: DatabaseConnection.forTesting(db));
    mock = _MockNovelAgentService();
    novelRepo = _FakeNovelRepository({
      7: Novel(id: 7, title: '凡人修仙传', author: '忘语', url: 'u7'),
      8: Novel(id: 8, title: '诡秘之主', author: '爱潜水的乌贼', url: 'u8'),
    });
    container = ProviderContainer(overrides: [
      novelAgentServiceProvider.overrideWith((ref) => mock),
      chatSessionRepositoryProvider.overrideWith((ref) => repo),
      novelRepositoryProvider.overrideWithValue(novelRepo),
    ]);
    ref = container.read(_refProvider);
  });

  tearDown(() async {
    container.dispose();
    await DatabaseConnection.resetInstance();
  });

  /// 在 DB 建一条 chat_session 行，可带持久化的 currentNovel
  Future<int> seedSession({int? novelId, String? novelTitle}) {
    return repo.createSession(ChatSession(
      scenarioId: ScenarioIds.writing,
      title: 't',
      currentNovelId: novelId,
      currentNovelTitle: novelTitle,
    ));
  }

  ScenarioSession buildSession(int? initialSessionId) => ScenarioSession(
        scenarioId: ScenarioIds.writing,
        ref: ref,
        initialSessionId: initialSessionId,
      );

  group('hydrateIfNeeded 小说上下文恢复（2026-09-05 修复）', () {
    test('DB 有持久值时恢复，不再无条件清空', () async {
      final sid = await seedSession(novelId: 7, novelTitle: '凡人修仙传');
      final session = buildSession(sid);

      expect(session.currentNovel, isNull);
      await session.hydrateIfNeeded();

      expect(session.currentNovel?.id, 7,
          reason: 'hydrate 应从 chat_sessions.currentNovelId 恢复上下文');
      expect(session.currentNovel?.title, '凡人修仙传');
      expect(session.state.currentNovel?.id, 7,
          reason: 'UI 投影（AgentChatHeader 依赖）同步恢复');
      expect(container.read(currentNovelProvider)?.id, 7,
          reason: '恢复即选择：全局 currentNovelProvider 跟随会话恢复同步'
              '（打开历史会话时应看到上次选的小说）');
    });

    test('loadNovel await 期间被 selectNovel 抢先时以内存为准（issue #22）', () async {
      final sid = await seedSession(novelId: 7, novelTitle: '凡人修仙传');
      final session = buildSession(sid);

      // 仅对 DB 中的 novel 7 加延迟，制造 hydrate await 期间的时间窗
      novelRepo.getNovelDelay = const Duration(milliseconds: 80);
      novelRepo.delayedNovelId = 7;
      addTearDown(() {
        novelRepo.getNovelDelay = null;
        novelRepo.delayedNovelId = null;
      });

      final hydrating = session.hydrateIfNeeded();
      // hydrate 阻塞在 loadNovel(7) 期间，用户/工具抢先选了另一本
      await session.selectNovel(8);
      await hydrating;

      expect(session.currentNovel?.id, 8,
          reason: 'await 返回后不得用 DB 旧值 7 覆盖 await 期间写入的选择 8');
      expect(session.state.currentNovel?.id, 8);
    });

    test('内存已有选择时以内存为准（防 fire-and-forget hydrate 竞态）', () async {
      final sid = await seedSession(novelId: 7, novelTitle: '凡人修仙传');
      final session = buildSession(sid);

      // 用户在后台 hydrate 完成前刚选了另一本
      final picked = await session.selectNovel(8);
      expect(picked?.id, 8);

      await session.hydrateIfNeeded();

      expect(session.currentNovel?.id, 8,
          reason: '竞态守卫：内存中用户刚选的值不能被 DB 旧值覆盖');
    });

    test('持久化的小说已被删除时优雅清空', () async {
      final sid = await seedSession(novelId: 999, novelTitle: '已删除的书');
      final session = buildSession(sid);

      await session.hydrateIfNeeded();

      expect(session.currentNovel, isNull);
      expect(session.state.currentNovel, isNull);
    });

    test('无持久值且内存为空时维持清空（原行为不回归）', () async {
      final sid = await seedSession();
      final session = buildSession(sid);

      await session.hydrateIfNeeded();

      expect(session.currentNovel, isNull);
    });
  });

  group('adoptSession 小说上下文跟随会话', () {
    test('切到含持久小说的会话恢复该小说，全局选择同步跟随', () async {
      final sid1 = await seedSession(novelId: 7, novelTitle: '凡人修仙传');
      final sid2 = await seedSession(novelId: 8, novelTitle: '诡秘之主');
      final session = buildSession(sid1);

      // 用户主动选了 7 → 全局 = 7
      await session.selectNovel(7);
      expect(container.read(currentNovelProvider)?.id, 7);

      await session.adoptSession(sid2);
      expect(session.currentNovel?.id, 8,
          reason: '切换历史会话后小说上下文应跟随目标会话');
      expect(container.read(currentNovelProvider)?.id, 8,
          reason: '打开历史会话 = 同时选择该会话的小说，全局应同步为 8');

      await session.adoptSession(null);
      expect(session.currentNovel, isNull,
          reason: '开启全新会话时无上下文可恢复，应清空');
      expect(container.read(currentNovelProvider), isNull,
          reason: '全新会话无小说上下文，全局选择一并清空保持一致');
    });
  });

  group('会话标题自动跟随小说（2026-09-12）', () {
    test('发首条消息新建会话时以当前小说命名', () async {
      final session = buildSession(null);

      await session.selectNovel(7);
      await session.sendMessage(content: '继续写第一章');

      final sessions = await repo.listSessionsByScenario(ScenarioIds.writing);
      expect(sessions, hasLength(1));
      expect(sessions.first.title, '凡人修仙传',
          reason: '新建会话名 = 当前选中的小说');
      expect(sessions.first.currentNovelId, 7);
    });

    test('空标题会话首次选书后自动命名', () async {
      // 模拟「+ 新建会话」先建了空标题行，用户随后才选书
      final sid = await repo.createSession(ChatSession(
        scenarioId: ScenarioIds.writing,
        title: '',
      ));
      final session = buildSession(sid);

      await session.selectNovel(7);

      final row = await repo.getSession(sid);
      expect(row?.title, '凡人修仙传');
    });

    test('自动命名的会话切书后标题跟随最后一本', () async {
      final sid = await repo.createSession(ChatSession(
        scenarioId: ScenarioIds.writing,
        title: '凡人修仙传',
        currentNovelId: 7,
        currentNovelTitle: '凡人修仙传',
      ));
      final session = buildSession(sid);

      await session.selectNovel(8);

      final row = await repo.getSession(sid);
      expect(row?.title, '诡秘之主',
          reason: '旧标题 == 旧 currentNovelTitle（自动命名）→ 跟随新书');
      expect(row?.currentNovelId, 8);
    });

    test('用户手动重命名后标题不再自动跟随', () async {
      final sid = await repo.createSession(ChatSession(
        scenarioId: ScenarioIds.writing,
        title: '我的创作会话',
        currentNovelId: 7,
        currentNovelTitle: '凡人修仙传',
      ));
      final session = buildSession(sid);

      await session.selectNovel(8);

      final row = await repo.getSession(sid);
      expect(row?.title, '我的创作会话',
          reason: '旧标题 ≠ 旧 currentNovelTitle（手动改过）→ 不覆盖');
    });
  });

  group('sendMessage 跨回合保持（bug 回归用例）', () {
    test('空会话选小说后发首条消息，选择不被 hydrate 清空且 LLM 可见', () async {
      // 复现时序：空会话（0 条消息）→ 选小说 → 发第一条消息
      // 修复前：_ensureSessionId → hydrateIfNeeded 清空 currentNovel，
      //        LLM 看到的 context.currentNovelId 为 null，被迫重新选书。
      final sid = await seedSession();
      final session = buildSession(sid);

      await session.selectNovel(7);
      expect(session.currentNovel?.id, 7);

      await session.sendMessage(content: '继续写第一章');

      expect(mock.contextNovelIds, [7],
          reason: '本轮 LLM 的 AgentScenarioContext.currentNovelId 必须是已选小说');
      expect(session.currentNovel?.id, 7,
          reason: '第一轮结束后选择仍保持');
      expect(session.state.currentNovel?.id, 7);

      // 第二轮（此时消息非空，hydrate 早退）继续保持
      await session.sendMessage(content: '继续');
      expect(mock.contextNovelIds, [7, 7]);
      expect(session.currentNovel?.id, 7);

      // DB 持久值未被破坏
      final row = await repo.getSession(sid);
      expect(row?.currentNovelId, 7);
    });
  });
}

/// ScenarioSession.selectNovel 单元测试（picker 写入路径契约）
///
/// 锁定 2026-07-29 修复：AgentChatHeader 的"小说上下文"点击选择小说
/// 后，需要通过 ScenarioSession.selectNovel 把当前小说写回 state，
/// UI 才能显示。修复前 `_showNovelPicker` 把 dialog 返回的 novelId 丢弃，
/// 导致选了小说 UI 一直显示"尚未选择小说"。
///
/// 这里直接覆盖 `ScenarioSession.selectNovel(novelId)`：
/// - 给定一个存在的 novelId + 对应 Novel，调用后 state.currentNovel 必须更新
/// - state 会通过 _notifyStateChanged 推到 scenarioSessionsProvider → currentChatStateProvider
/// - 与 header 端的"已选小说显示书名"widget 测试组合，锁死整条链路
///
/// 不依赖真实 DB（用最小 INovelRepository fake，只暴露 selectNovel 走的两个方法）。
/// selectNovel → _persistCurrentNovel 路径在没有 sessionId 时直接返回，
/// 所以本测试不需要 chatSessionRepositoryProvider mock。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/current_novel_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';

/// INovelRepository 最小 fake：只实现 selectNovel → selectCurrentNovel 链路
/// 必需的 getNovelById 与 getNovels。
/// 其他方法抛 UnimplementedError，便于测试发现意外扩散。
class _FakeNovelRepository implements INovelRepository {
  final Map<int, Novel> _byId;

  _FakeNovelRepository(Map<int, Novel> byId) : _byId = byId;

  @override
  Future<Novel?> getNovelById(int id) async => _byId[id];

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

void main() {
  late ProviderContainer container;

  setUp(() {
    final sample = Novel(
      id: 7,
      title: '凡人修仙传',
      author: '忘语',
      url: 'u7',
    );
    final fakeRepo = _FakeNovelRepository({7: sample});
    container = ProviderContainer(overrides: [
      novelRepositoryProvider.overrideWithValue(fakeRepo),
    ]);
    // 切换到默认场景为 writing（与 picker 出现的上下文一致）
    container.read(currentAgentScenarioProvider.notifier).state =
        ScenarioIds.writing;
  });

  tearDown(() {
    container.dispose();
  });

  group('ScenarioSession.selectNovel（picker 写入路径）', () {
    test('selectNovel(novelId) 后 state.currentNovel 等于该书',
        () async {
      final session = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.writing);

      expect(session.state.currentNovel, isNull,
          reason: '冷启动 session 初始 currentNovel 应为空');

      final picked =
          await session.selectNovel(7);

      expect(picked, isNotNull);
      expect(picked!.id, 7);
      expect(picked.title, '凡人修仙传');
      expect(session.state.currentNovel, isNotNull,
          reason: '调用 selectNovel 后 session state 必须携带 currentNovel,'
              '这是 picker 修复的关键契约 —— 否则 header UI 不会刷新');
      expect(session.state.currentNovel!.title, '凡人修仙传');
      expect(session.state.currentNovel!.url, 'u7');

      // 通过 currentChatStateProvider 验证 UI 端可见（这条链路正是 header 渲染依赖的）
      final uiState = container.read(currentChatStateProvider);
      expect(uiState.currentNovel?.title, '凡人修仙传',
          reason: '通过 sessionsProvider 推达 currentChatStateProvider 后,'
              'AgentChatHeader watch 此 provider 必能看到');
    });

    test('selectNovel 不存在的 novelId 返回 null，state.currentNovel 保持 null',
        () async {
      final session = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.writing);

      final result = await session.selectNovel(999);

      expect(result, isNull);
      expect(session.state.currentNovel, isNull,
          reason: 'picker 选中已被删除的小说时不应污染 state');
    });

    test('selectNovel 后 currentNovelProvider（Agent 工具读取入口）也被更新',
        () async {
      // AgentScenarioContext.currentNovelId 读 currentNovelProvider 决定隐式
      // 工具作用目标。picker 路径必须保证全局 provider 同步，否则 LLM 看到
      // 的工具结果与 UI 显示的小说不一致。
      final session = container
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.writing);

      await session.selectNovel(7);

      final global = container.read(currentNovelProvider);
      expect(global, isNotNull,
          reason: 'selectCurrentNovel 内部已写全局 provider');
      expect(global!.id, 7);
      expect(global.title, '凡人修仙传');
    });
  });
}

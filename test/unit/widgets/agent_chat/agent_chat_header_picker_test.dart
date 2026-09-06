/// 端到端回归测试：AgentChatHeader「小说上下文」picker → selectNovel 连线
///
/// 锁定 2026-07-29 修复的 root cause：
/// 修复前 `_showNovelPicker` 用 `showDialog(...)` 后不接收返回值，
/// picker 里 `Navigator.pop(context, n.id)` 返回的 novelId 被丢弃，
/// `ScenarioSession.selectNovel` 从未被调用 → header 永远显示
/// 「尚未选择小说」。
///
/// 本测试用 spy ScenarioSession override `currentSessionProvider`，
/// 真实驱动：点击上下文行 → picker 弹出 → 点击列表项 → 断言
/// `selectNovel(novelId)` 被调用（修复前会失败）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/providers/agent_chat_state.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/current_novel_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_header.dart';

/// INovelRepository 最小 fake：picker 调 getNovels 列出书。
/// selectNovel 在 spy 里被 override，不会真的读 getNovelById。
class _FakeNovelRepository implements INovelRepository {
  final List<Novel> _novels;
  _FakeNovelRepository(this._novels);

  @override
  Future<List<Novel>> getNovels() async => _novels;

  // selectNovel 走 spy，下面方法不会被触碰；保留以满足接口。
  @override
  Future<Novel?> getNovelById(int id) async =>
      _novels.where((n) => n.id == id).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// ScenarioSession spy：记录 selectNovel 调用，并把它反映到 state，
/// 模拟真实 ScenarioSession「selectNovel → state.currentNovel 更新」行为。
class _SpyScenarioSession extends ScenarioSession {
  int? selectNovelCallsArg;

  _SpyScenarioSession({required super.ref})
      : super(scenarioId: ScenarioIds.writing);

  @override
  Future<CurrentNovel?> selectNovel(int novelId) async {
    selectNovelCallsArg = novelId;
    return null; // 返回值不被 header 使用
  }
}

void main() {
  testWidgets('点击上下文行 → picker → 选小说 → 调用 selectNovel(novelId)',
      (tester) async {
    late _SpyScenarioSession spy;

    final novel = Novel(id: 7, title: '凡人修仙传', author: '忘语', url: 'u7');

    final container = ProviderContainer(overrides: [
      novelRepositoryProvider
          .overrideWithValue(_FakeNovelRepository([novel])),
      // 注入 spy session：picker 选定后，header 会经此 provider 调 selectNovel
      currentSessionProvider.overrideWith((ref) {
        spy = _SpyScenarioSession(ref: ref);
        return spy;
      }),
      // 默认场景写作（picker 上下文行在非 webview 场景渲染）
      currentAgentScenarioProvider.overrideWith((ref) => ScenarioIds.writing),
      // 让上下文行初始显示「尚未选择小说」（currentNovel=null）
      currentChatStateProvider.overrideWith((ref) => const AgentChatState(
            scenarioId: ScenarioIds.writing,
            scenarioDisplayName: '小说写作助手',
          )),
    ]);

    addTearDown(container.dispose);

    // 强制建 spy（无论 header 是否最终调过 selectNovel），保证后续断言不因
    // late var 未初始化报错，而是聚焦到「selectNovel 是否被调」的语义断言上。
    container.read(currentSessionProvider);
    expect(spy, isNotNull,
        reason: 'override 回调不跑则 spy 为 null — ProviderContainer 自检');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: AgentChatHeader()),
      ),
    ));
    await tester.pumpAndSettle();

    // 前置：未选小说，上下文行显示占位提示且可点
    expect(find.textContaining('尚未选择小说'), findsOneWidget);

    // 点击上下文行 → 打开 picker
    await tester.tap(find.textContaining('尚未选择小说'));
    await tester.pumpAndSettle();

    // picker 已弹出，列出小说；点击「凡人修仙传」
    expect(find.text('凡人修仙传'), findsOneWidget,
        reason: 'picker 应列出 novelRepository.getNovels() 返回的小说');
    await tester.tap(find.text('凡人修仙传'));
    await tester.pumpAndSettle();

    // ★ root cause 断言：picker 选中后必须把 novelId 传给 selectNovel
    //   修复前此值为 null（showDialog 返回值被丢弃）。
    expect(spy.selectNovelCallsArg, 7,
        reason: '修复前 _showNovelPicker 丢弃了 dialog 返回值,'
            'selectNovel 不会被调用 —— 这里必须拿到 picker 返回的 novelId=7');
  });
}

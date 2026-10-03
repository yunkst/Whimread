/// 文字游戏「重新开始」测试
///
/// 覆盖：restartGame 清空本局剧情消息链（内存 + DB）回到扉页「开始游戏」
/// 前状态；游戏行与设定（世界观/开场/参战名单/玩家角色/世界线）原样保留；
/// 重开后仍能正常开新局。真实链路：TextGamePlayController → ScenarioSession
/// （clearConversation）→ chat_session 表。
///
/// 运行:
///   flutter test test/unit/screens/text_game/text_game_play_restart_test.dart
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/text_game.dart';
import 'package:novel_app/repositories/chat_session_repository.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/repositories/text_game_repository.dart';
import 'package:novel_app/screens/text_game/game_transcript_projector.dart';
import 'package:novel_app/screens/text_game/text_game_play_controller.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';
import 'package:novel_app/utils/cancellation_token.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../helpers/test_database_setup.dart';

/// 最小 AgentService 假件：sendMessage 落一条 TextDelta + Done（与真实
/// 服务的事件收尾路径一致，让会话 isLoading 正常翻转），其余成员不参与本
/// 测试（未用到即抛错，便于发现意外调用）。
class _FakeNovelAgentService implements NovelAgentService {
  final _controller = StreamController<AgentEvent>.broadcast();

  @override
  Ref get ref => throw UnimplementedError();

  @override
  bool get isRunning => false;

  @override
  bool isRunningFor(String scenarioId) => false;

  @override
  CancellationToken? tokenFor(String scenarioId) => null;

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
    // 等一帧让 ScenarioSession 的事件监听先注册上
    await Future<void>.delayed(Duration.zero);
    _controller.add(TextDeltaEvent('旁白：故事开始了。'));
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
    await Future<void>.delayed(Duration.zero);
    _controller.add(const AgentDoneEvent());
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

/// 反复让出事件循环，直到条件满足或超次（fire-and-forget 异步推进用）
Future<void> _pumpUntil(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// clearConversation 的 DB 清理是 fire-and-forget：轮询直到清空（或超时）
Future<bool> _waitDbMessagesEmpty(
    ChatSessionRepository repo, int sessionId) async {
  for (var i = 0; i < 100; i++) {
    if ((await repo.listMessages(sessionId)).isEmpty) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return false;
}

void main() {
  late Database db;
  late ProviderContainer container;
  late TextGameRepository gameRepo;
  late ChatSessionRepository sessionRepo;
  late TextGame game;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
      novelAgentServiceProvider
          .overrideWith((ref) => _FakeNovelAgentService()),
    ]);
    gameRepo = container.read(textGameRepositoryProvider);
    sessionRepo = container.read(chatSessionRepositoryProvider);

    final novelRepo = container.read(novelRepositoryProvider) as NovelRepository;
    await novelRepo.createNovel(
        title: '流云志', author: '佚名', backgroundSetting: '修仙世界，灵气衰竭');
    final novel = (await novelRepo.getNovelByUrl('流云志'))!;
    final charRepo = container.read(characterRepositoryProvider);
    final npcId =
        await charRepo.createCharacter(Character(novelUrl: novel.url, name: '林昭'));
    final playerId =
        await charRepo.createCharacter(Character(novelUrl: novel.url, name: '沈砚'));

    final sessionId = await sessionRepo.createSession(ChatSession(
      scenarioId: ScenarioIds.textGame,
      title: '流云试炼',
    ));
    final id = await gameRepo.create(TextGame(
      title: '流云试炼',
      sourceNovelId: novel.id,
      sourceNovelTitle: '流云志',
      settings: GameSettings(
        worldview: '灵气衰竭的修仙世界',
        opening: '你自沉睡中醒来，身处废弃洞府。',
        characterIds: [npcId],
        playerCharacterId: playerId,
      ),
      chatSessionId: sessionId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    game = (await gameRepo.getById(id))!;
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('restartGame：剧情链清空回扉页，游戏行与设定保留，可再开新局', () async {
    // autoDispose provider：必须挂一个监听者保活，否则 read 后立即被释放
    final provider = textGamePlayControllerProvider(game.id!);
    final keepAlive = container.listen(provider, (_, __) {});
    addTearDown(keepAlive.close);
    final controller = container.read(provider.notifier);
    await _pumpUntil(
        () => !controller.state.initializing && controller.state.game != null);
    expect(controller.state.isEmptyGame, isTrue, reason: '前置：新游戏显示扉页');

    // 开局：用户消息 + 假件回复都进剧情链
    await controller.sendInput('开始游戏');
    await _pumpUntil(() => controller.state.transcript.isNotEmpty);
    expect(controller.state.isEmptyGame, isFalse);
    expect(
      controller.state.transcript.whereType<GamePlayerInput>(),
      isNotEmpty,
      reason: '玩家输入已在定稿链中',
    );
    expect(await sessionRepo.listMessages(game.chatSessionId), isNotEmpty,
        reason: '前置：剧情已落库');

    await controller.restartGame();

    expect(controller.state.isEmptyGame, isTrue,
        reason: '回到「开始游戏」前的扉页状态');
    expect(controller.state.transcript, isEmpty);
    expect(await _waitDbMessagesEmpty(sessionRepo, game.chatSessionId), isTrue,
        reason: 'DB 里的剧情消息链一并清空');

    // 游戏行与设定原样保留（含会话绑定：清的是消息不是会话）
    final fresh = (await gameRepo.getById(game.id!))!;
    expect(fresh.chatSessionId, game.chatSessionId);
    expect(fresh.title, '流云试炼');
    expect(fresh.settings.worldview, '灵气衰竭的修仙世界');
    expect(fresh.settings.opening, '你自沉睡中醒来，身处废弃洞府。');
    expect(fresh.settings.characterIds, game.settings.characterIds);
    expect(fresh.settings.playerCharacterId, game.settings.playerCharacterId);

    // 重开后还能正常开新局
    await controller.sendInput('开始游戏');
    await _pumpUntil(() => controller.state.transcript.isNotEmpty);
    expect(controller.state.isEmptyGame, isFalse, reason: '新一局正常推进');
  });
}

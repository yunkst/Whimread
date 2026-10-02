/// 文字游戏子执行器 — create_text_game / list_text_games / update_text_game
///
/// 创建链路：写作助手场景中用户与 agent 探讨设定 → 确认后由本执行器建两条
/// 记录——chat_sessions 行（scenarioId='text_game'，承载剧情历史）+ text_games
/// 行（游戏侧设定，chatSessionId 关联）。创建后 invalidate textGamesProvider，
/// 管理页（底部「文字游戏」Tab）实时可见。
///
/// 统一模型：游戏必须绑定小说（source_novel_id 必填）以共享角色卡——参战
/// 名单（character_ids）与玩家角色（player_character_id）都是 characters 表
/// 的行 id（先经 create_character 建卡），settings_json 不再快照拷贝角色。
/// 游玩不走本执行器：text_game 场景有自己的回合工具（TextGameScenario）。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/text_game_providers.dart';
import '../../../models/chat_session.dart';
import '../../../models/text_game.dart';
import '../../../services/logger_service.dart';
import '../agent_scenario.dart' show ScenarioIds;
import '../../../core/providers/database_providers.dart'
    show
        characterRepositoryProvider,
        chatSessionRepositoryProvider,
        novelRepositoryProvider,
        textGameRepositoryProvider;

class TextGameExecutor {
  final Ref ref;
  TextGameExecutor(this.ref);

  /// 创建文字游戏（设定必须已与用户确认；必须绑定小说）
  Future<String> createTextGame(Map<String, dynamic> args) async {
    final title = (args['title'] as String?)?.trim() ?? '';
    final worldview = (args['worldview'] as String?)?.trim() ?? '';
    final opening = (args['opening'] as String?)?.trim() ?? '';
    final narrativeStyle = (args['narrativeStyle'] as String?)?.trim() ?? '';
    final contentBoundary = (args['contentBoundary'] as String?)?.trim() ?? '';
    final choicesCountRaw = args['choicesCount'];
    final imagePolicyRaw = args['imagePolicy'] as String?;
    final sourceNovelId = _parseId(args['source_novel_id']);
    final sourceNovelTitle = (args['source_novel_title'] as String?)?.trim();
    final playerCharacterId = _parseId(args['player_character_id']);

    if (title.isEmpty) {
      return _error('missing_title', 'title 不能为空');
    }
    if (sourceNovelId == null) {
      return _error(
          'missing_source_novel',
          'source_novel_id 不能为空。文字游戏必须绑定小说以共享角色卡：'
          '用户指定书架小说（list_novels 查 id），或先用 create_novel 建轻量小说壳。');
    }
    if (opening.isEmpty) {
      return _error('missing_opening', 'opening 不能为空（玩家的开场情境）');
    }

    // 校验小说存在，并取真实标题兜底展示名
    final novelRepo = ref.read(novelRepositoryProvider);
    final novel = await novelRepo.getNovelById(sourceNovelId);
    if (novel == null) {
      return _error('novel_not_found',
          '小说 id=$sourceNovelId 不存在。可先调用 list_novels 查看书架小说，'
          '或用 create_novel 创建。');
    }
    final resolvedNovelUrl = novel.url;

    // 参战名单：characters 表行 id，必须都属于绑定小说
    final characterIds = <int>[];
    if (args['character_ids'] is List) {
      for (final raw in (args['character_ids'] as List)) {
        final id = raw is num ? raw.toInt() : int.tryParse('$raw');
        if (id != null && !characterIds.contains(id)) characterIds.add(id);
      }
    }
    if (characterIds.isEmpty) {
      return _error(
          'missing_characters',
          'character_ids 不能为空。先用 create_character 在该小说下创建角色卡'
          '（含玩家角色），再传入其 characterId。');
    }
    if (playerCharacterId == null) {
      return _error('missing_player_character',
          'player_character_id 不能为空：先用 create_character 创建玩家角色卡，'
          '再传入其 characterId。');
    }

    final charRepo = ref.read(characterRepositoryProvider);
    for (final id in {...characterIds, playerCharacterId}) {
      final card = await charRepo.getCharacter(id);
      if (card == null || card.novelUrl != resolvedNovelUrl) {
        return _error('invalid_character',
            '角色卡 id=$id 不存在或不属于小说「${novel.title}」。'
            '请传该小说下 create_character 返回的 characterId。');
      }
    }
    if (!characterIds.contains(playerCharacterId)) {
      characterIds.add(playerCharacterId);
    }

    final choicesCount = (choicesCountRaw is num ? choicesCountRaw.toInt() : 3)
        .clamp(2, 4);
    final imagePolicy = imagePolicyRaw == 'manual'
        ? GameImagePolicy.manual
        : GameImagePolicy.auto;

    final settings = GameSettings(
      worldview: worldview,
      opening: opening,
      characterIds: characterIds,
      playerCharacterId: playerCharacterId,
      rules: GameRules(
        narrativeStyle: narrativeStyle,
        contentBoundary: contentBoundary,
        choicesCount: choicesCount,
        imagePolicy: imagePolicy,
      ),
    );

    // 同名查重（仅提示不阻断：同名游戏允许覆盖式重建）
    final existing = await ref.read(textGameRepositoryProvider).listAll();
    if (existing.any((g) => g.title == title)) {
      LoggerService.instance.w(
        '创建文字游戏：已存在同名游戏「$title」',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'create_text_game', 'duplicate_title'],
      );
    }

    final sessionRepo = ref.read(chatSessionRepositoryProvider);
    final sessionId = await sessionRepo.createSession(
      ChatSession(scenarioId: ScenarioIds.textGame, title: title),
    );

    final repo = ref.read(textGameRepositoryProvider);
    final int gameId;
    try {
      gameId = await repo.create(TextGame(
        title: title,
        sourceNovelId: sourceNovelId,
        sourceNovelTitle: sourceNovelTitle ?? novel.title,
        settings: settings,
        chatSessionId: sessionId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    } catch (_) {
      // 补偿：游戏行写入失败时删掉刚建的会话，避免遗留孤儿 chat_sessions
      // 行（text_games 无 FK，会话不可见于任何列表，也没有清理路径）
      try {
        await sessionRepo.deleteSession(sessionId);
      } catch (_) {
        // 补偿失败只记日志，不遮蔽原始错误
      }
      rethrow;
    }

    ref.invalidate(textGamesProvider);
    LoggerService.instance.i(
      '创建文字游戏: gameId=$gameId sessionId=$sessionId title=$title '
      'novelId=$sourceNovelId cast=${characterIds.length}',
      category: LogCategory.ai,
      tags: ['agent', 'tool', 'create_text_game', 'success'],
    );

    return jsonEncode({
      'success': true,
      'gameId': gameId,
      'gameTitle': title,
      'message': '游戏「$title」已创建（绑定小说「${novel.title}」，'
          '参战角色 ${characterIds.length} 名）。'
          '请告知用户：到底部「文字游戏」页即可开始游玩。',
    });
  }

  /// 列出已创建的游戏
  Future<String> listTextGames() async {
    final games = await ref.read(textGameRepositoryProvider).listAll();
    return jsonEncode({
      'games': games
          .map((g) => {
                'id': g.id,
                'title': g.title,
                'status': g.status.name,
                'source': 'novel:${g.sourceNovelTitle ?? g.sourceNovelId}',
                'lastPlayedAt': g.lastPlayedAt?.toIso8601String(),
              })
          .toList(),
      'count': games.length,
    });
  }

  /// 修改游戏设定（只传的字段生效；角色卡本身走 create/update_character）
  Future<String> updateTextGame(Map<String, dynamic> args) async {
    final gameId = _parseId(args['game_id']);
    if (gameId == null) {
      return _error('missing_game_id', 'game_id 不能为空');
    }
    final repo = ref.read(textGameRepositoryProvider);
    final game = await repo.getById(gameId);
    if (game == null) {
      return _error('game_not_found',
          '游戏 id=$gameId 不存在，可先调用 list_text_games 查看现有游戏');
    }

    // 参战名单参数解析：增量（add/remove）与整体替换互斥
    final newCastRaw = args['character_ids'];
    final addCastRaw = args['add_character_ids'];
    final removeCastRaw = args['remove_character_ids'];
    final newPlayerId = _parseId(args['player_character_id']);
    final hasReplace = newCastRaw is List;
    final hasIncremental = addCastRaw is List || removeCastRaw is List;
    if (hasReplace && hasIncremental) {
      return _error('conflicting_cast_args',
          'character_ids（整体替换）与 add/remove_character_ids（增量调整）'
          '不能同时传，请二选一');
    }

    // 显式传入的角色 id 先行校验归属（多次 await 的校验窗口与写回分离）
    if (hasReplace || hasIncremental || newPlayerId != null) {
      final involved = <int>{
        ..._parseIdList(newCastRaw),
        ..._parseIdList(addCastRaw),
        if (newPlayerId != null) newPlayerId,
      };
      if (involved.isNotEmpty) {
        final novel = await ref
            .read(novelRepositoryProvider)
            .getNovelById(game.sourceNovelId ?? -1);
        if (novel == null) {
          return _error('novel_not_found', '绑定的小说已不存在，无法校验角色归属');
        }
        final charRepo = ref.read(characterRepositoryProvider);
        for (final id in involved) {
          final card = await charRepo.getCharacter(id);
          if (card == null || card.novelUrl != novel.url) {
            return _error('invalid_character',
                '角色卡 id=$id 不存在或不属于小说「${novel.title}」');
          }
        }
      }
    }

    // 校验通过后再读最新行打 patch：游玩中的并发写入（update_game_state
    // 追加 worldNotes、游戏内 create_character 追加参战名单、touchLastPlayed）
    // 不被旧快照整行覆盖——与场景侧 fresh-read-patch 模式对齐
    final fresh = await repo.getById(gameId);
    if (fresh == null) {
      return _error('game_not_found', '游戏在修改过程中被删除');
    }
    final s = fresh.settings;
    var settings = s.copyWith(
      worldview: (args['worldview'] as String?)?.trim() ?? s.worldview,
      opening: (args['opening'] as String?)?.trim() ?? s.opening,
      rules: GameRules(
        narrativeStyle:
            (args['narrativeStyle'] as String?)?.trim() ?? s.rules.narrativeStyle,
        contentBoundary:
            (args['contentBoundary'] as String?)?.trim() ?? s.rules.contentBoundary,
        choicesCount: args['choicesCount'] is num
            ? (args['choicesCount'] as num).toInt().clamp(2, 4)
            : s.rules.choicesCount,
        imagePolicy: args['imagePolicy'] == 'manual'
            ? GameImagePolicy.manual
            : args['imagePolicy'] == 'auto'
                ? GameImagePolicy.auto
                : s.rules.imagePolicy,
      ),
    );

    if (hasReplace || hasIncremental || newPlayerId != null) {
      List<int> characterIds;
      if (hasReplace) {
        characterIds = _parseIdList(newCastRaw);
      } else if (hasIncremental) {
        characterIds = [...s.characterIds];
        for (final id in _parseIdList(addCastRaw)) {
          if (!characterIds.contains(id)) characterIds.add(id);
        }
        final removedIds = _parseIdList(removeCastRaw);
        characterIds.removeWhere(removedIds.contains);
      } else {
        characterIds = [...s.characterIds];
      }
      final playerId = newPlayerId ?? s.playerCharacterId;
      if (playerId == null) {
        return _error('missing_player_character',
            'player_character_id 不能为空（当前游戏未设置玩家角色）');
      }
      if (!characterIds.contains(playerId)) {
        if (newPlayerId != null) {
          characterIds.add(playerId); // 换玩家角色自动入名单
        } else {
          return _error('player_cannot_be_removed',
              '玩家角色（id=$playerId）不能移出参战名单；'
              '如需更换玩家请传 player_character_id');
        }
      }
      settings = settings.copyWith(
          characterIds: characterIds, playerCharacterId: playerId);
    }

    var updated = fresh;
    if (args['title'] is String && (args['title'] as String).trim().isNotEmpty) {
      updated = updated.copyWith(title: (args['title'] as String).trim());
    }
    updated = updated.copyWith(settings: settings);

    await repo.update(updated);
    ref.invalidate(textGamesProvider);
    return jsonEncode({
      'success': true,
      'message': '游戏「${updated.title}」设定已更新',
    });
  }

  /// 解析 id 列表参数（宽容：数字或数字字符串，去重保序）
  List<int> _parseIdList(Object? raw) => raw is List
      ? raw
          .map((e) => e is num ? e.toInt() : int.tryParse('$e'))
          .whereType<int>()
          .toSet()
          .toList()
      : const [];

  /// 宽容解析单个整数 id（LLM 偶尔把 id 传成 "3" 这类字符串数字，
  /// 原始 `as int?` 强转会抛 TypeError，错误信息是英文原文难以自纠）
  static int? _parseId(Object? raw) =>
      raw is int ? raw : raw is num ? raw.toInt() : int.tryParse('$raw');

  String _error(String code, String message) {
    return jsonEncode({'error': code, 'message': message});
  }
}

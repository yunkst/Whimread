/// 文字游戏子执行器 — create_text_game / list_text_games / update_text_game
///
/// 创建链路：写作助手场景中用户与 agent 探讨设定 → 确认后由本执行器建两条
/// 记录——chat_sessions 行（scenarioId='text_game'，承载剧情历史）+ text_games
/// 行（游戏侧设定，chatSessionId 关联）。创建后 invalidate textGamesProvider，
/// 管理页（底部「文字游戏」Tab）实时可见。
///
/// 统一模型：游戏必须绑定小说（source_novel_id 必填，list_novels 可查）以
/// 共享角色卡。参战名单**缺省 = 绑定小说全部角色卡**（agent 的职责是在
/// 创建前把该小说的主要人物与玩家角色的完整角色卡建好），character_names
/// 仅用于角色过多时圈定子集；角色真实 id 有意不对模型暴露
/// （list_characters 只返回名字），本执行器在绑定小说内把名字解析回行 id。
/// 游玩不走本执行器：text_game 场景有自己的回合工具（TextGameScenario）。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/text_game_providers.dart';
import '../../../models/character.dart';
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
  ///
  /// 绑定小说用 source_novel_id；参战名单缺省 = 绑定小说全部角色卡
  /// （agent 创建前负责把主要人物与玩家角色的完整角色卡建好），
  /// character_names 仅用于显式圈定子集；玩家角色按名字引用且必填。
  Future<String> createTextGame(Map<String, dynamic> args) async {
    final title = (args['title'] as String?)?.trim() ?? '';
    final coreExperience = (args['coreExperience'] as String?)?.trim() ?? '';
    final worldview = (args['worldview'] as String?)?.trim() ?? '';
    final opening = (args['opening'] as String?)?.trim() ?? '';
    final narrativeStyle = (args['narrativeStyle'] as String?)?.trim() ?? '';
    final contentBoundary = (args['contentBoundary'] as String?)?.trim() ?? '';
    final choicesCountRaw = args['choicesCount'];
    final imagePolicyRaw = args['imagePolicy'] as String?;
    final sourceNovelId = _parseId(args['source_novel_id']);
    final playerCharacterName =
        (args['player_character_name'] as String?)?.trim() ?? '';

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
    if (coreExperience.isEmpty) {
      return _error('missing_core_experience',
          'coreExperience 不能为空：先用 ask_user 问清用户想获得什么样的游玩'
          '体验（节奏/爽感来源/描写密度/叙事人称/挫败感），再创建游戏。');
    }

    // 校验小说存在（角色卡解析也限定在这本小说内）
    final novelRepo = ref.read(novelRepositoryProvider);
    final novel = await novelRepo.getNovelById(sourceNovelId);
    if (novel == null) {
      return _error('novel_not_found',
          '小说 id=$sourceNovelId 不存在。可先调用 list_novels 查看书架小说，'
          '或用 create_novel 创建。');
    }

    // 参战名单：缺省 = 绑定小说全部角色卡（agent 创建前应已补齐完整角色卡）；
    // 显式传名字 = 圈定子集（角色过多时聚焦主要角色），名字必须都存在
    final charRepo = ref.read(characterRepositoryProvider);
    final allCards = await charRepo.getCharacters(novel.url);
    final cardByName = <String, Character>{};
    for (final card in allCards) {
      cardByName.putIfAbsent(card.name, () => card);
    }

    final requestedNames = <String>[];
    if (args['character_names'] is List) {
      for (final raw in (args['character_names'] as List)) {
        final name = raw?.toString().trim() ?? '';
        if (name.isNotEmpty && !requestedNames.contains(name)) {
          requestedNames.add(name);
        }
      }
    }

    final characterIds = <int>[];
    if (requestedNames.isNotEmpty) {
      for (final name in requestedNames) {
        final card = cardByName[name];
        if (card?.id == null) {
          return _error('character_not_found',
              '小说「${novel.title}」下不存在名为「$name」的角色卡。'
              '先用 list_characters 核对现有角色名，缺的用 create_character '
              '创建后再引用。');
        }
        if (!characterIds.contains(card!.id)) characterIds.add(card.id!);
      }
    } else {
      for (final card in allCards) {
        if (card.id != null && !characterIds.contains(card.id)) {
          characterIds.add(card.id!);
        }
      }
    }

    if (playerCharacterName.isEmpty) {
      return _error('missing_player_character',
          'player_character_name 不能为空：先 create_character 为该小说创建'
          '玩家角色卡，再按名字引用。');
    }

    final playerCard = cardByName[playerCharacterName];
    if (playerCard?.id == null) {
      return _error('player_character_not_found',
          '小说「${novel.title}」下不存在名为「$playerCharacterName」的玩家'
          '角色卡。先用 create_character 为该小说创建完整角色卡（含玩家角色，'
          '名字须一致），再创建游戏。');
    }
    final playerCharacterId = playerCard!.id!;
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
      coreExperience: coreExperience,
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
        sourceNovelId: novel.id,
        sourceNovelTitle: novel.title,
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
      'novelId=${novel.id} cast=${characterIds.length}',
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

  /// 修改游戏设定（只传的字段生效；角色卡本身走 create/update_character，
  /// 参战名单与玩家角色按角色名引用，在绑定小说内解析为行 id）
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

    // 参战名单参数解析：增量（add/remove）与整体替换互斥，均按角色名引用
    final newCastRaw = args['character_names'];
    final addCastRaw = args['add_character_names'];
    final removeCastRaw = args['remove_character_names'];
    final newPlayerName =
        (args['player_character_name'] as String?)?.trim() ?? '';
    final hasReplace = newCastRaw is List;
    final hasIncremental = addCastRaw is List || removeCastRaw is List;
    if (hasReplace && hasIncremental) {
      return _error('conflicting_cast_args',
          'character_names（整体替换）与 add/remove_character_names（增量调整）'
          '不能同时传，请二选一');
    }

    // 显式传入的角色名先在绑定小说内解析为行 id（多次 await 的校验窗口与
    // 写回分离）；移除名单里的未知名字宽容处理（视为无操作）
    var resolvedNewCast = const <int>[];
    var resolvedAddCast = const <int>[];
    var resolvedRemoveCast = const <int>[];
    int? newPlayerId;
    if (hasReplace || hasIncremental || newPlayerName.isNotEmpty) {
      final novel = await ref
          .read(novelRepositoryProvider)
          .getNovelById(game.sourceNovelId ?? -1);
      if (novel == null) {
        return _error('novel_not_found', '绑定的小说已不存在，无法校验角色归属');
      }
      final cards = await ref
          .read(characterRepositoryProvider)
          .getCharacters(novel.url);
      final cardIdByName = <String, int>{};
      for (final card in cards) {
        if (card.id != null) cardIdByName.putIfAbsent(card.name, () => card.id!);
      }
      for (final name
          in [..._parseNameList(newCastRaw), ..._parseNameList(addCastRaw)]) {
        if (!cardIdByName.containsKey(name)) {
          return _error('character_not_found',
              '小说「${novel.title}」下不存在名为「$name」的角色卡。'
              '先用 list_characters 核对现有角色名，缺的用 create_character '
              '创建。');
        }
      }
      if (newPlayerName.isNotEmpty && !cardIdByName.containsKey(newPlayerName)) {
        return _error('player_character_not_found',
            '小说「${novel.title}」下不存在名为「$newPlayerName」的玩家角色卡。'
            '先 create_character 创建（名字须一致），再引用。');
      }
      resolvedNewCast = _resolveNameIds(newCastRaw, cardIdByName);
      resolvedAddCast = _resolveNameIds(addCastRaw, cardIdByName);
      resolvedRemoveCast = _resolveNameIds(removeCastRaw, cardIdByName);
      if (newPlayerName.isNotEmpty) newPlayerId = cardIdByName[newPlayerName];
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
      coreExperience:
          (args['coreExperience'] as String?)?.trim() ?? s.coreExperience,
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
        characterIds = resolvedNewCast;
      } else if (hasIncremental) {
        characterIds = [...s.characterIds];
        for (final id in resolvedAddCast) {
          if (!characterIds.contains(id)) characterIds.add(id);
        }
        characterIds.removeWhere(resolvedRemoveCast.contains);
      } else {
        characterIds = [...s.characterIds];
      }
      final playerId = newPlayerId ?? s.playerCharacterId;
      if (playerId == null) {
        return _error('missing_player_character',
            'player_character_name 不能为空（当前游戏未设置玩家角色）');
      }
      if (!characterIds.contains(playerId)) {
        if (newPlayerId != null) {
          characterIds.add(playerId); // 换玩家角色自动入名单
        } else {
          return _error('player_cannot_be_removed',
              '玩家角色（id=$playerId）不能移出参战名单；'
              '如需更换玩家请传 player_character_name');
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

  /// 解析角色名列表参数（宽容：非字符串也 toString，空名跳过，去重保序）
  List<String> _parseNameList(Object? raw) => raw is List
      ? raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
      : const [];

  /// 名字 → 行 id（绑定小说内解析；未知名字跳过，配合先行校验使用）
  List<int> _resolveNameIds(Object? raw, Map<String, int> cardIdByName) =>
      _parseNameList(raw)
          .map((name) => cardIdByName[name])
          .whereType<int>()
          .toList();

  /// 宽容解析单个整数 id（LLM 偶尔把 id 传成 "3" 这类字符串数字，
  /// 原始 `as int?` 强转会抛 TypeError，错误信息是英文原文难以自纠）
  static int? _parseId(Object? raw) =>
      raw is int ? raw : raw is num ? raw.toInt() : int.tryParse('$raw');

  String _error(String code, String message) {
    return jsonEncode({'error': code, 'message': message});
  }
}

/// 文字游戏场景
///
/// 一个游戏 = text_game 场景下的一个 chat_session（text_games.chatSessionId
/// 关联），消息链是剧情的真理源。上下文布局（缓存友好）：静态协议在
/// system prompt（[buildSystemPrompt]），设定数据每轮经 factory 重新加载后
/// 由 [buildDynamicContext] 渲染、拼在请求尾部（不落库，改卡/改设定后下一轮
/// 即生效，且不使 prompt cache 前缀失效）。
///
/// 统一模型：游戏必须绑定小说，**角色卡共享小说的 characters 表**——factory
/// 每次运行按参战名单加载角色卡（含玩家角色卡），GM 不再维护拷贝设定：
/// - 台词只能出自参战角色卡；剧情需要新角色时用本场景的 `create_character`
///   建卡（自动加入参战名单，落角色卡版本记录）
/// - `update_game_state` 把重大变化写进角色卡的 currentState（近况演化层，
///   source='text_game'，带原因 → 角色卡版本历史可溯源可回滚）
///
/// 核心体验（settings.coreExperience）：用户想获得的游玩感受（节奏/爽感来源/
/// 描写密度/人称/挫败感），创建时必问、用户可在设定编辑页改。动态块置顶
/// 渲染并在静态协议里声明为**最高准则**——本协议原有的通用节奏默认值
/// （300-600 字/回合）退为"未设定核心体验时"的兜底，否则用户的体验诉求
/// 会被写死的 house style 压过。
///
/// 回合协议（系统提示词中约束 + 工具校验兜底）：
/// - 旁白（环境/时间/动作/神态描写）→ `narrate(text)`；角色台词 →
///   `speak(character, text)`，text 只放直接引语（台词与描写分离，
///   玩家端两种段渲染样式不同）
/// - 回合必以 `present_choices(choices)` 收尾（2-4 项）；它是终止工具
///   （[terminalToolNames]），调用成功 AgentLoop 即结束本回合，不逼 GM 续写
/// - 剧情内容禁止裸文本输出；onNoToolCalls 注入一次协议提醒
///
/// 回合内容**一次性展示**：GM 写作期间玩家只看到进度（运行状态条 + GM
/// 幕后），本回合产出在回合收尾时才进入消息链进入剧情流——因此 GM 写错可
/// 用【后悔重置】（discard_output，loop 层拦截）撤回未展示的草稿重来。
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/database_providers.dart'
    show characterRepositoryProvider, textGameRepositoryProvider;
import 'package:novel_app/core/providers/text_game_providers.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/character_revision.dart'
    show CharacterRevisionSource;
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/models/text_game.dart';
import 'package:novel_app/services/image_generation/image_generation_providers.dart';
import 'package:novel_app/services/logger_service.dart';

import '../agent_scenario.dart';
import 'text_game_prompt.dart';
import 'text_game_tools.dart';

/// 协议提醒标记：nudge 文本前缀。该文本会被 AgentLoop emit 成正文并落库，
/// 游玩页投影器按此前缀过滤，不把协议提醒渲染进剧情流。
const String kGameProtocolNudge = '【协议提醒】';

/// 近况/世界条目单条长度上限（一句话）
const int kGameStateFactMaxLength = 60;

/// 每个记录目标（角色卡/玩家卡/世界与剧情线）的条目数量上限
const int kGameStateMaxEntries = 8;

/// 近况文本 → 条目列表（每行一条；旧的单行散文自然退化为单条目）
List<String> gameStateEntries(String? state) => (state ?? '')
    .split('\n')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// 归一化包含匹配（remove 用）：去空白后相等或互为包含。返回索引，-1 未命中。
int matchStateEntry(List<String> entries, String key) {
  String norm(String s) => s.replaceAll(RegExp(r'\s+'), '');
  final k = norm(key);
  for (var i = 0; i < entries.length; i++) {
    final e = norm(entries[i]);
    if (e == k || e.contains(k) || k.contains(e)) return i;
  }
  return -1;
}

/// 账本应用结果（供工具结果引导 GM 纠偏）
class StateLedgerResult {
  /// 实际划掉的条目原文
  final List<String> removed;

  /// remove 未命中的关键词（原条目已不存在或表述对不上）
  final List<String> unmatched;

  /// 实际新增的条目
  final List<String> added;

  /// 因达到条目数量上限未加入的
  final List<String> overflow;

  const StateLedgerResult({
    required this.removed,
    required this.unmatched,
    required this.added,
    required this.overflow,
  });

  bool get changed => removed.isNotEmpty || added.isNotEmpty;
}

/// 对条目账本就地应用 add/remove：
/// - remove 按包含匹配划掉首个命中条目（GM 引用动态块原文，模糊可容错）
/// - add 精确去重（归一化后相同跳过），达到上限进入 overflow
StateLedgerResult applyStateLedger(
  List<String> entries, {
  required List<String> addFacts,
  required List<String> removeFacts,
}) {
  String norm(String s) => s.replaceAll(RegExp(r'\s+'), '');
  final result = StateLedgerResult(
      removed: [], unmatched: [], added: [], overflow: []);

  for (final key in removeFacts) {
    final idx = matchStateEntry(entries, key);
    if (idx >= 0) {
      result.removed.add(entries[idx]);
      entries.removeAt(idx);
    } else {
      result.unmatched.add(key);
    }
  }
  for (final fact in addFacts) {
    final f = norm(fact);
    if (entries.any((e) => norm(e) == f)) continue; // 已存在，精确去重
    if (entries.length >= kGameStateMaxEntries) {
      result.overflow.add(fact);
      continue;
    }
    entries.add(fact);
    result.added.add(fact);
  }
  return result;
}

/// 概率判定的一个分支（roll_random_event 参数项）
class WeightedEvent {
  /// 结果短标签（GM 据此演出分支）
  final String label;

  /// 相对权重（正数；按总和归一化为概率）
  final double weight;

  const WeightedEvent({required this.label, required this.weight});
}

/// 按权重抽取一个分支（纯函数，便于边界测试）
///
/// [point] 取值域 [0, totalWeight)，逐项累加权重落入首个超过 point 的分支。
WeightedEvent pickWeightedEvent(List<WeightedEvent> events, double point) {
  var acc = 0.0;
  for (final e in events) {
    acc += e.weight;
    if (point < acc) return e;
  }
  return events.last; // 浮点兜底：point 落在区间右端时归最后一项
}

/// 权重归一化为百分比文案（整数不带小数，否则保留 1 位）
String weightedPercent(double weight, double total) {
  if (total <= 0) return '0%';
  final pct = weight / total * 100;
  final s = pct == pct.roundToDouble()
      ? pct.toStringAsFixed(0)
      : pct.toStringAsFixed(1);
  return '$s%';
}

class TextGameScenario with AgentScenarioCleanupMixin implements AgentScenario {
  final Ref _ref;

  /// 概率判定的随机源（测试可注入固定序列）
  final Random _random;

  /// 当前游戏（factory 每次运行按 textGameId 重新加载，设定即时生效）
  final TextGame game;

  /// 绑定的小说（被删除时为 null，动态上下文优雅降级）
  final Novel? novel;

  /// 参战角色卡（characters 表行，含玩家角色卡；factory 按参战名单加载）
  final List<Character> cast;

  /// 玩家角色卡（未设置/名单缺卡时为 null）
  Character? get _playerCard {
    final id = game.settings.playerCharacterId;
    if (id == null) return null;
    for (final c in cast) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 可发言的登场角色（参战名单去掉玩家角色——玩家由用户自己扮演）
  List<Character> get _npcCards => cast
      .where((c) => c.id != game.settings.playerCharacterId)
      .toList();

  TextGameScenario(
    this._ref,
    this.game, {
    required this.novel,
    required this.cast,
    Random? random,
  }) : _random = random ?? Random();

  @override
  String get id => ScenarioIds.textGame;

  @override
  String get displayName => '文字游戏';

  /// present_choices 是交付型终止工具：选项提交给玩家即回合结束。
  /// 不终止的话 AgentLoop 会继续请求下一轮，onNoToolCalls 的协议提醒会
  /// 逼着 GM 把剧情重演一遍（玩家端看到重复内容 + 第二组选项）。
  @override
  Set<String> get terminalToolNames => const {'present_choices'};

  /// 【后悔重置】可撤回的展示类工具：旁白/台词/选项。
  /// 回合内容等 AgentDone 才一次性展示，GM 发现自己写错时可用
  /// discard_output 撤回这些草稿重来——玩家从未看到过。状态类工具
  /// （update_game_state / roll_random_event / create_scene_image）已落库/
  /// 回填，不在可撤集合（撤叙述不撤账本会造成不一致）。
  @override
  Set<String> get retractableToolNames => const {'narrate', 'speak', 'present_choices'};

  @override
  List<Map<String, dynamic>> get tools => [
        narrateToolDefinition,
        speakToolDefinition,
        presentChoicesToolDefinition,
        discardOutputToolDefinition,
        // manual 策略不注入生图工具（工具面硬约束，agent 无法主动调用）；
        // 玩家手动生成走游玩页输入指令。auto 时工具面含 create_scene_image。
        if (game.settings.rules.imagePolicy == GameImagePolicy.auto)
          createSceneImageToolDefinition,
        updateGameStateToolDefinition,
        createGameCharacterToolDefinition,
        rollRandomEventToolDefinition,
      ];

  /// 静态系统提示词：只放 GM 身份与输出协议（整个 run 周期内不变，
  /// 保持请求前缀稳定以命中供应商的 prompt cache）。
  ///
  /// 设定数据（世界观/角色档案/规则）在 [buildDynamicContext]——每轮重新
  /// 生成、拼在请求尾部，改卡或改设定后下一轮即生效，且不会使缓存前缀失效。
  /// 静态系统提示词：五节原则（输出纪律/回合节奏/玩家主权/配套工具/自纠错），
  /// 文本构建在 `text_game_prompt.dart`（协议演进只改那个文件）。
  @override
  String buildSystemPrompt(AgentScenarioContext context) =>
      buildTextGameSystemPrompt(game.title);

  /// 动态设定块：每轮从最新设定渲染，拼在请求尾部（最后一条 user 消息前缀）。
  /// 角色档案/近况来自共享角色卡（factory 运行时加载），改卡后下一轮生效。
  @override
  String buildDynamicContext(AgentScenarioContext context) {
    final s = game.settings;
    final buf = StringBuffer();

    buf.writeln('## 游戏当前状态（每轮刷新，以此为准）');

    // 核心体验置顶：GM 每轮最先读到，压过协议里的通用节奏默认值
    if (s.coreExperience.isNotEmpty) {
      buf.writeln('### 核心体验（演出的最高准则）');
      buf.writeln('玩家想获得的游玩体验如下——回合节奏、描写详略、叙事人称、'
          '选项形态都以此为准，与其它设定冲突时优先服从这里：');
      buf.writeln(s.coreExperience);
    }

    buf.writeln('### 世界观');
    final worldview = s.worldview.isNotEmpty
        ? s.worldview
        : (novel?.backgroundSetting ?? '');
    buf.writeln(worldview.isEmpty ? '（未设定）' : worldview);

    if (s.opening.isNotEmpty) {
      buf.writeln('### 开场情境');
      buf.writeln(s.opening);
    }

    buf.writeln('### 登场角色（只能扮演以下角色）');
    final npcs = _npcCards;
    if (npcs.isEmpty) {
      buf.writeln(novel == null
          ? '（绑定的小说已不存在且名单为空，请以旁白推进剧情）'
          : '（参战名单为空，需要角色时先调用 create_character 创建）');
    } else {
      for (final c in npcs) {
        buf.writeln(_renderCard(c));
      }
    }

    buf.writeln('### 玩家角色（用户扮演：重大抉择归玩家；不影响走向的过场'
        '小动作与简短应答由你在叙述中合理带过，不要事事停下来问）');
    final player = _playerCard;
    if (player == null) {
      buf.writeln('（未设置玩家角色卡）');
    } else {
      final line = StringBuffer('- ${player.name}');
      if (player.occupation?.isNotEmpty == true) {
        line.write('：${player.occupation}');
      }
      if (player.backgroundStory?.isNotEmpty == true) {
        line.write('；来历与目标：${player.backgroundStory}');
      }
      buf.writeln(line);
      _writeFacts(buf, gameStateEntries(player.currentState), label: '当前状态');
    }

    buf.writeln('### 世界与剧情线');
    final worldNotes = game.settings.worldNotes;
    if (worldNotes.isEmpty) {
      buf.writeln('（暂无记录。出现新任务、势力动向或重要悬念时，用 '
          'update_game_state(target="world") 记录）');
    } else {
      for (final n in worldNotes) {
        buf.writeln('· $n');
      }
    }

    buf.writeln('### 规则');
    buf.writeln('- 每回合结束时提交 ${s.rules.choicesCount.clamp(2, 4)} 个选项');
    if (s.rules.narrativeStyle.isNotEmpty) {
      buf.writeln('- 叙事风格：${s.rules.narrativeStyle}');
    }
    if (s.rules.contentBoundary.isNotEmpty) {
      buf.writeln('- 内容边界（必须遵守）：${s.rules.contentBoundary}');
    }
    buf.writeln(
        '- 场景插图：${s.rules.imagePolicy == GameImagePolicy.auto ? '关键场景主动调用 create_scene_image' : '仅当玩家明确要求插图时才调用 create_scene_image，平时不要主动调用'}');
    final boundNovel = novel;
    if (boundNovel != null) {
      buf.writeln('- 本游戏绑定小说《${boundNovel.title}》，忠于其世界观与人物性格');
    }

    // 设定块与玩家输入在同一条 user 消息里（块在前、输入紧随其后），
    // 显式划界避免 GM 把玩家输入当设定数据忽略或误读
    buf.writeln();
    buf.writeln('---');
    buf.writeln('（以上是本轮刷新的设定数据。紧跟本行之后的内容是**玩家本回合'
        '的行动或台词**，不是设定——请据此推进剧情。）');

    return buf.toString();
  }

  /// 渲染一张 NPC 角色卡（动态上下文行 + 近况条目）
  String _renderCard(Character c) {
    final line = StringBuffer('- ${c.name}');
    final profile = <String>[
      if (c.occupation?.isNotEmpty == true) c.occupation!,
      if (c.personality?.isNotEmpty == true) c.personality!,
      if (c.backgroundStory?.isNotEmpty == true) c.backgroundStory!,
    ];
    if (profile.isNotEmpty) line.write('：${profile.join('；')}');
    if (c.speechStyle?.isNotEmpty == true) {
      line.write('（说话风格：${c.speechStyle}）');
    }
    final buf = StringBuffer(line.toString());
    _writeFacts(buf, gameStateEntries(c.currentState), label: '近况');
    return buf.toString();
  }

  /// 把条目列表写为缩进账本（空条目不输出）
  void _writeFacts(StringBuffer buf, List<String> facts,
      {required String label}) {
    if (facts.isEmpty) return;
    buf.write('\n  $label：');
    for (final f in facts) {
      buf.write('\n  · $f');
    }
  }

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    LoggerService.instance.d(
      'TextGameScenario 执行工具: $name (game=${game.id})',
      category: LogCategory.ai,
      tags: ['agent', 'scenario', 'text_game', name],
    );
    switch (name) {
      case 'narrate':
        return _executeNarrate(args);
      case 'speak':
        return _executeSpeak(args);
      case 'present_choices':
        return _executePresentChoices(args);
      case 'create_scene_image':
        // 同步生图：与 create_images 共用统一门面（await 到出图完成）
        final prompt = (args['prompt'] as String?)?.trim() ?? '';
        final aspectRatio = (args['aspect_ratio'] as String?)?.trim();
        final outcome =
            await _ref.read(imageGenerationServiceProvider).generate(
                  prompt: prompt,
                  aspectRatio: aspectRatio,
                );
        if (!outcome.ok) return jsonEncode(outcome.errorJson!);
        return jsonEncode({
          'success': true,
          'message': '场景图已生成。',
          // 与 create_images 结果同构：画廊解析可直接渲染
          'images': outcome.result!.mediaIds
              .map((m) => {
                    'mediaId': m,
                    'prompt': prompt,
                    'modelName': outcome.result!.modelName,
                  })
              .toList(),
          'count': outcome.result!.mediaIds.length,
        });
      case 'update_game_state':
        return await _executeUpdateGameState(args);
      case 'create_character':
        return await _executeCreateCharacter(args);
      case 'roll_random_event':
        return _executeRollEvent(args);
      default:
        return jsonEncode({
          'error': 'unknown_tool',
          'message': '文字游戏场景没有工具 $name',
        });
    }
  }

  Future<String> _executeNarrate(Map<String, dynamic> args) async {
    final text = (args['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      return jsonEncode({
        'error': 'empty_text',
        'message': 'narrate 的 text 不能为空，请重新调用并给出旁白内容',
      });
    }
    return '{"ok":true}';
  }

  Future<String> _executeSpeak(Map<String, dynamic> args) async {
    final character = (args['character'] as String?)?.trim() ?? '';
    final text = (args['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      return jsonEncode({
        'error': 'empty_text',
        'message': 'speak 的 text 不能为空',
      });
    }
    final known = _npcCards.map((c) => c.name).toList();
    if (character.isEmpty) {
      return jsonEncode({
        'error': 'missing_character',
        'message': 'speak 必须传 character（登场角色名或别名）。'
            '可用角色：${known.isEmpty ? "（无，先 create_character）" : known.join('、')}',
      });
    }
    // 别名也算已知角色（角色卡 aliases）
    final nameOrAlias = _npcCards.where((c) =>
        c.name == character ||
        (c.aliases?.contains(character) ?? false)).toList();
    if (nameOrAlias.isEmpty) {
      return jsonEncode({
        'error': 'unknown_character',
        'message': known.isEmpty
            ? '参战名单没有角色。剧情需要角色时先调用 create_character 创建'
            : '未知角色「$character」。登场角色：${known.join('、')}。'
                '新角色请先调用 create_character 创建角色卡。',
        'knownCharacters': known,
      });
    }
    return '{"ok":true}';
  }

  Future<String> _executePresentChoices(Map<String, dynamic> args) async {
    final raw = args['choices'];
    final labels = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final label = (item['label'] as String?)?.trim() ?? '';
          if (label.isNotEmpty) labels.add(label);
        } else if (item is String && item.trim().isNotEmpty) {
          labels.add(item.trim()); // 宽容：LLM 直接给字符串数组
        }
      }
    }
    if (labels.length < 2) {
      return jsonEncode({
        'error': 'too_few_choices',
        'message': 'present_choices 至少需要 2 个选项（当前 ${labels.length} 个），'
            '请重新调用补足 2-4 个',
      });
    }
    if (labels.length > 4) {
      return jsonEncode({
        'error': 'too_many_choices',
        'message': 'present_choices 最多 4 个选项（当前 ${labels.length} 个），'
            '请精简后重新调用',
      });
    }
    return jsonEncode({
      'ok': true,
      'note': '选项已提交给玩家。不要再输出任何内容，等待玩家的选择。',
    });
  }

  /// 协议纠偏：本回合零工具调用时注入一次提醒（防重复标志控制，每次运行最多一次）
  bool _protocolNudged = false;

  /// 状态账本回写：add/remove 条目写入三类目标之一——
  /// 具体角色卡 / 玩家角色卡（省略 character_name）/ 世界与剧情线
  /// （target="world"，写 settings_json.worldNotes，不进版本管理）。
  ///
  /// 角色卡写入基于**最新 DB 卡**（同回合可能已写过一次），只改 currentState
  ///（一行一条），落版本记录 source='text_game'；下一轮 factory 重载后
  /// [buildDynamicContext] 即带上新条目。
  Future<String> _executeUpdateGameState(Map<String, dynamic> args) async {
    final characterName = (args['character_name'] as String?)?.trim() ?? '';
    final targetKind = (args['target'] as String?)?.trim() ?? 'player';
    final reason = (args['reason'] as String?)?.trim();
    final addFacts = _stringListArg(args['add_facts']);
    final removeFacts = _stringListArg(args['remove_facts']);

    if (addFacts.isEmpty && removeFacts.isEmpty) {
      return jsonEncode({
        'error': 'empty_facts',
        'message': 'add_facts 与 remove_facts 至少提供一个（新增/划掉条目）',
      });
    }
    final tooLong = [...addFacts, ...removeFacts]
        .where((f) => f.length > kGameStateFactMaxLength)
        .toList();
    if (tooLong.isNotEmpty) {
      return jsonEncode({
        'error': 'fact_too_long',
        'message': '每条需 $kGameStateFactMaxLength 字以内，超长：${tooLong.join('；')}',
      });
    }

    if (targetKind == 'world') {
      if (characterName.isNotEmpty) {
        return jsonEncode({
          'error': 'conflicting_target',
          'message': 'target="world" 记录世界与剧情线，不针对具体角色，'
              '请去掉 character_name（角色变化就不要传 target）',
        });
      }
      return _updateWorldNotes(addFacts, removeFacts, reason);
    }

    // 目标卡：character_name 优先（名字/别名）；省略 = 玩家角色卡
    final Character? target;
    if (characterName.isEmpty) {
      target = _playerCard;
      if (target == null) {
        return jsonEncode({
          'error': 'no_player_character',
          'message': '本游戏未设置玩家角色卡，无法记录玩家状态；'
              '请带 character_name 记录具体角色，或用 target="world" 记世界线',
        });
      }
    } else {
      final matched = cast.where((c) =>
          c.name == characterName ||
          (c.aliases?.contains(characterName) ?? false)).toList();
      target = matched.isEmpty ? null : matched.first;
      if (target == null) {
        return jsonEncode({
          'error': 'unknown_character',
          'message': '未知角色「$characterName」，参战角色：'
              '${cast.isEmpty ? "（无）" : cast.map((c) => c.name).join("、")}。'
              '新角色请先 create_character 创建',
          'knownCharacters': cast.map((c) => c.name).toList(),
        });
      }
    }

    final cardRepo = _ref.read(characterRepositoryProvider);
    final fresh =
        target.id == null ? null : await cardRepo.getCharacter(target.id!);
    if (fresh == null) {
      return jsonEncode({
        'error': 'character_missing',
        'message': '角色卡「${target.name}」已不存在（可能刚被删除）',
      });
    }

    final entries = gameStateEntries(fresh.currentState);
    final ledger = applyStateLedger(entries,
        addFacts: addFacts, removeFacts: removeFacts);
    if (!ledger.changed) {
      return jsonEncode({
        'ok': true,
        'changed': false,
        'currentFacts': entries,
        'note': _ledgerNote(ledger, '没有产生实际变化'),
      });
    }

    await cardRepo.updateCharacter(
      fresh.copyWith(currentState: entries.join('\n')),
      source: CharacterRevisionSource.textGame,
      sourceRef: '文字游戏《${game.title}》',
      reason: (reason?.isNotEmpty == true) ? reason : '剧情状态回写',
    );

    LoggerService.instance.i(
      '记录游戏状态: gameId=${game.id} target=${fresh.name} '
      'add=${ledger.added.length} remove=${ledger.removed.length}',
      category: LogCategory.ai,
      tags: ['agent', 'scenario', 'text_game', 'update_game_state'],
    );
    return jsonEncode({
      'ok': true,
      'changed': true,
      'added': ledger.added,
      'removed': ledger.removed,
      'unmatched': ledger.unmatched,
      'notAdded': ledger.overflow,
      'currentFacts': entries,
      'note': _ledgerNote(ledger, '状态已记录，下一轮生效。继续当前输出。'),
    });
  }

  /// 世界与剧情线账本：settings_json.worldNotes（游戏侧数据，不进版本管理）
  Future<String> _updateWorldNotes(
    List<String> addFacts,
    List<String> removeFacts,
    String? reason,
  ) async {
    final gameId = game.id;
    if (gameId == null) {
      return jsonEncode({
        'error': 'game_missing',
        'message': '当前游戏未落库，无法记录世界状态',
      });
    }
    final gameRepo = _ref.read(textGameRepositoryProvider);
    final freshGame = await gameRepo.getById(gameId);
    if (freshGame == null) {
      return jsonEncode({
        'error': 'game_missing',
        'message': '游戏已不存在（可能刚被删除）',
      });
    }

    final entries = [...freshGame.settings.worldNotes];
    final ledger = applyStateLedger(entries,
        addFacts: addFacts, removeFacts: removeFacts);
    if (!ledger.changed) {
      return jsonEncode({
        'ok': true,
        'changed': false,
        'currentWorldNotes': entries,
        'note': _ledgerNote(ledger, '没有产生实际变化'),
      });
    }

    await gameRepo.update(
        freshGame.copyWith(settings: freshGame.settings.copyWith(worldNotes: entries)));
    _ref.invalidate(textGamesProvider);
    LoggerService.instance.i(
      '记录世界状态: gameId=$gameId add=${ledger.added.length} '
      'remove=${ledger.removed.length}${reason == null ? "" : " reason=$reason"}',
      category: LogCategory.ai,
      tags: ['agent', 'scenario', 'text_game', 'update_game_state', 'world'],
    );
    return jsonEncode({
      'ok': true,
      'changed': true,
      'added': ledger.added,
      'removed': ledger.removed,
      'unmatched': ledger.unmatched,
      'notAdded': ledger.overflow,
      'currentWorldNotes': entries,
      'note': _ledgerNote(ledger, '世界状态已记录，下一轮生效。继续当前输出。'),
    });
  }

  /// 工具结果 note：账本明细引导（未命中/超限），让 GM 下一轮自我纠偏
  String _ledgerNote(StateLedgerResult ledger, String prefix) {
    final hints = <String>[prefix];
    if (ledger.unmatched.isNotEmpty) {
      hints.add('remove 未命中（已忽略）：${ledger.unmatched.join('；')}');
    }
    if (ledger.overflow.isNotEmpty) {
      hints.add('条目已达 $kGameStateMaxEntries 条上限，未加入：'
          '${ledger.overflow.join('；')}（请先 remove 过期条目）');
    }
    return hints.join('。');
  }

  /// 解析字符串数组参数（宽容：非字符串项转字符串，空项跳过）
  List<String> _stringListArg(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 游戏内建角色卡：剧情引入新角色时，落小说 characters 表（版本记录
  /// source='text_game'）并自动加入游戏参战名单。
  Future<String> _executeCreateCharacter(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    final novelRef = novel;
    if (novelRef == null) {
      return jsonEncode({
        'error': 'novel_missing',
        'message': '绑定的小说已不存在，无法创建角色卡',
      });
    }
    if (name.isEmpty) {
      return jsonEncode({
        'error': 'missing_name',
        'message': 'name 不能为空',
      });
    }

    final cardRepo = _ref.read(characterRepositoryProvider);
    final gameRepo = _ref.read(textGameRepositoryProvider);
    final reason = (args['reason'] as String?)?.trim();

    // 同名卡已存在 → 不重建，直接加入参战名单
    final existing =
        await cardRepo.findCharacterByName(novelRef.url, name);
    Character? card;
    if (existing != null) {
      card = existing;
    } else {
      final id = await cardRepo.createCharacter(
        Character(
          novelUrl: novelRef.url,
          name: name,
          occupation: (args['identity'] as String?)?.trim(),
          personality: (args['personality'] as String?)?.trim(),
          appearanceFeatures: (args['appearance'] as String?)?.trim(),
          backgroundStory: (args['background'] as String?)?.trim(),
          speechStyle: (args['speech_style'] as String?)?.trim(),
        ),
        source: CharacterRevisionSource.textGame,
        sourceRef: '文字游戏《${game.title}》',
        reason: (reason?.isNotEmpty == true) ? reason : '剧情引入新角色',
      );
      card = await cardRepo.getCharacter(id);
      if (card == null) {
        return jsonEncode({
          'error': 'create_failed',
          'message': '角色卡创建失败，请重试',
        });
      }
    }

    // 加入参战名单（基于最新游戏行 patch，避免覆盖同回合其他变更）
    final gameId = game.id;
    if (gameId != null) {
      final freshGame = await gameRepo.getById(gameId);
      if (freshGame != null &&
          !freshGame.settings.characterIds.contains(card.id)) {
        await gameRepo.update(
          freshGame.copyWith(
              settings: freshGame.settings.withCharacter(card.id!)),
        );
        _ref.invalidate(textGamesProvider);
      }
    }

    // 同步内存 cast：本轮后续 speak/update_game_state 按 _npcCards（cast
    // 派生）校验，工具返回 note 已承诺"可用 speak 让其说话"——cast 是
    // 构造时加载的固定列表，不同步会让本回合的 speak 立即收到
    // unknown_character，GM 陷入"重建→再 speak→再被拒"的循环
    // （cardId 提到闭包外：card 是可空局部变量，闭包内不做类型提升）
    final cardId = card.id;
    if (cardId != null && !cast.any((c) => c.id == cardId)) {
      cast.add(card);
    }

    LoggerService.instance.i(
      '游戏内创建角色卡: game=${game.id} name=${card.name} id=${card.id}'
      '${existing != null ? "（复用已有卡）" : ""}',
      category: LogCategory.ai,
      tags: ['agent', 'scenario', 'text_game', 'create_character'],
    );
    return jsonEncode({
      'ok': true,
      'characterId': card.id,
      'name': card.name,
      'note': existing != null
          ? '「${card.name}」已有角色卡，已加入参战名单，可直接用 speak 让其说话。'
          : '角色卡「${card.name}」已创建并加入参战名单，可用 speak 让其说话。',
    });
  }

  /// 概率判定：按权重随机抽取一个分支作为既定事实返回。
  ///
  /// 参数校验从严（错误信息引导 GM 自纠）：分支 2-6 个、label 非空、
  /// weight 为正数（宽容解析字符串数字，缺省 1）。结果即锁定——note 明示
  /// 不得改写/重判，日志留档每次判定的分支与权重供回溯。
  Future<String> _executeRollEvent(Map<String, dynamic> args) async {
    final reason = (args['reason'] as String?)?.trim() ?? '';
    final raw = args['events'];
    if (raw is! List || raw.isEmpty) {
      return jsonEncode({
        'error': 'missing_events',
        'message': 'events 不能为空：列出全部分支（2-6 个，含失败/意外分支）'
            '与相对权重后再调用',
      });
    }
    final events = <WeightedEvent>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      final label = (item is Map ? item['label'] : item)?.toString().trim() ?? '';
      if (label.isEmpty) {
        return jsonEncode({
          'error': 'invalid_event',
          'message': '第 ${i + 1} 个分支缺少 label，请补全每个分支的结果标签'
              '（如「战斗胜利」）后重新调用',
        });
      }
      final rawWeight = item is Map ? item['weight'] : null;
      final weight = rawWeight == null
          ? 1.0
          : rawWeight is num
              ? rawWeight.toDouble()
              : double.tryParse('$rawWeight');
      if (weight == null || weight <= 0) {
        return jsonEncode({
          'error': 'invalid_weight',
          'message': '分支「$label」的 weight 必须是正数（相对权重，如 70 与 30 '
              '表示七三开），省略视为 1',
        });
      }
      events.add(WeightedEvent(label: label, weight: weight));
    }
    if (events.length < 2) {
      return jsonEncode({
        'error': 'too_few_events',
        'message': '至少 2 个分支才有随机意义（当前 ${events.length} 个）。'
            '请把失败/意外分支也列入 events，如 胜利(70) + 失败(30)',
      });
    }
    if (events.length > 6) {
      return jsonEncode({
        'error': 'too_many_events',
        'message': '最多 6 个分支（当前 ${events.length} 个），请合并同类结果',
      });
    }

    final total = events.fold<double>(0, (s, e) => s + e.weight);
    final picked = pickWeightedEvent(events, _random.nextDouble() * total);

    LoggerService.instance.i(
      '概率判定: game=${game.id}'
      '${reason.isEmpty ? "" : " reason=$reason"} '
      'branches=${events.map((e) => "${e.label}:${e.weight}").join("/")} '
      '→ ${picked.label}',
      category: LogCategory.ai,
      tags: ['agent', 'scenario', 'text_game', 'roll_random_event'],
    );
    return jsonEncode({
      'ok': true,
      'selected': picked.label,
      'selectedPercent': weightedPercent(picked.weight, total),
      'branches': [
        for (final e in events)
          {'label': e.label, 'weight': e.weight, 'percent': weightedPercent(e.weight, total)},
      ],
      'note': '随机判定完成：本回合剧情必须按「${picked.label}」推进，'
          '不得改写，也不要重复判定换结果。请用 narrate/speak 演出该结果，'
          '最后仍需 present_choices 收尾。',
    });
  }

  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async {
    if (_protocolNudged) return null;
    _protocolNudged = true;
    return '$kGameProtocolNudge 本回合没有调用任何工具，直接输出的正文玩家看不到'
        '（剧情必须经工具渲染）。请把刚才的内容改用工具重新输出：旁白用 '
        'narrate，台词用 speak，并以 present_choices 结束回合。';
  }

  /// 文字游戏无经验记忆闭环（implements 语义下需显式给出实现）
  @override
  Future<List<String>> getMemories() async => const [];

  @override
  Future<MemoryPatchResult> patchMemory(int? index, String newText) async {
    return MemoryPatchResult.error('patch_memory 在文字游戏场景不可用', const []);
  }
}

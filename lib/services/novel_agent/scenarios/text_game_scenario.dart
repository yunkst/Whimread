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
/// narrate/speak 在 [streamableToolNames] 白名单中：AgentLoop 把参数流式
/// 过程透传为 ToolArgDeltaEvent，游玩页据此做打字机渲染。
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

  @override
  Set<String> get streamableToolNames => const {'narrate', 'speak'};

  /// present_choices 是交付型终止工具：选项提交给玩家即回合结束。
  /// 不终止的话 AgentLoop 会继续请求下一轮，onNoToolCalls 的协议提醒会
  /// 逼着 GM 把剧情重演一遍（玩家端看到重复内容 + 第二组选项）。
  @override
  Set<String> get terminalToolNames => const {'present_choices'};

  @override
  List<Map<String, dynamic>> get tools => [
        narrateToolDefinition,
        speakToolDefinition,
        presentChoicesToolDefinition,
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
  @override
  String buildSystemPrompt(AgentScenarioContext context) {
    final buf = StringBuffer();

    buf.writeln('你是文字游戏「${game.title}」的游戏主持人（GM）。'
        '你负责描写世界、扮演登场角色、推动剧情，并在每个回合结束时把'
        '剧情的走向交给玩家决定。玩家来玩是为了获得他想要的体验——'
        '设定中的「核心体验」是演出的最高准则：回合节奏、描写详略、'
        '叙事人称、选项形态都以它为准，与其它设定或本协议的通用规则'
        '冲突时，以核心体验为准。');

    buf.writeln();
    buf.writeln('## 游戏设定在哪');
    buf.writeln('完整的游戏设定（核心体验、世界观、开场、登场角色档案与近况、'
        '玩家角色当前状态、规则）在每轮对话末尾的「游戏当前状态」块中，'
        '**以它为准**：角色该是什么样、关系如何、实力几何，都依该块演出；'
        '更早轮次里可能已过时的描述不要沿用。');

    buf.writeln();
    buf.writeln('## 输出协议（必须严格遵守）');
    buf.writeln('1. 所有剧情内容必须通过工具输出，且台词与描写严格分离：'
        '旁白（环境、时间过渡、角色的动作/神态/心理等第三人称描写）用 '
        'narrate(text=...)；角色台词用 speak(character=..., text=...)，'
        'text 只写角色说的话本身（含必要的语气词/称呼），不要把动作神态'
        '塞进台词。禁止不调用工具直接输出正文。');
    buf.writeln('2. text 参数放在所有参数的最后输出（利于玩家端流式渲染）。');
    buf.writeln('3. 每段旁白、每句台词单独调用一次工具；一回合可连续调用多次。');
    buf.writeln('4. 单回合节奏与篇幅以「游戏当前状态」块中的核心体验为准'
        '（快节奏就短平快直给，慢热沉浸就把铺陈写足，人称视角同样服从它）；'
        '未设定核心体验时按通用节奏：1-3 段旁白 + 适量台词，总长 300-600 字，'
        '不要拖沓。');
    buf.writeln('5. 回合收尾：内容输出完后，必须调用 '
        'present_choices(choices=[{label, hint}...]) 提交选项，然后立即停止，'
        '等待玩家选择或自由输入。选项数量以「游戏当前状态」块中的规则为准；'
        '选项的形态贴合核心体验（战斗向给行动抉择，角色互动向可以是'
        '「说什么/怎么回应」，解谜向给推理路线）。');
    buf.writeln('6. 状态记录：当角色/玩家发生**重大且持久**的变化（致残、'
        '突破等级、获得或失去关键物品、立场关系质变），或世界出现新任务/'
        '势力动向/重要悬念时，调用 update_game_state：变化用 add_facts 新增'
        '条目，不再成立的旧条目用 remove_facts 引用「游戏当前状态」块中的'
        '原文划掉；任务与剧情线用 target="world"。每条一句话。'
        '正例：突破魂力三十级 / 获得玄重尺 / 与戴沐白结拜；反例：战斗掉血'
        '未倒下、临时情绪波动——不要记录。');
    buf.writeln('7. 新角色出场：剧情需要新角色时，先调用 create_character '
        '创建角色卡（自动加入参战名单并记录版本），再用 speak 让其说话。'
        '不要凭空扮演「游戏当前状态」块之外的已有角色。');
    buf.writeln('8. 场景插图：按「游戏当前状态」块中的插图策略执行。'
        'create_scene_image 是同步的：调用后会阻塞到图片生成完成（数十秒），'
        '返回即已拿到图片，不要重复调用同一场景。'
        'prompt 用英文外貌/构图描述'
        '（可参考角色 facePrompts/bodyPrompts/appearanceFeatures）。');
    buf.writeln('9. 概率判定：剧情出现不确定性分岔（战斗能否获胜、行动能否成功、'
        '机关是否触发、随机遭遇等）时，调用 roll_random_event：events 列出'
        '全部分支（含失败/意外分支）与相对权重，随机结果返回后即为既定事实——'
        '必须照此推进剧情，不得改写或重复判定，然后用 narrate/speak 演出结果。'
        '确定性剧情不要滥用判定。');

    return buf.toString();
  }

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

    buf.writeln('### 玩家角色（用户扮演，不要代其行动/说话）');
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

// ===== 工具定义（OpenAI Function Calling schema）=====

const Map<String, dynamic> narrateToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'narrate',
    'description':
        '输出一段旁白：环境描写、时间过渡、剧情推进，以及角色的动作、'
        '神态、心理等第三人称描写。每段旁白单独调用一次；一回合可多次调用。',
    'parameters': {
      'type': 'object',
      'properties': {
        'text': {
          'type': 'string',
          'description': '旁白正文（放在最后一个参数输出）',
        },
      },
      'required': ['text'],
    },
  },
};

const Map<String, dynamic> speakToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'speak',
    'description':
        '输出一位登场角色的台词。text 只放角色说的话本身（直接引语，'
        '可含语气词/称呼）；该角色的动作、神态、心理描写一律改用 narrate '
        '单独输出，不要混进台词。character 必须是登场角色之一；'
        '每句台词单独调用一次。',
    'parameters': {
      'type': 'object',
      'properties': {
        'character': {
          'type': 'string',
          'description': '说话的角色名（必须在登场角色列表中）',
        },
        'text': {
          'type': 'string',
          'description': '台词正文（放在最后一个参数输出）',
        },
      },
      'required': ['character', 'text'],
    },
  },
};

const Map<String, dynamic> presentChoicesToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'present_choices',
    'description':
        '结束本回合：给玩家提交 2-4 个剧情走向/行动选项。'
        '必须在输出完旁白与台词之后、作为本回合最后一个工具调用；'
        '调用后不要再输出任何内容，等待玩家选择或自由输入。',
    'parameters': {
      'type': 'object',
      'properties': {
        'choices': {
          'type': 'array',
          'description': '2-4 个选项',
          'items': {
            'type': 'object',
            'properties': {
              'label': {
                'type': 'string',
                'description': '选项短标签（行动或走向，16 字以内）',
              },
              'hint': {
                'type': 'string',
                'description': '可选补充说明（后果/风险提示，30 字以内）',
              },
            },
            'required': ['label'],
          },
        },
      },
      'required': ['choices'],
    },
  },
};

/// 场景生图工具（仅 imagePolicy == auto 时注入工具面）
const Map<String, dynamic> createSceneImageToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'create_scene_image',
    'description':
        '为当前关键场景生成一幅插图（异步：提交后立即继续输出剧情，'
        '不要等待，不要向玩家提及生成进度；图完成后会自动插入剧情）。'
        '仅在关键场景调用：新地点、重要角色登场、高潮时刻等，不要每回合都调用。',
    'parameters': {
      'type': 'object',
      'properties': {
        'prompt': {
          'type': 'string',
          'description':
              '画面描述提示词（英文效果更佳）：场景 + 角色外貌（可参考角色卡'
              ' facePrompts/appearanceFeatures）+ 构图/光影风格。不要包含文字、水印要求。',
        },
        'aspect_ratio': {
          'type': 'string',
          'description': '可选画面比例（如 3:4 / 16:9），仅部分模型生效',
        },
      },
      'required': ['prompt'],
    },
  },
};

/// 状态账本工具：add/remove 条目，目标为具体角色卡 / 玩家卡 / 世界与剧情线
const Map<String, dynamic> updateGameStateToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'update_game_state',
    'description':
        '把重大且持久的变化记录为状态条目（下一轮生效，长期不会遗忘；角色'
        '变化会记入角色卡版本历史）。记录对象三选一：具体角色（传 '
        'character_name）、玩家角色（省略 character_name 与 target）、'
        '世界与剧情线（target="world"：任务/势力动向/未解悬念）。\n'
        '何时记录：致残、突破等级、获得或失去关键物品、立场关系质变、'
        '新任务与主线动向。何时不记录：战斗掉血未倒下、临时情绪波动等'
        '日常琐事。\n'
        '条目一句话（60 字以内）；不再成立的旧条目用 remove_facts 引用'
        '原文划掉。',
    'parameters': {
      'type': 'object',
      'properties': {
        'character_name': {
          'type': 'string',
          'description':
              '要记录的登场角色名（参战名单中，可为别名）。'
              '省略且 target 非 world 时 = 记录玩家角色',
        },
        'target': {
          'type': 'string',
          'enum': ['player', 'world'],
          'description':
              '记录目标：player=玩家角色（默认）；world=世界与剧情线。'
              '传了 character_name 时按角色处理',
        },
        'add_facts': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '新增条目列表（每条一句话，60 字以内）',
        },
        'remove_facts': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              '要划掉的既有条目（引用「游戏当前状态」块中的原文或其关键片段）',
        },
        'reason': {
          'type': 'string',
          'description': '发生变化的一句话原因（如「击败风笑天，获得玄重尺」），'
              '记入版本历史便于回溯',
        },
      },
    },
  },
};

/// 概率判定工具：多分支事件按相对权重随机抽取一个结果
const Map<String, dynamic> rollRandomEventToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'roll_random_event',
    'description':
        '概率判定：对剧情中的不确定性分岔（战斗能否获胜、行动能否成功、'
        '机关是否触发、随机遭遇等）按权重随机抽取一个结果。\n'
        'events 列出全部分支（含失败/意外分支）与相对权重，系统归一化后'
        '抽取一个分支返回。weight 只需相对比例正确，不必加总为 100'
        '（如 70 与 30 即七三开）。\n'
        '⚠️ 结果返回后即为既定事实：必须照此推进剧情，不得改写，也不要'
        '重复调用试图换结果。确定性剧情不要调用本工具。',
    'parameters': {
      'type': 'object',
      'properties': {
        'events': {
          'type': 'array',
          'description': '所有可能分支（2-6 个，必须包含失败/意外分支）。'
              'weight 为相对权重（正数，省略视为 1 即等概率）',
          'items': {
            'type': 'object',
            'properties': {
              'label': {
                'type': 'string',
                'description': '分支结果短标签（如「战斗胜利」「机关触发」）',
              },
              'weight': {
                'type': 'number',
                'description': '相对权重（正数，如 70 与 30 表示七三开）',
              },
            },
            'required': ['label'],
          },
        },
        'reason': {
          'type': 'string',
          'description': '一句话说明为什么判定（如「主角强闯山门禁制」），'
              '记入日志便于回溯',
        },
      },
      'required': ['events'],
    },
  },
};

/// 游戏内建角色卡工具：剧情引入新角色时创建（自动加入参战名单）
const Map<String, dynamic> createGameCharacterToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'create_character',
    'description':
        '为剧情引入一位新角色：创建角色卡并自动加入本游戏参战名单'
        '（会记入角色卡版本历史）。创建后即可用 speak 让其说话。'
        '仅在新角色有持续戏份时创建；一次性路人在旁白中带过即可。',
    'parameters': {
      'type': 'object',
      'properties': {
        'name': {
          'type': 'string',
          'description': '角色名',
        },
        'identity': {
          'type': 'string',
          'description': '身份/职业（如「铁匠」「史莱克学院学员」）',
        },
        'personality': {
          'type': 'string',
          'description': '性格特点',
        },
        'appearance': {
          'type': 'string',
          'description': '外貌特征',
        },
        'background': {
          'type': 'string',
          'description': '背景来历',
        },
        'speech_style': {
          'type': 'string',
          'description': '说话风格（口吻/口头禅，保持扮演一致性）',
        },
        'reason': {
          'type': 'string',
          'description': '登场原因（如「剧情第3回合新登场的铁匠」），记入版本历史',
        },
      },
      'required': ['name'],
    },
  },
};

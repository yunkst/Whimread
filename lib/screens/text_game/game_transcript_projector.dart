/// 游戏剧情投影器：Agent 消息链 → 游玩页渲染段
///
/// 消息链是真理源：投影是纯函数，输入 AgentChatMessage 列表（ScenarioSession
/// 的 UI 投影），输出游玩页自己的 [GameSegment] 列表。重放（hydrate 后）与
/// 定稿（回合 finalize 后）走同一投影，保证「玩家看到的 = 消息链里的」。
///
/// 回合协议到渲染的映射：
/// - user → [GamePlayerInput]（协议提醒/图片占位等系统文本跳过）
/// - assistant TextSegment → [GameNarration]（旁白兜底）
/// - narrate 工具调用 → [GameNarration]
/// - speak 工具调用 → [GameDialogue]
/// - create_scene_image 工具调用 → [GameSceneImage]（媒体从 tool result 解析）
/// - roll_random_event 工具调用 → [GameDiceRoll]（分支/选中从参数与 result 解析）
/// - present_choices 工具调用 → [GameChoices]
///
/// 失败调用不进剧情流：narrate/speak 若以失败告终（[isFailedToolCall]，如
/// speak 的 unknown_character / missing_character），该次尝试视为"没演成"，
/// GM 会按纠错提示重调——只渲染重调成功的那次，否则同一句台词会显示两遍
/// （现场日志：speak 失败 → create_character → 同文重调成功）。插图与骰子
/// 例外：它们的失败态本身是信息（错误卡/判定失败），照常渲染。直播打字机
/// 侧同一语义由 [dropFailedStoryStreamingPart] 保证，不必等回合结束才自愈。
///
/// 选项活性：只有「最后一条」GameChoices 是可点的（active），其后出现玩家
/// 输入则转为历史；若玩家输入与某选项 label 精确一致，该选项标记 chosen。
/// 历史选项组带 rollbackUiIndex 锚点（其后那条玩家输入的位置），供游玩页
/// 实现「回溯到这一步重新选择」。
///
/// 回合关闭截断：每回合（最后一条玩家输入之后）首个 present_choices 即回合
/// 终点，其后同回合的旁白/台词/插图/判定/重复选项一律不渲染——GM 在选项
/// 之后被续跑钩子逼出的重复内容（用户反馈 #10）不进剧情流，历史脏数据
/// 重放时同样自愈。
library;

import 'dart:convert';

import '../../models/agent_chat_message.dart';
import '../../services/novel_agent/agent_event.dart'
    show AgentToolCall, AgentToolStatus, ToolCallEndEvent;
import '../../services/novel_agent/scenarios/text_game_scenario.dart'
    show kGameProtocolNudge, weightedPercent;

/// 一个选项
class GameChoice {
  final String label;
  final String? hint;

  const GameChoice({required this.label, this.hint});
}

/// 游玩页渲染段（sealed）
sealed class GameSegment {
  const GameSegment();
}

/// 旁白（含 narrate 工具输出与 assistant 裸文本兜底）
class GameNarration extends GameSegment {
  final String text;
  const GameNarration(this.text);
}

/// 角色台词
class GameDialogue extends GameSegment {
  final String character;
  final String text;

  /// 角色头像 mediaId（共享角色卡 avatarMediaId；null = 无头像，只渲染彩色名）
  final String? avatarMediaId;

  const GameDialogue({
    required this.character,
    required this.text,
    this.avatarMediaId,
  });
}

/// 场景插图（异步生图：媒体/状态从 tool result 或任务表解析）
class GameSceneImage extends GameSegment {
  final String toolCallId;
  final String prompt;

  /// 工具结果 JSON（completed 态才有；成功含 images[].mediaId，
  /// 失败含 error。运行中/重启后丢失任务态时用它兜底渲染）
  final String? toolResultJson;

  /// 工具是否已结束（false = 仍在本回合运行中）
  final bool toolCompleted;

  const GameSceneImage({
    required this.toolCallId,
    required this.prompt,
    this.toolResultJson,
    this.toolCompleted = true,
  });
}

/// 概率判定的一个分支（展示用：标签 + 权重 + 归一化百分比）
class GameRollBranch {
  final String label;
  final double weight;

  /// 权重归一化后的百分比文案（如 "70%"）
  final String percent;

  const GameRollBranch({
    required this.label,
    required this.weight,
    required this.percent,
  });
}

/// 概率判定段（roll_random_event 工具调用 → 命运骰子卡）
///
/// 判定是同步工具（调用即出结果）：result 已出时 [selectedLabel] 非空；
/// [toolCompleted] false = 本回合仍在判定（live 轮转动画）；
/// [live] false = 定稿链里的未完成判定（回合中断残留，静态降级展示）。
class GameDiceRoll extends GameSegment {
  final String toolCallId;
  final String reason;
  final List<GameRollBranch> branches;

  /// 抽中的分支标签（null = 运行中未定 / 判定失败）
  final String? selectedLabel;

  /// 判定失败信息（工具返回 error）
  final String? error;

  /// 工具是否已结束
  final bool toolCompleted;

  /// 是否处于运行中的回合（pending 投影 true；定稿链 false）
  final bool live;

  const GameDiceRoll({
    required this.toolCallId,
    required this.reason,
    required this.branches,
    this.selectedLabel,
    this.error,
    this.toolCompleted = true,
    this.live = false,
  });

  /// 选中分支的百分比文案（未定/失败为 null）
  String? get selectedPercent {
    for (final b in branches) {
      if (b.label == selectedLabel) return b.percent;
    }
    return null;
  }
}

/// 回合选项
class GameChoices extends GameSegment {
  final List<GameChoice> choices;

  /// 是否可点（最后一条 + agent 空闲）
  final bool active;

  /// 玩家已选的选项 label（与后续输入精确一致时标记）
  final String? chosenLabel;

  /// 回溯锚点：其后使本选项组历史化的那条玩家输入在消息链（UI 列表）中的
  /// 索引。回溯 = 删除该输入及其后全部剧情，本选项组恢复为当前可选项。
  /// null = 无锚点（当前活动选项 / 运行中预览），不可回溯。
  final int? rollbackUiIndex;

  /// 来源 present_choices 工具调用的 id（入场动画只播一次的记账键；
  /// 运行中预览/测试构造可能为 null）
  final String? toolCallId;

  const GameChoices({
    required this.choices,
    required this.active,
    this.chosenLabel,
    this.rollbackUiIndex,
    this.toolCallId,
  });
}

/// 玩家输入
class GamePlayerInput extends GameSegment {
  final String text;
  const GamePlayerInput(this.text);
}

/// 运行中的流式片段（ToolArgDeltaEvent 驱动的打字机内容，未定稿）
class GameStreamingPart {
  final String toolCallId;
  final String name; // narrate | speak
  final String text;
  final String? character;

  const GameStreamingPart({
    required this.toolCallId,
    required this.name,
    required this.text,
    this.character,
  });
}

/// 从工具调用参数解析选项列表（宽容：缺 label 的项跳过）
List<GameChoice> parseGameChoices(Object? raw) {
  final result = <GameChoice>[];
  if (raw is! List) return result;
  for (final item in raw) {
    if (item is Map) {
      final label = (item['label'] as String?)?.trim() ?? '';
      if (label.isEmpty) continue;
      result.add(GameChoice(
        label: label,
        hint: (item['hint'] as String?)?.trim(),
      ));
    } else if (item is String && item.trim().isNotEmpty) {
      result.add(GameChoice(label: item.trim()));
    }
  }
  return result;
}

/// 解析 create_scene_image 工具结果里的 mediaIds（成功态）
List<String> parseSceneImageMediaIds(String? toolResultJson) {
  if (toolResultJson == null || toolResultJson.isEmpty) return const [];
  try {
    final decoded = jsonDecode(toolResultJson);
    if (decoded is Map<String, dynamic> &&
        decoded['success'] == true &&
        decoded['images'] is List) {
      return (decoded['images'] as List)
          .whereType<Map>()
          .map((m) => m['mediaId']?.toString() ?? '')
          .where((m) => m.isNotEmpty)
          .toList();
    }
  } catch (_) {
    // 坏数据按无图处理
  }
  return const [];
}

/// 解析 create_scene_image 工具结果里的错误信息（失败态）
String? parseSceneImageError(String? toolResultJson) {
  if (toolResultJson == null || toolResultJson.isEmpty) return null;
  try {
    final decoded = jsonDecode(toolResultJson);
    if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
      return decoded['message']?.toString() ?? '插图生成失败';
    }
  } catch (_) {}
  return null;
}

/// 解析 roll_random_event 参数里的分支列表（宽容：缺 label 跳过，
/// 非法权重按 1 计），权重归一化为百分比文案
List<GameRollBranch> parseRollBranches(Object? raw) {
  if (raw is! List) return const [];
  final parsed = <(String, double)>[];
  for (final item in raw) {
    final label =
        (item is Map ? item['label'] : item)?.toString().trim() ?? '';
    if (label.isEmpty) continue;
    final rawWeight = item is Map ? item['weight'] : null;
    final weight = rawWeight == null
        ? 1.0
        : rawWeight is num
            ? rawWeight.toDouble()
            : double.tryParse('$rawWeight');
    parsed.add((label, weight != null && weight > 0 ? weight : 1.0));
  }
  if (parsed.isEmpty) return const [];
  final total = parsed.fold<double>(0, (s, e) => s + e.$2);
  return [
    for (final (label, weight) in parsed)
      GameRollBranch(
        label: label,
        weight: weight,
        percent: weightedPercent(weight, total),
      ),
  ];
}

/// 构造概率判定段（定稿投影与运行中 pending 投影共用）
///
/// [completed] 工具是否已结束；[resultJson] 工具结果（未结束传 null）。
/// [live] true = 运行中回合（轮转动画），false = 定稿链（静态展示）。
GameDiceRoll rollDiceRollSegment(
  String toolCallId,
  Map<String, dynamic> arguments, {
  required bool completed,
  String? resultJson,
  bool live = false,
}) {
  final parsed = parseRollResult(completed ? resultJson : null);
  return GameDiceRoll(
    toolCallId: toolCallId,
    reason: arguments['reason']?.toString().trim() ?? '',
    branches: parseRollBranches(arguments['events']),
    selectedLabel: parsed.selected,
    error: parsed.error,
    toolCompleted: completed,
    live: live,
  );
}

/// 解析 roll_random_event 工具结果（成功 → 选中分支；error → 失败信息）
({String? selected, String? error}) parseRollResult(String? toolResultJson) {
  if (toolResultJson == null || toolResultJson.isEmpty) {
    return (selected: null, error: null);
  }
  try {
    final decoded = jsonDecode(toolResultJson);
    if (decoded is Map<String, dynamic>) {
      if (decoded['ok'] == true && decoded['selected'] is String) {
        return (selected: decoded['selected'] as String, error: null);
      }
      if (decoded.containsKey('error')) {
        return (selected: null, error: decoded['message']?.toString() ?? '判定失败');
      }
    }
  } catch (_) {
    // 坏数据按未定处理
  }
  return (selected: null, error: null);
}

/// 判断文本是否为应跳过的系统文本（协议提醒 / 图片占位）
bool isSkippableSystemText(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (t.startsWith(kGameProtocolNudge)) return true;
  if (t.startsWith('[用户上传了图片 mediaId=') && t.endsWith(']')) return true;
  return false;
}

/// 工具调用是否以失败告终（状态为 error / rejected，即"没演成"）
///
/// 校验失败的 narrate/speak（如 speak 的 unknown_character）没有真正"演出"，
/// GM 会按工具返回的纠错提示重调——失败尝试不进剧情流，否则同一句台词
/// 会以"失败版 + 重调成功版"重复渲染两遍（用户反馈 #10/#11 现场日志：
/// speak 失败 → create_character → 同文重调成功）。
///
/// 失败信号读 [AgentToolCall.status] 这一个持久化标志：AgentLoop 的
/// toolSuccess（JSON 结果含 `error` 即失败）经 ToolCallEndEvent 落库时同步
/// 写成对应状态，这里读同一标志即可，不再二次解析结果 JSON——避免在 UI 层
/// 复制一份执行器的错误约定形成双真理源。rejected（已取消）与 error 同为
/// "未演出"。运行中（结果未产出）按未失败处理，不误伤内容。
bool isFailedToolCall(AgentToolCall call) =>
    call.status == AgentToolStatus.error ||
    call.status == AgentToolStatus.rejected;

/// narrate/speak 是否属于"剧情打字机"工具（与生图/骰子等工具卡区分）
bool isStoryStreamTool(String name) => name == 'narrate' || name == 'speak';

/// 流式占位 tool_call id：SSE 帧 id 缺失时由聚合层按 `call_$index` 合成，
/// 真实 id（供应商下发）帧晚到时打字机块仍挂在占位上
final RegExp _kPlaceholderToolCallId = RegExp(r'^call_\d+$');

/// 打字机直播侧剔除失败的 narrate/speak 流式块（与 [isFailedToolCall] 同源语义）
///
/// 失败在工具执行时才确定，而台词文字在参数流式阶段已经打出——不剔除的话
/// 玩家会先看到失败台词出现、回合结束被定稿投影滤掉又消失。成功块与非叙事
/// 工具（生图/骰子，失败态本身是信息）原样保留。
///
/// 兜底：真实 id 帧晚于最后一个参数帧时，块还挂在 `call_N` 占位上（精确
/// 匹配落空）——此时按同名 + 占位 id 剔除。GM 一轮一个叙事工具是常态，
/// 极端并发下误删相邻占位块的风险可接受（其定稿版仍在消息链里，回合结束
/// 投影自愈）。
List<GameStreamingPart> dropFailedStoryStreamingPart(
  List<GameStreamingPart> parts,
  ToolCallEndEvent event,
) {
  if (event.success || !isStoryStreamTool(event.name)) return parts;
  final kept = [...parts]
    ..removeWhere((p) => p.toolCallId == event.toolCallId);
  if (kept.length == parts.length) {
    kept.removeWhere((p) =>
        isStoryStreamTool(p.name) &&
        _kPlaceholderToolCallId.hasMatch(p.toolCallId));
  }
  return kept;
}

/// 回合收尾诊断（游玩页「自动补选」兜底的判定输入）
///
/// 回合协议要求 GM 以 present_choices 收尾，但只是提示词约定：GM 若只演了
/// 剧情就停手，回合会正常 finalize，玩家端一个选项都没有，只剩自由输入框。
/// 这里按「最后一条玩家输入之后」的剧情段做纯判定：
/// - [hasPlayerInput] 定稿链里出现过玩家输入（首回合即「开始游戏」消息）
/// - [hasStoryAfterInput] 该输入之后有剧情产出（旁白/台词/插图/判定）
/// - [hasChoicesAfterInput] 该输入之后有选项组（正常收尾）
({bool hasPlayerInput, bool hasStoryAfterInput, bool hasChoicesAfterInput})
    diagnoseTurnEnding(List<GameSegment> transcript) {
  var lastInputIdx = -1;
  for (var i = 0; i < transcript.length; i++) {
    if (transcript[i] is GamePlayerInput) lastInputIdx = i;
  }
  var hasStory = false;
  var hasChoices = false;
  for (var i = lastInputIdx + 1; i < transcript.length; i++) {
    switch (transcript[i]) {
      case GameNarration() ||
            GameDialogue() ||
            GameSceneImage() ||
            GameDiceRoll():
        hasStory = true;
      case GameChoices():
        hasChoices = true;
      case GamePlayerInput():
        break;
    }
  }
  return (
    hasPlayerInput: lastInputIdx >= 0,
    hasStoryAfterInput: hasStory,
    hasChoicesAfterInput: hasChoices,
  );
}

/// 是否应自动补一轮选项（纯判定，控制器在每个回合 finalize 后调用）
///
/// 「有剧情、无选项」才补；以下情况一律不动：
/// - [agentRunning] 回合仍在跑（finalize 判定时本为 false，保留为防御）
/// - [hasError] 回合失败——玩家需要的是重试，不是自动续跑
/// - [cancelRequested] 玩家主动按了「停止」，绝不能替他重启
/// - [autoNudgeCount] 已自动补过（每条玩家输入至多补 1 次，防无限续跑）
bool shouldAutoNudgeChoices({
  required bool hasStoryAfterInput,
  required bool hasChoicesAfterInput,
  required bool agentRunning,
  required bool hasError,
  required bool cancelRequested,
  required int autoNudgeCount,
}) =>
    !agentRunning &&
    !hasError &&
    !cancelRequested &&
    autoNudgeCount < 1 &&
    hasStoryAfterInput &&
    !hasChoicesAfterInput;

/// 投影主函数
///
/// [messages] 来自 AgentChatState.messages（定稿链）；[agentRunning] 为
/// agent 是否正在运行（决定最后一条选项是否可点）。运行中的回合内容
/// （streamingSegments + ToolArgDelta 流）由游玩页另行拼接在尾部。
/// [avatarByName] 角色名/别名 → 头像 mediaId 映射（共享角色卡，控制器加载），
/// 台词段据此带头像；未命中保持纯彩色名。
List<GameSegment> projectGameTranscript(
  List<AgentChatMessage> messages, {
  required bool agentRunning,
  Map<String, String> avatarByName = const {},
}) {
  final result = <GameSegment>[];
  // 记录最后一个 GameChoices 的索引与其后出现的玩家输入文本
  int? lastChoicesIdx;
  // 回合关闭标记：本回合（自最后一条玩家输入起）已出现 present_choices。
  // 协议下选项即回合终点，其后同回合的任何内容都是违规尾巴（GM 被续跑
  // 钩子逼出的重复剧情/第二组选项）——不渲染，历史脏数据在此自愈。
  bool turnClosed = false;

  for (var msgIdx = 0; msgIdx < messages.length; msgIdx++) {
    final msg = messages[msgIdx];
    switch (msg.role) {
      case AgentChatRole.user:
        final text = msg.content.trim();
        if (isSkippableSystemText(text)) break;
        final seg = GamePlayerInput(text);
        result.add(seg);
        turnClosed = false;
        // 该输入使之前所有选项失效，并可能精确命中最后一个选项；
        // 同时把本输入的位置记录为该选项组的回溯锚点
        if (lastChoicesIdx != null) {
          final choices = result[lastChoicesIdx] as GameChoices;
          final hit = choices.choices.any((c) => c.label == text);
          result[lastChoicesIdx] = GameChoices(
            choices: choices.choices,
            active: false,
            chosenLabel: hit ? text : null,
            rollbackUiIndex: msgIdx,
            toolCallId: choices.toolCallId,
          );
          lastChoicesIdx = null;
        }

      case AgentChatRole.assistant:
        // 回合已收尾：present_choices 之后同回合的内容不渲染（自愈重复）
        if (turnClosed) break;
        for (final seg in msg.segments) {
          if (seg is TextSegment) {
            if (!isSkippableSystemText(seg.content)) {
              result.add(GameNarration(seg.content.trim()));
            }
          } else if (seg is ToolCallSegment) {
            final call = seg.call;
            switch (call.name) {
              case 'narrate':
                // 校验失败的调用没有真正演出（工具返回纠错提示等 GM 重调），
                // 不进剧情流——否则失败版 + 重调成功版重复渲染
                if (isFailedToolCall(call)) break;
                final text = call.arguments['text']?.toString() ?? '';
                if (text.trim().isNotEmpty) {
                  result.add(GameNarration(text.trim()));
                }
              case 'speak':
                if (isFailedToolCall(call)) break;
                final text = call.arguments['text']?.toString() ?? '';
                final character =
                    call.arguments['character']?.toString().trim() ?? '';
                if (text.trim().isNotEmpty) {
                  // 角色名缺失（speak 未带 character，工具已返回纠错错误）：
                  // 退化为旁白，避免渲染出只有空名字签的台词行
                  result.add(character.isEmpty
                      ? GameNarration(text.trim())
                      : GameDialogue(
                          character: character,
                          text: text.trim(),
                          avatarMediaId: avatarByName[character],
                        ));
                }
              case 'create_scene_image':
                final prompt =
                    call.arguments['prompt']?.toString() ?? '';
                final completed = call.status != AgentToolStatus.running;
                result.add(GameSceneImage(
                  toolCallId: call.id,
                  prompt: prompt,
                  toolResultJson: completed ? call.result : null,
                  toolCompleted: completed,
                ));
              case 'roll_random_event':
                result.add(rollDiceRollSegment(
                  call.id,
                  call.arguments,
                  completed: call.status != AgentToolStatus.running,
                  resultJson: call.status == AgentToolStatus.running
                      ? null
                      : call.result,
                ));
              case 'present_choices':
                final choices = parseGameChoices(call.arguments['choices']);
                if (choices.isNotEmpty) {
                  lastChoicesIdx = result.length;
                  result.add(GameChoices(
                    choices: choices,
                    active: false, // 先置 false，循环结束后统一激活最后一条
                    toolCallId: call.id,
                  ));
                  turnClosed = true; // 回合终点：其后内容不再渲染
                }
              default:
                break; // 未知工具不渲染（未来扩展）
            }
          }
        }

      case AgentChatRole.system:
      case AgentChatRole.marker:
        break; // 压缩提示/系统消息不渲染
    }
  }

  // 激活最后一条选项（其后没有玩家输入且 agent 空闲）
  if (lastChoicesIdx != null) {
    final choices = result[lastChoicesIdx] as GameChoices;
    result[lastChoicesIdx] = GameChoices(
      choices: choices.choices,
      active: !agentRunning,
      toolCallId: choices.toolCallId,
    );
  }
  return result;
}

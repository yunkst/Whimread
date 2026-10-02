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
/// - present_choices 工具调用 → [GameChoices]
///
/// 选项活性：只有「最后一条」GameChoices 是可点的（active），其后出现玩家
/// 输入则转为历史；若玩家输入与某选项 label 精确一致，该选项标记 chosen。
/// 历史选项组带 rollbackUiIndex 锚点（其后那条玩家输入的位置），供游玩页
/// 实现「回溯到这一步重新选择」。
library;

import 'dart:convert';

import '../../models/agent_chat_message.dart';
import '../../services/novel_agent/agent_event.dart' show AgentToolStatus;
import '../../services/novel_agent/scenarios/text_game_scenario.dart'
    show kGameProtocolNudge;

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

  const GameChoices({
    required this.choices,
    required this.active,
    this.chosenLabel,
    this.rollbackUiIndex,
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

/// 判断文本是否为应跳过的系统文本（协议提醒 / 图片占位）
bool isSkippableSystemText(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (t.startsWith(kGameProtocolNudge)) return true;
  if (t.startsWith('[用户上传了图片 mediaId=') && t.endsWith(']')) return true;
  return false;
}

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

  for (var msgIdx = 0; msgIdx < messages.length; msgIdx++) {
    final msg = messages[msgIdx];
    switch (msg.role) {
      case AgentChatRole.user:
        final text = msg.content.trim();
        if (isSkippableSystemText(text)) break;
        final seg = GamePlayerInput(text);
        result.add(seg);
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
          );
          lastChoicesIdx = null;
        }

      case AgentChatRole.assistant:
        for (final seg in msg.segments) {
          if (seg is TextSegment) {
            if (!isSkippableSystemText(seg.content)) {
              result.add(GameNarration(seg.content.trim()));
            }
          } else if (seg is ToolCallSegment) {
            final call = seg.call;
            switch (call.name) {
              case 'narrate':
                final text = call.arguments['text']?.toString() ?? '';
                if (text.trim().isNotEmpty) {
                  result.add(GameNarration(text.trim()));
                }
              case 'speak':
                final text = call.arguments['text']?.toString() ?? '';
                final character =
                    call.arguments['character']?.toString() ?? '';
                if (text.trim().isNotEmpty) {
                  result.add(GameDialogue(
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
              case 'present_choices':
                final choices = parseGameChoices(call.arguments['choices']);
                if (choices.isNotEmpty) {
                  lastChoicesIdx = result.length;
                  result.add(GameChoices(
                    choices: choices,
                    active: false, // 先置 false，循环结束后统一激活最后一条
                  ));
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
    );
  }
  return result;
}

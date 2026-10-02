/// 游戏剧情投影器测试
///
/// 覆盖：协议到渲染段的完整映射 / 选项激活与已选标记 / 系统文本过滤 /
/// 生图结果解析 / 空输入兜底。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/services/novel_agent/scenarios/text_game_scenario.dart'
    show kGameProtocolNudge;
import 'package:novel_app/screens/text_game/game_transcript_projector.dart';

AgentToolCall _call(
  String name,
  Map<String, dynamic> args, {
  String id = 'tc1',
  AgentToolStatus status = AgentToolStatus.completed,
  String? result,
}) =>
    AgentToolCall(
      id: id,
      name: name,
      arguments: args,
      status: status,
      result: result,
    );

void main() {
  group('projectGameTranscript', () {
    test('完整回合映射：旁白/台词/生图/选项/玩家输入', () {
      final messages = [
        AgentChatMessage.user('我推门而入'),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('narrate', {'text': '屋内烛火摇曳。'})),
        ]),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'speak',
            {'character': '林昭', 'text': '你来了。'},
            id: 'tc2',
          )),
        ]),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'create_scene_image',
            {'prompt': 'candlelit room'},
            id: 'tc3',
            result: '{"success":true,"images":[{"mediaId":"local_1"}],"count":1}',
          )),
        ]),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '询问来意', 'hint': '温和开场'},
                {'label': '拔剑相向'},
              ]
            },
            id: 'tc4',
            result: '{"ok":true}',
          )),
        ]),
      ];

      final segs = projectGameTranscript(messages, agentRunning: false);

      expect(segs, hasLength(5));
      expect(segs[0], isA<GamePlayerInput>());
      expect((segs[0] as GamePlayerInput).text, '我推门而入');
      expect((segs[1] as GameNarration).text, '屋内烛火摇曳。');
      final dialogue = segs[2] as GameDialogue;
      expect(dialogue.character, '林昭');
      expect(dialogue.text, '你来了。');
      final image = segs[3] as GameSceneImage;
      expect(image.prompt, 'candlelit room');
      expect(parseSceneImageMediaIds(image.toolResultJson), ['local_1']);
      final choices = segs[4] as GameChoices;
      expect(choices.choices.map((c) => c.label), ['询问来意', '拔剑相向']);
      expect(choices.choices.first.hint, '温和开场');
      expect(choices.active, isTrue, reason: '最后一条选项且 agent 空闲 → 可点');
    });

    test('选项历史化：其后出现玩家输入 → 置灰 + 精确命中标记已选', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '留下'},
                {'label': '离开'},
              ]
            },
          )),
        ]),
        AgentChatMessage.user('离开'),
      ];

      final segs = projectGameTranscript(messages, agentRunning: false);
      expect(segs, hasLength(2));
      final choices = segs[0] as GameChoices;
      expect(choices.active, isFalse);
      expect(choices.chosenLabel, '离开');
      expect(segs[1], isA<GamePlayerInput>());
    });

    test('选项后玩家自由输入（非 label）→ 置灰但不标记已选', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '留下'},
                {'label': '离开'},
              ]
            },
          )),
        ]),
        AgentChatMessage.user('我在原地犹豫了很久'),
      ];

      final choices =
          projectGameTranscript(messages, agentRunning: false).first as GameChoices;
      expect(choices.active, isFalse);
      expect(choices.chosenLabel, isNull);
    });

    test('历史选项带回溯锚点（其后玩家输入的链内索引）；最后活动选项无锚点', () {
      final messages = [
        AgentChatMessage.user('开始游戏'), // idx 0
        AgentChatMessage.assistantFromSegments([
          // idx 1
          ToolCallSegment(_call('narrate', {'text': '风雪压城。'}, id: 't1')),
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '迎战'},
                {'label': '撤离'},
              ]
            },
            id: 't2',
          )),
        ]),
        AgentChatMessage.user('迎战'), // idx 2 → 锚点
        AgentChatMessage.assistantFromSegments([
          // idx 3
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '追击'},
                {'label': '原地休整'},
              ]
            },
            id: 't3',
          )),
        ]),
      ];

      final segs = projectGameTranscript(messages, agentRunning: false);
      expect(segs, hasLength(5));
      final historical = segs[2] as GameChoices;
      expect(historical.active, isFalse);
      expect(historical.chosenLabel, '迎战');
      expect(historical.rollbackUiIndex, 2, reason: '锚点 = 其后玩家输入的索引');
      final active = segs[4] as GameChoices;
      expect(active.active, isTrue);
      expect(active.rollbackUiIndex, isNull, reason: '活动选项无可回溯的后续输入');
    });

    test('协议提醒 user 注入被跳过：不渲染、不产生锚点，真实输入锚点指向自身', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          // idx 0
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '留下'},
                {'label': '离开'},
              ]
            },
          )),
        ]),
        AgentChatMessage.user('$kGameProtocolNudge 请用工具输出'), // idx 1，跳过
        AgentChatMessage.user('离开'), // idx 2 → 锚点
      ];

      final segs = projectGameTranscript(messages, agentRunning: false);
      expect(segs, hasLength(2));
      final choices = segs[0] as GameChoices;
      expect(choices.active, isFalse);
      expect(choices.chosenLabel, '离开');
      expect(choices.rollbackUiIndex, 2);
      expect(segs[1], isA<GamePlayerInput>());
    });

    test('台词头像：按 avatarByName 映射附加，未命中为 null', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'speak',
            {'character': '林昭', 'text': '你来了。'},
            id: 'tcA',
          )),
        ]),
      ];

      final withAvatar = projectGameTranscript(
        messages,
        agentRunning: false,
        avatarByName: const {'林昭': 'media_9'},
      ).first as GameDialogue;
      expect(withAvatar.avatarMediaId, 'media_9');

      final without =
          projectGameTranscript(messages, agentRunning: false).first
              as GameDialogue;
      expect(without.avatarMediaId, isNull);
    });

    test('agent 运行中：最后一条选项不可点', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': 'a'},
                {'label': 'b'},
              ]
            },
          )),
        ]),
      ];
      final choices =
          projectGameTranscript(messages, agentRunning: true).first as GameChoices;
      expect(choices.active, isFalse);
    });

    test('协议提醒（assistant 裸文本 + user 注入）被过滤', () {
      final messages = [
        AgentChatMessage.user('$kGameProtocolNudge 请用工具输出'),
        AgentChatMessage.assistant('$kGameProtocolNudge 本回合没有调用任何工具…'),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('narrate', {'text': '正常旁白'})),
        ]),
      ];

      final segs = projectGameTranscript(messages, agentRunning: false);
      expect(segs, hasLength(1));
      expect(segs.first, isA<GameNarration>());
    });

    test('assistant 裸文本兜底为旁白；空文本跳过', () {
      final messages = [
        AgentChatMessage.assistant('夜幕降临。'),
        AgentChatMessage.assistant('   '),
      ];
      final segs = projectGameTranscript(messages, agentRunning: false);
      expect(segs, hasLength(1));
      expect((segs.first as GameNarration).text, '夜幕降临。');
    });

    test('system/marker 消息不渲染', () {
      final messages = [
        AgentChatMessage.system('[上下文压缩|...]'),
        AgentChatMessage.compactionMarker(CompactionMarkerSegment(
          droppedMessageCount: 1,
          keptMessageCount: 2,
          removedChars: 10,
          originalChars: 20,
          compactedChars: 5,
        )),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('narrate', {'text': '正文'})),
        ]),
      ];
      final segs = projectGameTranscript(messages, agentRunning: false);
      expect(segs, hasLength(1));
    });

    test('未知工具不渲染', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('list_novels', {})),
          ToolCallSegment(_call('narrate', {'text': '旁白'}, id: 'tc9')),
        ]),
      ];
      final segs = projectGameTranscript(messages, agentRunning: false);
      expect(segs, hasLength(1));
    });
  });

  group('parseSceneImage 辅助', () {
    test('失败结果解析错误信息', () {
      expect(
        parseSceneImageError('{"error":"generation_failed","message":"超时"}'),
        '超时',
      );
      expect(parseSceneImageError('{"success":true,"images":[]}'), isNull);
      expect(parseSceneImageError('not json'), isNull);
    });

    test('运行中占位（无结果）解析为无媒体无错误', () {
      expect(parseSceneImageMediaIds(null), isEmpty);
      expect(parseSceneImageError(null), isNull);
    });
  });
}

/// 游戏剧情投影器测试
///
/// 覆盖：协议到渲染段的完整映射 / 选项激活与已选标记 / 系统文本过滤 /
/// 生图结果解析 / 概率判定段解析（分支/选中/失败/运行中）/ 空输入兜底 /
/// 失败工具调用过滤（定稿侧 isFailedToolCall）。
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

    test('assistant 裸文本不渲染（正文必须经工具输出）；空文本同样跳过', () {
      final messages = [
        AgentChatMessage.assistant('夜幕降临。'),
        AgentChatMessage.assistant('   '),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('narrate', {'text': '经工具的正文'})),
        ]),
      ];
      final segs = projectGameTranscript(messages, agentRunning: false);
      // 只有工具产出的旁白入流；绕过工具的裸文本（含空文本）一律不渲染
      expect(segs, hasLength(1));
      expect((segs.first as GameNarration).text, '经工具的正文');
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

    group('roll_random_event → GameDiceRoll', () {
      Map<String, dynamic> rollArgs() => {
            'reason': '主角强闯山门禁制',
            'events': [
              {'label': '闯关成功', 'weight': 70},
              {'label': '闯关失败', 'weight': 30},
            ],
          };

      test('已完成判定：分支/百分比/选中项/缘由解析', () {
        final messages = [
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call(
              'roll_random_event',
              rollArgs(),
              id: 'tcR1',
              result:
                  '{"ok":true,"selected":"闯关失败","selectedPercent":"30%",'
                  '"branches":[],"note":"..."}',
            )),
          ]),
        ];
        final seg =
            projectGameTranscript(messages, agentRunning: false).single
                as GameDiceRoll;
        expect(seg.toolCallId, 'tcR1');
        expect(seg.reason, '主角强闯山门禁制');
        expect(seg.branches.map((b) => b.label), ['闯关成功', '闯关失败']);
        expect(seg.branches.map((b) => b.percent), ['70%', '30%']);
        expect(seg.selectedLabel, '闯关失败');
        expect(seg.selectedPercent, '30%');
        expect(seg.error, isNull);
        expect(seg.toolCompleted, isTrue);
      });

      test('运行中判定：无选中、未完成（pending 动画轮转 / 定稿降级）', () {
        final messages = [
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call(
              'roll_random_event',
              rollArgs(),
              id: 'tcR2',
              status: AgentToolStatus.running,
            )),
          ]),
        ];
        final seg =
            projectGameTranscript(messages, agentRunning: true).single
                as GameDiceRoll;
        expect(seg.toolCompleted, isFalse);
        expect(seg.selectedLabel, isNull);
        expect(seg.branches, hasLength(2), reason: '分支在参数里，运行中即可渲染');
        expect(seg.selectedPercent, isNull);
      });

      test('判定失败：解析错误信息', () {
        final messages = [
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call(
              'roll_random_event',
              rollArgs(),
              id: 'tcR3',
              result: '{"error":"invalid_weight","message":"weight 必须是正数"}',
            )),
          ]),
        ];
        final seg =
            projectGameTranscript(messages, agentRunning: false).single
                as GameDiceRoll;
        expect(seg.error, 'weight 必须是正数');
        expect(seg.selectedLabel, isNull);
      });

      test('分支解析宽容：字符串权重 / 缺 label 跳过 / 缺 weight 等概率', () {
        final branches = parseRollBranches([
          {'label': '甲', 'weight': '20'},
          {'weight': 99},
          {'label': '乙'},
          {'label': '丙', 'weight': -3},
        ]);
        expect(branches.map((b) => b.label), ['甲', '乙', '丙']);
        expect(branches.map((b) => b.weight), [20.0, 1.0, 1.0]);
        // 总权重 20+1+1=22（weight=99 那项无 label 被跳过，-3 归一为 1）
        expect(branches.map((b) => b.percent), ['90.9%', '4.5%', '4.5%']);

        expect(parseRollBranches(null), isEmpty);
        expect(parseRollBranches('not a list'), isEmpty);
      });

      test('结果解析兜底：坏 JSON / 空结果', () {
        expect(parseRollResult(null).selected, isNull);
        expect(parseRollResult('not json').selected, isNull);
        expect(parseRollResult('{"error":"x","message":"坏"}').error, '坏');
        expect(parseRollResult('{"ok":true}').selected, isNull);
      });
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

  group('正文转义残留归一化（normalizeStoryText）', () {
    test('字面量 \\n / \\r\\n / \\r 还原为真实换行', () {
      expect(normalizeStoryText(r'第一段\n第二段'), '第一段\n第二段');
      expect(normalizeStoryText(r'第一段\r\n第二段'), '第一段\n第二段');
      expect(normalizeStoryText(r'第一段\r第二段'), '第一段\n第二段');
      // 混合：字面量与真实换行并存
      expect(normalizeStoryText('甲\n乙\\n丙'), '甲\n乙\n丙');
    });

    test('真实换行与无转义文本原样透传', () {
      expect(normalizeStoryText('第一段\n第二段'), '第一段\n第二段');
      expect(normalizeStoryText('没有转义的正文。'), '没有转义的正文。');
      expect(normalizeStoryText(''), '');
    });

    test('narrate / speak 投影时归一化，剧情流不出现字面量 \\n', () {
      final messages = [
        // 模型偶发双重转义：JSON 里的 \\n 解码后是「\ + n」两个字符
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('narrate', {
            'text': r'烛火摇曳。\n窗外雨声渐歇。',
          })),
        ]),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'speak',
            {
              'character': '林昭',
              'text': r'你终于来了。\r\n我等了很久。',
            },
            id: 'tc2',
          )),
        ]),
      ];

      final segs = projectGameTranscript(messages, agentRunning: false);

      expect((segs[0] as GameNarration).text, '烛火摇曳。\n窗外雨声渐歇。');
      expect((segs[1] as GameDialogue).text, '你终于来了。\n我等了很久。');
    });
  });

  group('speak 缺角色名降级', () {
    test('speak 未带 character：退化为旁白，不渲染空名字签', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('speak', {'text': '（无人称台词）'})),
        ]),
      ];
      final seg = projectGameTranscript(messages, agentRunning: false).single;
      expect(seg, isA<GameNarration>());
      expect((seg as GameNarration).text, '（无人称台词）');
    });

    test('带 character 的 speak 正常渲染台词', () {
      final messages = [
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('speak', {'character': '林昭', 'text': '你来了。'})),
        ]),
      ];
      final seg = projectGameTranscript(messages, agentRunning: false).single;
      expect(seg, isA<GameDialogue>());
      expect((seg as GameDialogue).character, '林昭');
    });
  });

  group('回合收尾诊断（自动补选兜底）', () {
    test('正常收尾：有输入、有剧情、有选项 → 不补', () {
      final d = diagnoseTurnEnding([
        const GamePlayerInput('我推门而入'),
        const GameNarration('屋内烛火摇曳。'),
        const GameChoices(choices: [
          GameChoice(label: '环视四周'),
          GameChoice(label: '退出房间'),
        ], active: false),
      ]);
      expect(d.hasPlayerInput, isTrue);
      expect(d.hasStoryAfterInput, isTrue);
      expect(d.hasChoicesAfterInput, isTrue);
      expect(
        shouldAutoNudgeChoices(
          hasStoryAfterInput: d.hasStoryAfterInput,
          hasChoicesAfterInput: d.hasChoicesAfterInput,
          agentRunning: false,
          hasError: false,
          cancelRequested: false,
          autoNudgeCount: 0,
        ),
        isFalse,
      );
    });

    test('GM 漏收尾：有剧情、无选项 → 应补', () {
      final d = diagnoseTurnEnding([
        const GamePlayerInput('开始游戏'),
        const GameNarration('雨夜，你在城门口醒来。'),
        const GameDialogue(character: '守卫', text: '站住！什么人？'),
      ]);
      expect(d.hasStoryAfterInput, isTrue);
      expect(d.hasChoicesAfterInput, isFalse);
      expect(
        shouldAutoNudgeChoices(
          hasStoryAfterInput: d.hasStoryAfterInput,
          hasChoicesAfterInput: d.hasChoicesAfterInput,
          agentRunning: false,
          hasError: false,
          cancelRequested: false,
          autoNudgeCount: 0,
        ),
        isTrue,
      );
    });

    test('输入后只有选项没有剧情：不补（无剧情可续）', () {
      final d = diagnoseTurnEnding([
        const GamePlayerInput('继续'),
        const GameChoices(choices: [
          GameChoice(label: '甲'),
          GameChoice(label: '乙'),
        ], active: false),
      ]);
      expect(d.hasStoryAfterInput, isFalse);
      expect(
        shouldAutoNudgeChoices(
          hasStoryAfterInput: d.hasStoryAfterInput,
          hasChoicesAfterInput: d.hasChoicesAfterInput,
          agentRunning: false,
          hasError: false,
          cancelRequested: false,
          autoNudgeCount: 0,
        ),
        isFalse,
      );
    });

    test('空链：无输入无剧情，不补', () {
      final d = diagnoseTurnEnding(const []);
      expect(d.hasPlayerInput, isFalse);
      expect(d.hasStoryAfterInput, isFalse);
      expect(
        shouldAutoNudgeChoices(
          hasStoryAfterInput: d.hasStoryAfterInput,
          hasChoicesAfterInput: d.hasChoicesAfterInput,
          agentRunning: false,
          hasError: false,
          cancelRequested: false,
          autoNudgeCount: 0,
        ),
        isFalse,
      );
    });

    test('守卫各自否决：运行中 / 失败回合 / 玩家取消 / 已补过一次', () {
      bool nudge({required bool agentRunning, required bool hasError,
          required bool cancelRequested, required int autoNudgeCount}) =>
          shouldAutoNudgeChoices(
            hasStoryAfterInput: true,
            hasChoicesAfterInput: false,
            agentRunning: agentRunning,
            hasError: hasError,
            cancelRequested: cancelRequested,
            autoNudgeCount: autoNudgeCount,
          );
      expect(nudge(
          agentRunning: true, hasError: false, cancelRequested: false,
          autoNudgeCount: 0), isFalse);
      expect(nudge(
          agentRunning: false, hasError: true, cancelRequested: false,
          autoNudgeCount: 0), isFalse, reason: '失败回合玩家要的是重试');
      expect(nudge(
          agentRunning: false, hasError: false, cancelRequested: true,
          autoNudgeCount: 0), isFalse, reason: '玩家按过停止，不能替他重启');
      expect(nudge(
          agentRunning: false, hasError: false, cancelRequested: false,
          autoNudgeCount: 1), isFalse, reason: '每条玩家输入至多自动补 1 次');
    });
  });

  group('回合关闭截断（present_choices 之后不渲染）', () {
    List<GameSegment> projectTailRepeat() => projectGameTranscript([
          AgentChatMessage.user('我推门而入'),
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call('narrate', {'text': '第一段剧情。'}, id: 'n1')),
          ]),
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call(
              'present_choices',
              {
                'choices': [
                  {'label': '拔剑'},
                  {'label': '后退'},
                ]
              },
              id: 'c1',
              result: '{"ok":true}',
            )),
          ]),
          // ↓↓ 以下是 GM 被续跑钩子推出来的重复内容（用户反馈 #10 的现场）
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call('narrate', {'text': '第一段剧情。'}, id: 'n2')),
          ]),
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call(
              'speak',
              {'character': '林昭', 'text': '你来了。'},
              id: 's2',
            )),
          ]),
          AgentChatMessage.assistantFromSegments([const TextSegment('好的。')]),
          AgentChatMessage.user('$kGameProtocolNudge 本回合没有调用任何工具…'),
          AgentChatMessage.assistantFromSegments([
            ToolCallSegment(_call(
              'present_choices',
              {
                'choices': [
                  {'label': '拔剑'},
                  {'label': '后退'},
                ]
              },
              id: 'c2',
              result: '{"ok":true}',
            )),
          ]),
        ], agentRunning: false);

    test('选项之后的重复剧情/台词/第二组选项全部不渲染', () {
      final segs = projectTailRepeat();
      expect(segs, hasLength(3), reason: '输入 + 旁白 + 选项，各一份');
      expect((segs[1] as GameNarration).text, '第一段剧情。');
      final choices = segs[2] as GameChoices;
      expect(choices.choices.map((c) => c.label), ['拔剑', '后退']);
      expect(choices.toolCallId, 'c1', reason: '保留首个选项组，后来的丢弃');
      expect(choices.active, isTrue);
    });

    test('下一条玩家输入重新开启回合（截断不跨回合）', () {
      final segs = projectGameTranscript([
        AgentChatMessage.user('第一回合'),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '甲'},
                {'label': '乙'},
              ]
            },
            id: 'c1',
            result: '{"ok":true}',
          )),
        ]),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('narrate', {'text': '回合尾巴。'}, id: 'n2')),
        ]),
        AgentChatMessage.user('第二回合'),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call('narrate', {'text': '新剧情。'}, id: 'n3')),
        ]),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'present_choices',
            {
              'choices': [
                {'label': '丙'},
                {'label': '丁'},
              ]
            },
            id: 'c2',
            result: '{"ok":true}',
          )),
        ]),
      ], agentRunning: false);

      expect(segs, hasLength(5));
      expect((segs[0] as GamePlayerInput).text, '第一回合');
      expect((segs[1] as GameChoices).toolCallId, 'c1');
      expect((segs[1] as GameChoices).active, isFalse, reason: '已有后续输入');
      expect((segs[1] as GameChoices).rollbackUiIndex, 3,
          reason: '回溯锚点指向下一条玩家输入');
      expect((segs[2] as GamePlayerInput).text, '第二回合');
      expect((segs[3] as GameNarration).text, '新剧情。');
      expect((segs[4] as GameChoices).toolCallId, 'c2');
      expect((segs[4] as GameChoices).active, isTrue);
    });
  });

  group('失败工具调用不进剧情流（isFailedToolCall）', () {
    const errUnknownCharacter = '{"error":"unknown_character",'
        '"message":"未知角色「虞贵妃」。登场角色：虞欢。",'
        '"knownCharacters":["虞欢"]}';

    test('speak 校验失败 + 同文重调成功 → 只渲染成功那条', () {
      final segs = projectGameTranscript([
        AgentChatMessage.user('我看向她'),
        // 第一次：角色名不在参战名单，工具返回纠错错误（状态 error）
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'speak',
            {'character': '虞贵妃', 'text': '七郎无罪，是臣妾教子无方。'},
            id: 's_fail',
            status: AgentToolStatus.error,
            result: errUnknownCharacter,
          )),
        ]),
        // GM 建卡后同文重调 → 玩家只应看到这一条
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'speak',
            {'character': '虞欢', 'text': '七郎无罪，是臣妾教子无方。'},
            id: 's_ok',
            result: '{"ok":true}',
          )),
        ]),
      ], agentRunning: false);

      expect(segs, hasLength(2), reason: '玩家输入 + 一条台词（失败版不渲染）');
      final dialogue = segs[1] as GameDialogue;
      expect(dialogue.character, '虞欢');
      expect(dialogue.text, '七郎无罪，是臣妾教子无方。');
    });

    test('narrate 失败（execution_failed 但 text 非空）→ 不渲染旁白', () {
      final segs = projectGameTranscript([
        AgentChatMessage.user('我推门而入'),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'narrate',
            {'text': '这段没能演成。'},
            id: 'n_fail',
            status: AgentToolStatus.error,
            result: '{"error":"execution_failed","message":"工具异常"}',
          )),
        ]),
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'narrate',
            {'text': '屋内烛火摇曳。'},
            id: 'n_ok',
            result: '{"ok":true}',
          )),
        ]),
      ], agentRunning: false);

      expect(segs, hasLength(2));
      expect((segs[1] as GameNarration).text, '屋内烛火摇曳。');
    });

    test('防误伤：运行中（结果未产出）→ 照常渲染', () {
      final segs = projectGameTranscript([
        AgentChatMessage.assistantFromSegments([
          ToolCallSegment(_call(
            'narrate',
            {'text': '正在写。'},
            id: 'n_running',
            status: AgentToolStatus.running,
          )),
          ToolCallSegment(_call(
            'speak',
            {'character': '林昭', 'text': '还在判定中。'},
            id: 's_running',
            status: AgentToolStatus.running,
          )),
        ]),
      ], agentRunning: true);

      expect(segs, hasLength(2));
      expect((segs[0] as GameNarration).text, '正在写。');
      expect((segs[1] as GameDialogue).text, '还在判定中。');
    });

    test('isFailedToolCall 四态判定（失败信号取持久化状态）', () {
      expect(
          isFailedToolCall(_call('speak', const {}, result: '{"ok":true}')),
          isFalse,
          reason: 'completed 不是失败');
      expect(
          isFailedToolCall(
              _call('speak', const {}, status: AgentToolStatus.running)),
          isFalse,
          reason: '运行中按未失败处理');
      expect(
          isFailedToolCall(
              _call('speak', const {}, status: AgentToolStatus.rejected)),
          isTrue,
          reason: '已取消与 error 同为"没演成"');
      expect(
          isFailedToolCall(_call('speak', const {},
              status: AgentToolStatus.error, result: errUnknownCharacter)),
          isTrue);
      expect(
          isFailedToolCall(_call('speak', const {}, result: 'garbage')),
          isFalse,
          reason: '判定只读状态不解析结果 JSON，坏 JSON 不影响判定');
    });
  });

}

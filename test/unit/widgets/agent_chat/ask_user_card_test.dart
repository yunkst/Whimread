/// AskUserCard 组件测试
///
/// 覆盖三种交互（单选点击即答 / 多选勾选+确认 / 自由输入提交）与
/// 已答、失效两种静态渲染。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/widgets/agent_chat/ask_user_card.dart';

AgentToolCall _call({
  AgentToolStatus status = AgentToolStatus.running,
  Map<String, dynamic>? arguments,
  String? result,
}) {
  return AgentToolCall(
    id: 'call_1',
    name: 'ask_user',
    arguments: arguments ??
        {
          'question': '用第几人称叙述？',
          'options': ['第一人称', '第三人称'],
          'multi_select': false,
          'allow_free_text': true,
        },
    status: status,
    result: result,
  );
}

Widget _wrap(
  AgentToolCall call, {
  bool awaitingAnswer = true,
  required void Function(List<String>? selected, String? freeText) onAnswer,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AskUserCard(
        call: call,
        awaitingAnswer: awaitingAnswer,
        onAnswer: onAnswer,
      ),
    ),
  );
}

void main() {
  testWidgets('待答态：渲染问题与候选项（单选）', (tester) async {
    await tester.pumpWidget(
      _wrap(_call(), onAnswer: (_, __) {}),
    );
    expect(find.text('用第几人称叙述？'), findsOneWidget);
    expect(find.text('第一人称'), findsOneWidget);
    expect(find.text('第三人称'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget,
        reason: 'allow_free_text 默认 true，应有自由输入框');
  });

  testWidgets('单选：点击候选立即作答', (tester) async {
    List<String>? answered;
    await tester.pumpWidget(
      _wrap(_call(), onAnswer: (selected, freeText) => answered = selected),
    );
    await tester.tap(find.text('第三人称'));
    expect(answered, ['第三人称']);
    // 点击后进入"已回答，等待继续…"防重复状态
    await tester.pump();
    expect(find.textContaining('已回答'), findsOneWidget);
  });

  testWidgets('对象选项 {title, description}：归一为短语+说明两行展示，作答只回短语',
      (tester) async {
    List<String>? answered;
    await tester.pumpWidget(
      _wrap(
        _call(arguments: {
          'question': '游戏主基调？',
          'options': [
            {
              'title': '后宫权斗（默认）',
              'description': '以收编妃嫔、稳固皇权为核心',
            },
            {'label': '双线并进', 'description': '朝堂与后宫并重'},
          ],
        }),
        onAnswer: (selected, freeText) => answered = selected,
      ),
    );
    // 短语与说明都完整展示（不再有 {title: ...} 原样 JSON 字样）
    expect(find.text('后宫权斗（默认）'), findsOneWidget);
    expect(find.textContaining('以收编妃嫔'), findsOneWidget);
    expect(find.textContaining('{title'), findsNothing);
    // 点击短语行 → 只回传短语
    await tester.tap(find.text('后宫权斗（默认）'));
    expect(answered, ['后宫权斗（默认）']);
  });

  testWidgets('多选：勾选 + 确认按钮提交所选', (tester) async {
    List<String>? answered;
    await tester.pumpWidget(
      _wrap(
        _call(arguments: {
          'question': '保留哪些元素？',
          'options': ['悬疑', '权谋', '爱情'],
          'multi_select': true,
        }),
        onAnswer: (selected, freeText) => answered = selected,
      ),
    );
    // 未勾选时确认按钮禁用
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('悬疑'));
    await tester.tap(find.text('权谋'));
    await tester.pump();
    await tester.tap(find.textContaining('已选 2 项'));
    expect(answered, ['悬疑', '权谋']);
  });

  testWidgets('自由输入：输入文本后发送提交 freeText', (tester) async {
    String? answeredText;
    await tester.pumpWidget(
      _wrap(
        _call(arguments: {'question': '主角叫什么？'}),
        onAnswer: (selected, freeText) => answeredText = freeText,
      ),
    );
    await tester.enterText(find.byType(TextField), '林晚');
    await tester.tap(find.byTooltip('提交回答'));
    expect(answeredText, '林晚');
  });

  testWidgets('已答态（completed）：所选内容整行勾选样式展示', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _call(
          status: AgentToolStatus.completed,
          result: jsonEncode({
            'success': true,
            'question': '用第几人称叙述？',
            'selected': ['第一人称'],
          }),
        ),
        awaitingAnswer: false,
        onAnswer: (_, __) {},
      ),
    );
    expect(find.textContaining('已回答'), findsOneWidget);
    expect(find.text('第一人称'), findsOneWidget);
  });

  testWidgets('已答态：自由输入内容以文本块展示', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _call(
          status: AgentToolStatus.completed,
          arguments: {'question': '主角叫什么？'},
          result: jsonEncode({
            'success': true,
            'question': '主角叫什么？',
            'free_text': '就叫林晚',
          }),
        ),
        awaitingAnswer: false,
        onAnswer: (_, __) {},
      ),
    );
    expect(find.text('就叫林晚'), findsOneWidget);
  });

  testWidgets('失效态：running 但本轮已结束 → 显示未回答且不渲染可点候选', (tester) async {
    List<String>? answered;
    await tester.pumpWidget(
      _wrap(
        _call(),
        awaitingAnswer: false,
        onAnswer: (selected, __) => answered = selected,
      ),
    );
    expect(find.textContaining('未回答（本轮已中断）'), findsOneWidget);
    expect(find.text('第一人称'), findsNothing,
        reason: '失效态不应渲染可交互的候选 chip');
    expect(answered, isNull);
  });

  testWidgets('取消收尾态（completed + status=cancelled）：显示取消文案', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _call(
          status: AgentToolStatus.completed,
          result: jsonEncode({
            'success': true,
            'status': 'cancelled',
            'question': '用第几人称叙述？',
          }),
        ),
        awaitingAnswer: false,
        onAnswer: (_, __) {},
      ),
    );
    expect(find.textContaining('已取消'), findsOneWidget);
    expect(find.textContaining('已被取消'), findsOneWidget);
  });
}

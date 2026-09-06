import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/widgets/agent_chat/compaction_marker_card.dart';

void main() {
  testWidgets('默认折叠，点击展开显示统计', (tester) async {
    final seg = const CompactionMarkerSegment(
      droppedMessageCount: 23,
      keptMessageCount: 15,
      removedChars: 420000,
      originalChars: 580000,
      compactedChars: 160000,
      rewrittenCount: 8,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CompactionMarkerCard(segment: seg))),
    );
    expect(find.textContaining('丢弃 23 条'), findsOneWidget);
    expect(find.textContaining('释放字符'), findsNothing); // 展开内容默认不可见

    await tester.tap(find.byType(CompactionMarkerCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('释放字符'), findsOneWidget);
    // 第 4 格「保留消息」追加「(其中 8 条 tool result 被改写)」
    expect(find.textContaining('8 条 tool result 被改写'), findsOneWidget);
    // 预剪枝 1-liner 文案
    expect(find.textContaining('预剪枝'), findsOneWidget);
  });

  testWidgets('rewrittenCount=0 时不显示改写行', (tester) async {
    final seg = const CompactionMarkerSegment(
      droppedMessageCount: 1,
      keptMessageCount: 1,
      removedChars: 10,
      originalChars: 20,
      compactedChars: 10,
      rewrittenCount: 0,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CompactionMarkerCard(segment: seg))),
    );
    await tester.tap(find.byType(CompactionMarkerCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('改写'), findsNothing);
  });
}

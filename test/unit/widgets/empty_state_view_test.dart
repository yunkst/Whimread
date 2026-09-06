import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/empty_states/empty_state_view.dart';

void main() {
  testWidgets('不传 iconWidget/titleStyle 时走原逻辑（IconData 渲染）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EmptyStateView(icon: Icons.search, title: '空的')),
    ));
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('空的'), findsOneWidget);
  });

  testWidgets('传 iconWidget 时渲染该 widget 而非 IconData', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EmptyStateView(
        icon: Icons.search, // 仍必填（向后兼容），但被 iconWidget 覆盖
        title: '空的',
        iconWidget: const Icon(Icons.edit, size: 48),
      )),
    ));
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('传 titleStyle 时覆盖默认 headlineSmall', (tester) async {
    const custom = TextStyle(fontFamily: 'NotoSerifSC', fontSize: 17);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EmptyStateView(icon: Icons.search, title: '空的', titleStyle: custom)),
    ));
    final text = tester.widget<Text>(find.text('空的'));
    expect(text.style?.fontFamily, 'NotoSerifSC');
    expect(text.style?.fontSize, 17);
  });
}

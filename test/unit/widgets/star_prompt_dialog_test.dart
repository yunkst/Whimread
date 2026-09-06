import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/star_prompt_dialog.dart';

void main() {
  testWidgets('点主按钮 pop true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const StarPromptDialog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 主按钮文案包含「Star」
    await tester.tap(find.text('去 GitHub 点 Star'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('点「关闭」pop false + 文案关键句命中', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const StarPromptDialog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 文案关键句必须命中
    expect(find.textContaining('开源'), findsOneWidget);
    expect(find.textContaining('Star'), findsWidgets);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}

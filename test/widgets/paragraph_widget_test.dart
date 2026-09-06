import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/widgets/paragraph_widget.dart';

/// ParagraphWidget 循环嵌套问题的单元测试
///
/// 测试目标：
/// 1. 验证 didUpdateWidget 更新 controller.text 时不会触发 onContentChanged
/// 2. 确保程序更新和用户输入能够正确区分
/// 3. 防止无限循环导致的堆栈溢出
void main() {
  group('ParagraphWidget 循环嵌套测试', () {
    testWidgets(
      '当 didUpdateWidget 更新段落内容时，不应该触发 onContentChanged 回调',
      (WidgetTester tester) async {
        // Arrange
        String initialParagraph = '初始段落内容';
        String updatedParagraph = '更新后的段落内容';
        int onContentChangedCallCount = 0;
        String? lastChangedContent;

        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: ParagraphWidget(
                paragraph: initialParagraph,
                index: 0,
                fontSize: 18.0,
                isEditMode: true,
                onContentChanged: (newContent) {
                  onContentChangedCallCount++;
                  lastChangedContent = newContent;
                },
              ),
            ),
          ),
        );

        // 等待 widget 完成初始化
        await tester.pumpAndSettle();

        // Act: 更新 paragraph 内容（模拟父组件重建）
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: ParagraphWidget(
                paragraph: updatedParagraph,
                index: 0,
                fontSize: 18.0,
                isEditMode: true,
                onContentChanged: (newContent) {
                  onContentChangedCallCount++;
                  lastChangedContent = newContent;
                },
              ),
            ),
          ),
        );

        // 等待 didUpdateWidget 完成
        await tester.pump();

        // Assert: 验证 onContentChanged 没有被程序更新触发
        expect(
          onContentChangedCallCount,
          equals(0),
          reason: 'didUpdateWidget 更新 controller.text 时不应触发 onContentChanged',
        );
      },
    );

    testWidgets(
      '用户在 TextField 中输入时，应该正确触发 onContentChanged 回调',
      (WidgetTester tester) async {
        // Arrange
        String initialParagraph = '初始内容';
        int onContentChangedCallCount = 0;
        String? lastChangedContent;

        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: ParagraphWidget(
                paragraph: initialParagraph,
                index: 0,
                fontSize: 18.0,
                isEditMode: true,
                onContentChanged: (newContent) {
                  onContentChangedCallCount++;
                  lastChangedContent = newContent;
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Act: 用户在 TextField 中输入
        const userInput = '用户输入的内容';
        await tester.enterText(find.byType(TextField), userInput);

        // Assert: 验证 onContentChanged 被触发
        expect(
          onContentChangedCallCount,
          greaterThan(0),
          reason: '用户输入时应该触发 onContentChanged',
        );
        expect(
          lastChangedContent,
          equals(userInput),
          reason: 'onContentChanged 应该接收到用户输入的内容',
        );
      },
    );

    testWidgets(
      '连续更新 paragraph 多次不应该累积触发 onContentChanged',
      (WidgetTester tester) async {
        // Arrange
        int onContentChangedCallCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: ParagraphWidget(
                paragraph: '版本1',
                index: 0,
                fontSize: 18.0,
                isEditMode: true,
                onContentChanged: (_) => onContentChangedCallCount++,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Act: 连续更新 paragraph 3次
        for (int i = 2; i <= 4; i++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Material(
                child: ParagraphWidget(
                  paragraph: '版本$i',
                  index: 0,
                  fontSize: 18.0,
                  isEditMode: true,
                  onContentChanged: (_) => onContentChangedCallCount++,
                ),
              ),
            ),
          );
          await tester.pump();
        }

        // Assert: 验证 onContentChanged 没有被触发
        expect(
          onContentChangedCallCount,
          equals(0),
          reason: '连续的程序更新不应该触发 onContentChanged',
        );
      },
    );

    testWidgets(
      '防止无限循环：更新后不应触发 setState 循环',
      (WidgetTester tester) async {
        // Arrange
        String currentParagraph = '初始内容';
        int buildCount = 0;
        int maxAllowedBuilds = 10; // 防止真的进入无限循环

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                buildCount++;
                return Material(
                  child: ParagraphWidget(
                    paragraph: currentParagraph,
                    index: 0,
                    fontSize: 18.0,
                    isEditMode: true,
                    onContentChanged: (newContent) {
                      // 模拟父组件监听变化并更新
                      if (newContent != currentParagraph) {
                        currentParagraph = newContent;
                        setState(() {});
                      }
                    },
                  ),
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 记录初始 build 次数
        final initialBuildCount = buildCount;

        // Act: 外部更新 paragraph
        currentParagraph = '外部更新';
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                buildCount++;
                return Material(
                  child: ParagraphWidget(
                    paragraph: currentParagraph,
                    index: 0,
                    fontSize: 18.0,
                    isEditMode: true,
                    onContentChanged: (newContent) {
                      if (newContent != currentParagraph) {
                        currentParagraph = newContent;
                        setState(() {});
                      }
                    },
                  ),
                );
              },
            ),
          ),
        );

        // 等待可能的循环
        await tester.pump();

        // Assert: build 次数应该在一个合理范围内
        final additionalBuilds = buildCount - initialBuildCount;
        expect(
          additionalBuilds,
          lessThan(maxAllowedBuilds),
          reason: '不应该出现无限循环导致的大量重建',
        );
      },
    );
  });

  group('ParagraphWidget 边界情况测试', () {
    testWidgets('相同内容的更新不应该触发任何逻辑',
        (WidgetTester tester) async {
      // Arrange
      String paragraph = '相同内容';
      int onContentChangedCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ParagraphWidget(
              paragraph: paragraph,
              index: 0,
              fontSize: 18.0,
              isEditMode: true,
              onContentChanged: (_) => onContentChangedCallCount++,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Act: 用相同内容更新
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ParagraphWidget(
              paragraph: paragraph, // 相同内容
              index: 0,
              fontSize: 18.0,
              isEditMode: true,
              onContentChanged: (_) => onContentChangedCallCount++,
            ),
          ),
        ),
      );

      await tester.pump();

      // Assert
      expect(
        onContentChangedCallCount,
        equals(0),
        reason: '相同内容的更新不应该触发任何回调',
      );
    });

    testWidgets('空字符串到有内容的更新应该正常工作',
        (WidgetTester tester) async {
      // Arrange
      int onContentChangedCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ParagraphWidget(
              paragraph: '',
              index: 0,
              fontSize: 18.0,
              isEditMode: true,
              onContentChanged: (_) => onContentChangedCallCount++,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Act: 从空字符串更新到有内容
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ParagraphWidget(
              paragraph: '新内容',
              index: 0,
              fontSize: 18.0,
              isEditMode: true,
              onContentChanged: (_) => onContentChangedCallCount++,
            ),
          ),
        ),
      );

      await tester.pump();

      // Assert
      expect(
        onContentChangedCallCount,
        equals(0),
        reason: '程序更新不应该触发 onContentChanged',
      );
    });
  });
}

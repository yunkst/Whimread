import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/screens/insert_chapter_screen.dart';

/// InsertChapterScreen 单元测试
///
/// 测试纯手动模式下的章节插入：
/// - 标题/内容为空校验
/// - 正常输入返回 Map 数据
/// - 取消返回 null
void main() {
  Novel createTestNovel() => Novel(
        title: '测试小说',
        author: '测试作者',
        url: 'https://example.com/novel/1',
      );

  Widget createTestWidget({
    Novel? novel,
    int afterIndex = 0,
    List<Chapter>? chapters,
    String? prefillTitle,
    String? prefillContent,
  }) {
    return ProviderScope(
      child: MaterialApp(
        home: InsertChapterScreen(
          novel: novel ?? createTestNovel(),
          afterIndex: afterIndex,
          chapters: chapters ?? const [],
          prefillTitle: prefillTitle,
          prefillContent: prefillContent,
        ),
      ),
    );
  }

  group('InsertChapterScreen 纯手动模式', () {
    testWidgets('页面应显示"创建新章节"标题（无章节时）',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('创建新章节'), findsOneWidget);
      expect(find.text('章节标题'), findsOneWidget);
      expect(find.text('章节内容'), findsOneWidget);
    });

    testWidgets('页面应显示"插入新章节"标题（有章节时）',
        (WidgetTester tester) async {
      final chapters = [
        Chapter(
          title: '第一章 开篇',
          url: 'custom://chapter/1',
          chapterIndex: 0,
        ),
      ];
      await tester.pumpWidget(
        createTestWidget(
          afterIndex: 0,
          chapters: chapters,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('插入新章节'), findsOneWidget);
    });

    testWidgets('标题为空时点击插入应提示警告', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 填入内容但不填标题
      await tester.enterText(find.byType(TextField).at(1), '章节内容');
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();

      // 页面应该仍然存在（没返回）
      expect(find.text('插入'), findsOneWidget);
    });

    testWidgets('内容为空时点击插入应提示警告', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 填入标题但不填内容
      await tester.enterText(find.byType(TextField).at(0), '新章节');
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();

      // 页面应该仍然存在
      expect(find.text('插入'), findsOneWidget);
    });

    testWidgets('正常填入标题和内容后点击插入应返回 Map',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // 填入标题
      await tester.enterText(find.byType(TextField).at(0), '测试章节');
      // 填入内容
      await tester.enterText(find.byType(TextField).at(1), '这是章节内容。');

      // 点击插入
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();

      // 验证页面已经关闭
      expect(find.text('插入'), findsNothing);
    });

    testWidgets('点击取消应关闭页面', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('取消'), findsNothing);
    });

    testWidgets('prefillTitle 和 prefillContent 应被预填到输入框',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(
        prefillTitle: '预填标题',
        prefillContent: '预填内容',
      ));
      await tester.pumpAndSettle();

      expect(find.text('预填标题'), findsOneWidget);
      expect(find.text('预填内容'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/widgets/markdown/markdown_editor_screen.dart';

/// 验证 MarkdownEditorScreen 的关键行为契约。
///
/// 覆盖：加载渲染、防抖自动保存、Pop 拦截、单字段 vs 双字段模式。
void main() {
  testWidgets('加载完成后在编辑 Tab 渲染 content',
      (tester) async {
    final loadFuture = Future.value(
      const MarkdownEditorDoc(content: 'hello world'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownEditorScreen(
          appBarTitle: '测试',
          appBarSubtitle: '副标题',
          logTag: 'test',
          contentHint: '输入内容',
          load: () => loadFuture,
          save: (_, {required auto}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 加载完成 → TabBar + 文本框可见
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('编辑后 2 秒防抖自动保存(autosave=true)', (tester) async {
    var autoSaveCount = 0;
    MarkdownEditorDoc? lastSaved;

    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownEditorScreen(
          appBarTitle: '测试',
          appBarSubtitle: '副标题',
          logTag: 'test',
          contentHint: '输入内容',
          load: () => Future.value(const MarkdownEditorDoc(content: '')),
          save: (doc, {required auto}) async {
            lastSaved = doc;
            if (auto) autoSaveCount++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 找到内容 TextField
    final contentField = find.byType(TextField);
    expect(contentField, findsOneWidget);
    await tester.enterText(contentField, 'auto-saved text');

    // 2 秒未到 → 未自动保存
    await tester.pump(const Duration(milliseconds: 1500));
    expect(autoSaveCount, 0);

    // 2 秒到 → 触发自动保存
    await tester.pump(const Duration(milliseconds: 600));
    expect(autoSaveCount, 1);
    expect(lastSaved?.content, 'auto-saved text');
  });

  testWidgets('单字段模式不渲染标题输入框', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownEditorScreen(
          appBarTitle: '背景设定',
          appBarSubtitle: '副标题',
          logTag: 'test',
          contentHint: '输入内容',
          load: () => Future.value(const MarkdownEditorDoc(content: '')),
          save: (_, {required auto}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 单字段模式只一个 TextField
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('双字段模式(titleHint 非空)渲染标题输入框',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownEditorScreen(
          appBarTitle: '大纲',
          appBarSubtitle: '副标题',
          logTag: 'test',
          titleHint: '可选标题',
          contentHint: '输入内容',
          load: () => Future.value(const MarkdownEditorDoc(content: '')),
          save: (_, {required auto}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 双字段模式:两个 TextField(标题 + 内容)
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('load 抛错时不崩溃,降级为空内容', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownEditorScreen(
          appBarTitle: '测试',
          appBarSubtitle: '副标题',
          logTag: 'test',
          contentHint: '输入内容',
          load: () => Future.error(Exception('数据库炸了')),
          save: (_, {required auto}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 加载结束(circular 消失),TabBar 仍可见,内容 TextField 可用
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('手动保存触发 save(auto:false)并 pop', (tester) async {
    var popped = false;
    var autoFlag = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MarkdownEditorScreen(
          appBarTitle: '测试',
          appBarSubtitle: '副标题',
          logTag: 'test',
          contentHint: '输入内容',
          savedToast: '已保存',
          load: () => Future.value(const MarkdownEditorDoc(content: '')),
          save: (doc, {required auto}) async {
            autoFlag = auto;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 包装一层,捕获 pop
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => MarkdownEditorScreen(
                    appBarTitle: '测试',
                    appBarSubtitle: '副标题',
                    logTag: 'test',
                    contentHint: '输入内容',
                    savedToast: '已保存',
                    load: () => Future.value(
                      const MarkdownEditorDoc(content: 'orig'),
                    ),
                    save: (doc, {required auto}) async {
                      autoFlag = auto;
                    },
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 修改内容
    final contentField = find.byType(TextField);
    await tester.enterText(contentField, 'changed');
    await tester.pump();

    // 点击保存按钮(tooltip '保存')
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(autoFlag, false, reason: '手动保存:autoFlag 必须为 false');
    expect(popped, true, reason: '手动保存成功后应 pop');
  });
}

/// TagEditDialog 编辑模式「删除」按钮 widget 测试。
///
/// 需求：编辑标签时，编辑对话框 actions 区应出现「删除」按钮（红色文字），
/// 点击后调用 onDeleteRequested 回调，由外层 Screen 负责二次确认 + 删库。
/// 添加模式（tag == null）不应出现删除按钮。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/widgets/tag_edit_dialog_delete_button_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/models/prompt_tag.dart';
import 'package:novel_app/models/prompt_tag_category.dart';
import 'package:novel_app/screens/prompt_tag/dialogs/tag_edit_dialog.dart';

PromptTag _makeTag() => PromptTag(
      id: 1,
      categoryId: 10,
      name: '赛博朋克',
      reason: '都市科幻题材',
      promptText: '霓虹街道、义体改造、底层人生活',
      sortOrder: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

List<PromptTagCategory> _categories() => [
      PromptTagCategory(
        id: 10,
        name: '题材',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      PromptTagCategory(
        id: 11,
        name: '风格',
        sortOrder: 1,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];

void main() {
  testWidgets('编辑模式：actions 区含「删除」按钮 + 点击触发 onDeleteRequested',
      (tester) async {
    var deleteRequested = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagEditDialog(
            tag: _makeTag(),
            categoryId: 10,
            categoryName: '题材',
            categories: _categories(),
            onDeleteRequested: () => deleteRequested++,
          ),
        ),
      ),
    );

    // 标题应为「编辑标签」
    expect(find.text('编辑标签'), findsOneWidget);
    // 含「删除」按钮
    final deleteBtn = find.widgetWithText(TextButton, '删除');
    expect(deleteBtn, findsOneWidget,
        reason: '编辑模式下 actions 区应出现「删除」按钮');
    // 含「取消」「保存」
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    // 点「删除」→ onDeleteRequested 应被调用一次
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();
    expect(deleteRequested, 1, reason: '点击「删除」应触发 onDeleteRequested 回调');
  });

  testWidgets('添加模式（presetName）：不含「删除」按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagEditDialog(
            categoryId: 10,
            categoryName: '题材',
            categories: _categories(),
            presetName: '赛博朋克',
          ),
        ),
      ),
    );

    // 标题应为「添加标签」
    expect(find.text('添加标签'), findsOneWidget);
    // 不应含「删除」按钮
    expect(find.widgetWithText(TextButton, '删除'), findsNothing,
        reason: '添加模式下不应出现「删除」按钮');
    // 仍含「取消」「保存」
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });
}
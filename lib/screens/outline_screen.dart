import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/database_providers.dart';
import '../models/novel.dart';
import '../models/outline.dart';
import '../widgets/markdown/markdown_editor_screen.dart';

/// 大纲展示 / 编辑页
///
/// 一本书对应一份大纲（[Outline]）。薄壳：仅负责把
/// [OutlineRepository] 的读写适配成 [MarkdownEditorScreen] 的回调契约，
/// 编辑 / 预览双 Tab、Markdown 渲染、防抖自动保存、放弃确认等通用行为
/// 全部由 [MarkdownEditorScreen] 承载（与 [BackgroundSettingScreen] 共用）。
///
/// 与背景设定的区别：
/// - 数据来自 `OutlineRepository.getOutlineByNovelUrl`，可能返回 null（尚无大纲）；
/// - 含 [Outline.title] 与 [Outline.content] 两个字段（双字段模式）；
/// - 保存用 `saveOutline`（upsert，存在则更新，不存在则新建）。
class OutlineScreen extends ConsumerWidget {
  final Novel novel;

  const OutlineScreen({required this.novel, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MarkdownEditorScreen(
      appBarTitle: '大纲',
      appBarSubtitle: novel.title,
      logTag: 'outline',
      titleHint: '可选，留空则使用书名',
      titleFallback: novel.title,
      contentHint: '在此输入大纲内容（支持 Markdown 格式）...',
      savedToast: '大纲已保存',
      load: () async {
        final repo = ref.read(outlineRepositoryProvider);
        final outline = await repo.getOutlineByNovelUrl(novel.url);
        return MarkdownEditorDoc(
          title: outline?.title,
          content: outline?.content ?? '',
        );
      },
      save: (doc, {required bool auto}) async {
        final repo = ref.read(outlineRepositoryProvider);
        await repo.saveOutline(Outline(
          novelUrl: novel.url,
          title: doc.title ?? novel.title,
          content: doc.content,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      },
    );
  }
}

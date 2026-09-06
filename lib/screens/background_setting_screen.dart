import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/database_providers.dart';
import '../models/novel.dart';
import '../widgets/markdown/markdown_editor_screen.dart';

/// 背景设定编辑页
///
/// 薄壳：仅负责把 [NovelRepository] 的读写适配成 [MarkdownEditorScreen] 的回调契约，
/// 编辑 / 预览双 Tab、Markdown 渲染、防抖自动保存、放弃确认等通用行为
/// 全部由 [MarkdownEditorScreen] 承载（与 [OutlineScreen] 共用）。
///
/// 加载失败时回退到 [Novel.backgroundSetting]（由 load 闭包内部 try-catch 完成）。
class BackgroundSettingScreen extends ConsumerWidget {
  final Novel novel;

  const BackgroundSettingScreen({
    super.key,
    required this.novel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MarkdownEditorScreen(
      appBarTitle: '背景设定',
      appBarSubtitle: novel.title,
      logTag: 'background',
      contentHint: '在此输入背景设定（支持 Markdown 格式）...',
      emptyText: '暂无内容',
      savedToast: '背景设定已保存',
      load: () async {
        try {
          final repo = ref.read(novelRepositoryProvider);
          final backgroundSetting = await repo.getBackgroundSetting(novel.url);
          return MarkdownEditorDoc(
            content: backgroundSetting ?? novel.backgroundSetting ?? '',
          );
        } catch (_) {
          return MarkdownEditorDoc(content: novel.backgroundSetting ?? '');
        }
      },
      save: (doc, {required bool auto}) async {
        final repo = ref.read(novelRepositoryProvider);
        await repo.updateBackgroundSetting(
          novel.url,
          doc.content.isEmpty ? null : doc.content,
        );
      },
    );
  }
}

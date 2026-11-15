/// 番外列表页（章级 / 小说级两用）
///
/// - 章级（传 [anchorChapterUrl]）：只显示挂载在该章的番外；底部「创建番外」
///   常驻按钮，空态时升级为居中引导。
/// - 小说级（不传）：显示宿主小说的全部番外（含番外的番外），按挂载点
///   分组展示；不提供创建按钮（创建必须选定锚点章，请从章节徽标/
///   阅读器角标进入）。
///
/// 数据源 `sideStorySummariesProvider`（listen sideStorySignalProvider，
/// 创建/删除后自动刷新）。点击卡片进入番外的章节列表页——与主线目录
/// 同一组件，阅读/进度/重排能力全部复用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/side_story_mutation_provider.dart';
import '../core/providers/side_story_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../models/chapter.dart';
import '../models/novel.dart';
import '../models/side_story_summary.dart';
import '../screens/chapter_list_screen_riverpod.dart';
import '../utils/error_helper.dart';
import '../utils/toast_utils.dart';
import '../widgets/common/confirm_dialog.dart';
import '../widgets/common/library_app_bar.dart';
import '../widgets/side_story/side_story_create_sheet.dart';

class SideStoryListScreen extends ConsumerWidget {
  /// 宿主小说（主线或父番外）
  final Novel novel;

  /// 锚点章 URL；null = 小说级视图（全部番外）
  final String? anchorChapterUrl;

  /// 锚点章标题（章级 AppBar 副标题 / 创建弹层展示用）
  final String? anchorChapterTitle;

  const SideStoryListScreen({
    super.key,
    required this.novel,
    this.anchorChapterUrl,
    this.anchorChapterTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChapterLevel = anchorChapterUrl != null;
    final summariesAsync =
        ref.watch(sideStorySummariesProvider(novel.url));
    final summaries =
        summariesAsync.valueOrNull ?? const <SideStorySummary>[];

    return Scaffold(
      appBar: LibraryAppBar(
        title: isChapterLevel ? '本章番外' : '番外列表',
        subtitle: isChapterLevel
            ? '挂载于「${anchorChapterTitle ?? '该章节'}」'
            : novel.title,
        brandMark: '番',
      ),
      body: summariesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('番外列表加载失败：$e', textAlign: TextAlign.center),
          ),
        ),
        data: (_) => _buildBody(context, ref, summaries, isChapterLevel),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<SideStorySummary> summaries,
    bool isChapterLevel,
  ) {
    if (summaries.isEmpty) {
      return _buildEmpty(context, isChapterLevel);
    }

    return Stack(
      children: [
        Column(
          children: [
            if (isChapterLevel)
              _AnchorBanner(
                text:
                    '本章节共挂载 ${summaries.length} 部番外，点击进入阅读',
              ),
            Expanded(
              child: isChapterLevel
                  ? _buildFlatList(context, ref, summaries)
                  : _buildGroupedList(context, ref, summaries),
            ),
            // 小说级底部统计
            if (!isChapterLevel && summaries.isNotEmpty)
              _buildTotalStats(context, summaries),
          ],
        ),
        // 章级：底部常驻创建按钮
        if (isChapterLevel)
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(child: _buildCreateButton(context)),
          ),
      ],
    );
  }

  /// 章级：平铺列表
  Widget _buildFlatList(
    BuildContext context,
    WidgetRef ref,
    List<SideStorySummary> summaries,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
      itemCount: summaries.length,
      itemBuilder: (_, i) => _SideStoryCard(
        summary: summaries[i],
        showAnchor: false,
        onDeleted: () => _deleteSideStory(context, ref, summaries[i]),
      ),
    );
  }

  /// 小说级：按挂载点分组（主线章一组、每部有子番外的番外各一组）
  Widget _buildGroupedList(
    BuildContext context,
    WidgetRef ref,
    List<SideStorySummary> summaries,
  ) {
    // 挂载点 key：'chapter:<url>' 或 'side:<番外url>'
    final groups = <String, List<SideStorySummary>>{};
    for (final s in summaries) {
      final anchorUrl = s.novel.anchorChapterUrl ?? '';
      final anchorNovel = s.novel.anchorNovelUrl ?? '';
      final key = anchorNovel == novel.url
          ? 'chapter:$anchorUrl'
          : 'side:$anchorNovel';
      groups.putIfAbsent(key, () => []).add(s);
    }

    final widgets = <Widget>[];
    // 主线章挂载组在前
    for (final entry in groups.entries) {
      if (entry.key.startsWith('chapter:')) {
        final chapterUrl = entry.key.substring('chapter:'.length);
        final anchorTitle = entry.value.first.anchorChapterTitle;
        widgets.add(_GroupLabel(
          text: anchorTitle != null
              ? '挂载于 $anchorTitle'
              : '挂载于 原章节已移除（$chapterUrl）',
          anchorMissing: anchorTitle == null,
        ));
        widgets.addAll(entry.value
            .map((s) => _SideStoryCard(
                  summary: s,
                  showAnchor: false,
                  onDeleted: () => _deleteSideStory(context, ref, s),
                ))
            );
      }
    }
    // 子番外组（番外套番外）
    for (final entry in groups.entries) {
      if (entry.key.startsWith('side:')) {
        final parentUrl = entry.key.substring('side:'.length);
        // 从汇总里找父番外的标题（父级一定在同一列表中——它挂在本小说
        // 下且被其它番外锚定）；找不到时回退显示 URL
        String? parentTitle;
        for (final s in summaries) {
          if (s.novel.url == parentUrl) {
            parentTitle = s.novel.title;
            break;
          }
        }
        widgets.add(_GroupLabel(
          text: parentTitle != null
              ? '挂载于 番外《$parentTitle》'
              : '挂载于 上级番外（$parentUrl）',
          anchorMissing: parentTitle == null,
        ));
        widgets.addAll(entry.value
            .map((s) => _SideStoryCard(
                  summary: s,
                  showAnchor: true,
                  onDeleted: () => _deleteSideStory(context, ref, s),
                ))
            );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: widgets,
    );
  }

  Widget _buildTotalStats(BuildContext context, List<SideStorySummary> summaries) {
    final totalChapters =
        summaries.fold<int>(0, (sum, s) => sum + s.chapterCount);
    final totalChars = summaries.fold<int>(0, (sum, s) => sum + s.totalChars);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        '共 ${summaries.length} 部番外 · $totalChapters 章 · '
        '${(totalChars / 10000).toStringAsFixed(1)} 万字',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).hintColor),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isChapterLevel) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories,
              size: 52,
              color: Theme.of(context).hintColor.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Text(
            isChapterLevel ? '本章还没有番外' : '这本书还没有番外',
            style: AppTypography.novelTitle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            isChapterLevel
                ? '想为这一章补一段支线往事？\n告诉 AI 你的想法，一篇番外马上成稿。'
                : '在目录页章节徽标或阅读时顶栏角标处\n可以为某一章创建番外。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
          ),
          if (isChapterLevel) ...[
            const SizedBox(height: 22),
            _buildCreateButton(context),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.auto_awesome, size: 18),
      label: const Text('创建番外'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
      ),
      onPressed: () => SideStoryCreateSheet.show(
        context,
        anchorNovel: novel,
        anchorChapter: Chapter(
          title: anchorChapterTitle ?? '该章节',
          url: anchorChapterUrl!,
        ),
      ),
    );
  }

  Future<void> _deleteSideStory(
    BuildContext context,
    WidgetRef ref,
    SideStorySummary summary,
  ) async {
    final novel = summary.novel;
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除番外',
      message: '确定删除番外《${novel.title}》吗？\n'
          '将同时删除其全部 ${summary.chapterCount} 章正文与挂载其上的子番外，不可恢复。',
      confirmText: '删除',
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(sideStoryMutationProvider.notifier)
          .deleteSideStoryTree(
            novel.url,
            anchorNovelUrl: novel.anchorNovelUrl ?? this.novel.url,
          );
      if (!context.mounted) return;
      ToastUtils.showSuccess('已删除番外《${novel.title}》', context: context);
    } catch (e, st) {
      if (!context.mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '删除番外失败',
        error: e,
        stackTrace: st,
      );
    }
  }
}

/// ============================== 子组件 ==============================

/// 锚点提示横幅（章级顶部）
class _AnchorBanner extends StatelessWidget {
  final String text;
  const _AnchorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: context.appColors.agentAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.appColors.agentAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.bookmark,
              size: 15, color: context.appColors.agentAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appColors.agentAccent,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组标签（小说级挂载树）
class _GroupLabel extends StatelessWidget {
  final String text;
  final bool anchorMissing;
  const _GroupLabel({required this.text, this.anchorMissing = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 14, color: Theme.of(context).hintColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: anchorMissing
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).hintColor,
                    fontWeight: FontWeight.w700,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 番外卡片
class _SideStoryCard extends StatelessWidget {
  final SideStorySummary summary;
  final bool showAnchor;
  final VoidCallback onDeleted;

  const _SideStoryCard({
    required this.summary,
    required this.showAnchor,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final novel = summary.novel;
    final readInfo = summary.hasProgress
        ? '已读 ${summary.readCount} 章'
        : '未读';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChapterListScreenRiverpod(novel: novel),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              // 程序化占位封面（番外名首字）
              Container(
                width: 44,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: context.appColors.agentAccent,
                  boxShadow: const [
                    BoxShadow(blurRadius: 5, color: Colors.black26),
                  ],
                ),
                child: Text(
                  novel.title.isEmpty ? '番' : novel.title.characters.first,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      novel.title,
                      style: AppTypography.novelTitle.copyWith(fontSize: 15.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '共 ${summary.chapterCount} 章 · $readInfo'
                      '${summary.totalChars > 0 ? ' · 约 ${(summary.totalChars / 1000).toStringAsFixed(1)} 千字' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                    if (showAnchor && summary.anchorChapterTitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '锚点：${summary.anchorChapterTitle}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.appColors.agentAccent),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: summary.progress,
                        minHeight: 4,
                        backgroundColor:
                            Theme.of(context).dividerColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert,
                    size: 18, color: Theme.of(context).hintColor),
                tooltip: '删除此番外',
                onPressed: onDeleted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

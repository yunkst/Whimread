import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../core/providers/chapter_list_providers.dart';
import '../core/providers/chapter_mutation_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../widgets/agent_chat/agent_floating_button.dart';
import '../services/novel_agent/agent_scenario.dart'; // ScenarioIds：FAB 显式声明 writing 场景
import '../widgets/chapter_list/chapter_list_header.dart';
import '../widgets/chapter_list/chapter_list_item.dart';
import '../widgets/chapter_list/reorderable_chapter_item.dart';
import '../widgets/chapter_list/empty_chapters_view.dart';
import '../constants/chapter_constants.dart';
import '../utils/toast_utils.dart';
import '../widgets/common/library_app_bar.dart';
import 'reader_screen.dart';
import 'chapter_search_screen.dart';
import 'background_setting_screen.dart';
import 'character_list_screen.dart';
import 'outline_screen.dart';
import 'insert_chapter_screen.dart';
import '../core/providers/reading_context_providers.dart';

/// 章节列表页面 - Riverpod版本
///
/// 这是原始 ChapterListScreen 的 Riverpod 包装器
/// 所有状态管理通过 Riverpod Provider 完成
class ChapterListScreenRiverpod extends ConsumerStatefulWidget {
  final Novel novel;

  const ChapterListScreenRiverpod({
    super.key,
    required this.novel,
  });

  @override
  ConsumerState<ChapterListScreenRiverpod> createState() =>
      _ChapterListScreenRiverpodState();
}

class _ChapterListScreenRiverpodState
    extends ConsumerState<ChapterListScreenRiverpod> {
  final ScrollController _scrollController = ScrollController();

  // 标记是否已经设置了监听
  bool _hasSetupListener = false;

  // 标记是否已经自动滚动到上次阅读位置
  bool _hasScrolledToLastRead = false;

  @override
  void initState() {
    super.initState();
    // 设置当前阅读上下文
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(readingContextProvider.notifier).state = ReadingContext(
        novelTitle: widget.novel.title,
        novelUrl: widget.novel.url,
      );
    });
  }

  @override
  void deactivate() {
    // 离开页面时清除 Agent 阅读上下文。
    //
    // 两难:
    // - 同步修改会触发 Riverpod "Tried to modify a provider while the
    //   widget tree was building"(deactivate 在 _InactiveElements 重建链
    //   中触发,属于 build 阶段);
    // - 直接 Future.microtask 又可能跨过 dispose,触发 Riverpod
    //   "_assertNotDisposed" 崩溃(Bad state: Cannot use "ref" after the
    //   widget was disposed)。
    //
    // 解法:Future.microtask 把修改推到 build 阶段之后 + mounted 兜底,
    // widget 已 dispose 时跳过(ref 已失效)。读取 mounted 不经过 ref,
    // 不会触发 _assertNotDisposed。
    Future.microtask(() {
      if (!mounted) return;
      ref.read(readingContextProvider.notifier).state = const ReadingContext();
    });
    super.deactivate();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 监听预加载进度
  void _listenToPreloadProgress() {
    ref.listen(
      preloadProgressProvider(widget.novel),
      (previous, next) {
        next.when(
          data: (update) {
            if (update.chapterUrl != null) {
              // 更新特定章节的缓存状态
              ref
                  .read(chapterListProvider(widget.novel).notifier)
                  .updateChapterCacheStatus(update.chapterUrl!, true);
            }
          },
          loading: () {},
          error: (_, __) {},
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 设置监听（只设置一次）
    if (!_hasSetupListener) {
      _hasSetupListener = true;
      _listenToPreloadProgress();
    }

    final state = ref.watch(chapterListProvider(widget.novel));
    final notifier = ref.read(chapterListProvider(widget.novel).notifier);

    // 首次加载完成时，自动滚动到上次阅读位置（只执行一次）
    // 修复: 使用-1作为未加载的默认值，避免异步加载时序问题
    if (!_hasScrolledToLastRead &&
        state.chapters.isNotEmpty &&
        state.lastReadChapterIndex >= 0) {
      _hasScrolledToLastRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLastReadChapter();
      });
    }

    return AgentFloatingShell(
      scenarioId: ScenarioIds.writing,
      child: Scaffold(
        appBar: LibraryAppBar(
          title: widget.novel.title,
          actions: [
            _buildReorderButton(state, notifier),
            _buildSearchButton(),
            _buildPopupMenu(state, notifier, context),
          ],
        ),
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.errorMessage.isNotEmpty
                ? _buildErrorView(state, notifier)
                : Column(
                    children: [
                      ChapterListHeader(
                        novel: widget.novel,
                        chapterCount: state.chapters.length,
                        cachedCount: state.cachedCount,
                      ),
                      const Divider(),
                      Expanded(
                        child: state.chapters.isEmpty
                            ? EmptyChaptersView(
                                novel: widget.novel,
                                onCreateChapter: () =>
                                    _showInsertChapterDialog(0),
                                onLoadFromSource: () =>
                                    notifier.refreshChapters(context),
                              )
                            : state.isReorderingMode
                                ? _buildReorderableChapterList(state, notifier)
                                : _buildNormalChapterList(state),
                      ),
                      // 只在非重排模式、有章节且总页数大于1时显示分页控制栏
                      if (!state.isReorderingMode &&
                          state.chapters.isNotEmpty &&
                          state.totalPages > 1)
                        _buildPaginationControl(state, notifier),
                    ],
                  ),
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(ChapterListState state, ChapterList notifier) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            state.errorMessage,
            style: AppTypography.bodyProse.copyWith(
              fontSize: 15,
              color: context.appColors.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => notifier.refreshChapters(context),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 构建重排按钮
  Widget _buildReorderButton(ChapterListState state, ChapterList notifier) {
    if (state.isReorderingMode) {
      return IconButton(
        icon: const Icon(Icons.check),
        onPressed: () {
          notifier.exitReorderingMode();
          ToastUtils.show('已退出重排模式');
        },
        tooltip: '完成重排',
        style: IconButton.styleFrom(
          backgroundColor: context.appColors.success,
          foregroundColor: Theme.of(context).colorScheme.surface,
        ),
      );
    } else {
      return IconButton(
        icon: const Icon(Icons.reorder),
        onPressed: () => notifier.toggleReorderingMode(),
        tooltip: '重排章节',
      );
    }
  }

  /// 构建搜索按钮
  Widget _buildSearchButton() {
    return IconButton(
      icon: const Icon(Icons.search),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChapterSearchScreen(novel: widget.novel),
          ),
        );
      },
      tooltip: '搜索章节内容',
    );
  }

  /// 构建弹出菜单
  Widget _buildPopupMenu(
    ChapterListState state,
    ChapterList notifier,
    BuildContext context,
  ) {
    final isCustomNovel = widget.novel.url.startsWith('custom://');

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'toggle_bookmark':
            _handleToggleBookshelf(notifier);
            break;
          case 'clear_cache':
            _showClearCacheDialog(notifier);
            break;
          case 'refresh':
            notifier.refreshChapters(context);
            break;
          case 'background_setting':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BackgroundSettingScreen(
                  novel: widget.novel,
                ),
              ),
            );
            break;
          case 'characters':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CharacterListScreen(
                  novel: widget.novel,
                ),
              ),
            );
            break;
          case 'outline':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OutlineScreen(
                  novel: widget.novel,
                ),
              ),
            );
            break;
        }
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            value: 'toggle_bookmark',
            child: Row(
              children: [
                Icon(state.isInBookshelf
                    ? Icons.bookmark
                    : Icons.bookmark_border),
                const SizedBox(width: 8),
                Text(state.isInBookshelf ? '移出书架' : '加入书架'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'clear_cache',
            child: Row(
              children: [
                Icon(Icons.clear_all, color: context.appColors.warning),
                SizedBox(width: 8),
                Text('清除缓存'),
              ],
            ),
          ),
          if (!isCustomNovel)
            const PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(Icons.refresh),
                  SizedBox(width: 8),
                  Text('刷新章节'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'background_setting',
            child: Row(
              children: [
                Icon(Icons.info_outline),
                SizedBox(width: 8),
                Text('背景设定'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'characters',
            child: Row(
              children: [
                Icon(Icons.people_outline),
                SizedBox(width: 8),
                Text('人物卡'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'outline',
            child: Row(
              children: [
                Icon(Icons.description_outlined),
                SizedBox(width: 8),
                Text('大纲'),
              ],
            ),
          ),
        ];
      },
    );
  }

  /// 构建正常的章节列表
  Widget _buildNormalChapterList(ChapterListState state) {
    final pageChapters = _getCurrentPageChapters(state);

    return ListView.builder(
      controller: _scrollController,
      itemCount: pageChapters.length,
      itemBuilder: (context, index) {
        final chapter = pageChapters[index];
        // 计算在全部章节中的实际索引
        final globalIndex =
            (state.currentPage - 1) * ChapterConstants.chaptersPerPage + index;
        final isLastRead = globalIndex == state.lastReadChapterIndex;
        final isUserChapter = chapter.isUserInserted;

        return ChapterListItem(
          chapter: chapter,
          isLastRead: isLastRead,
          isUserChapter: isUserChapter,
          isCached: chapter.isCached,
          isRead: chapter.isRead,
          onTap: () => _navigateToReader(chapter, state),
          onLongPress: () => ref
              .read(chapterListProvider(widget.novel).notifier)
              .toggleReorderingMode(),
          onInsert: () => _showInsertChapterDialog(index),
          onDelete: chapter.isUserInserted
              ? () => _showDeleteChapterDialog(chapter, index)
              : null,
        );
      },
    );
  }

  /// 构建可重排的章节列表
  Widget _buildReorderableChapterList(
    ChapterListState state,
    ChapterList notifier,
  ) {
    return ReorderableListView.builder(
      itemCount: state.chapters.length,
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) =>
          notifier.reorderChapters(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final chapter = state.chapters[index];
        final isLastRead = index == state.lastReadChapterIndex;
        final isUserChapter = chapter.isUserInserted;

        return ReorderableChapterListItem(
          key: ValueKey(chapter.url),
          chapter: chapter,
          index: index,
          isLastRead: isLastRead,
          isUserChapter: isUserChapter,
          isCached: chapter.isCached,
          isRead: chapter.isRead,
        );
      },
    );
  }

  /// 构建分页控制栏
  Widget _buildPaginationControl(ChapterListState state, ChapterList notifier) {
    final colors = context.appColors;
    final colorScheme = Theme.of(context).colorScheme;

    final isFirstPage = state.currentPage <= 1;
    final isLastPage = state.currentPage >= state.totalPages;

    // 次级按钮（首页 / 末页）：小图标 + 浅色
    Widget buildSecondaryButton({
      required IconData icon,
      required VoidCallback? onPressed,
      required String tooltip,
    }) {
      return IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
        padding: EdgeInsets.zero,
        color: colorScheme.onSurfaceVariant,
        disabledColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      );
    }

    // 主按钮（上一页 / 下一页）：圆形琥珀色背景
    Widget buildPrimaryButton({
      required IconData icon,
      required VoidCallback? onPressed,
      required String tooltip,
    }) {
      final enabled = onPressed != null;
      return Tooltip(
        message: tooltip,
        child: Material(
          color: enabled
              ? colors.agentAccent
              : colors.agentAccent.withValues(alpha: 0.3),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 36,
              width: 36,
              child: Icon(
                icon,
                size: 22,
                color: colors.agentOnBrand,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 首页按钮
            buildSecondaryButton(
              icon: Icons.first_page,
              onPressed:
                  isFirstPage ? null : () => notifier.goToPage(1),
              tooltip: '首页',
            ),
            const SizedBox(width: 4),
            // 上一页按钮（主按钮）
            buildPrimaryButton(
              icon: Icons.chevron_left,
              onPressed: isFirstPage
                  ? null
                  : () => notifier.goToPage(state.currentPage - 1),
              tooltip: '上一页',
            ),
            // 页码显示
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '第 ${state.currentPage} / ${state.totalPages} 页',
                style: AppTypography.metaItalic.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 下一页按钮（主按钮）
            buildPrimaryButton(
              icon: Icons.chevron_right,
              onPressed: isLastPage
                  ? null
                  : () => notifier.goToPage(state.currentPage + 1),
              tooltip: '下一页',
            ),
            const SizedBox(width: 4),
            // 末页按钮
            buildSecondaryButton(
              icon: Icons.last_page,
              onPressed: isLastPage
                  ? null
                  : () => notifier.goToPage(state.totalPages),
              tooltip: '末页',
            ),
          ],
        ),
      ),
    );
  }

  /// 获取当前页章节
  List<Chapter> _getCurrentPageChapters(ChapterListState state) {
    if (state.chapters.isEmpty) return [];

    // 修复：计算最大页数，确保 currentPage 不超过实际页数
    final maxPage = (state.chapters.length / ChapterConstants.chaptersPerPage).ceil();
    final currentPage = state.currentPage.clamp(1, maxPage);

    final startIndex =
        (currentPage - 1) * ChapterConstants.chaptersPerPage;
    final endIndex = (startIndex + ChapterConstants.chaptersPerPage)
        .clamp(0, state.chapters.length);

    // 防御性检查：确保 startIndex < endIndex
    if (startIndex >= endIndex) {
      return [];
    }

    return state.chapters.sublist(startIndex, endIndex);
  }

  /// 切换书架状态
  Future<void> _handleToggleBookshelf(ChapterList notifier) async {
    try {
      await notifier.toggleBookshelf();
      if (mounted) {
        final newState = ref.read(chapterListProvider(widget.novel));
        ToastUtils.show(newState.isInBookshelf ? '已添加到书架' : '已从书架移除');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('操作失败: $e');
      }
    }
  }

  /// 显示清除缓存对话框
  Future<void> _showClearCacheDialog(ChapterList notifier) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除该小说的所有缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await notifier.clearCache();
                if (mounted) {
                  ToastUtils.show('缓存已清除');
                }
              } catch (e) {
                if (mounted) {
                  ToastUtils.showError('清除缓存失败: $e');
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 导航到阅读页面
  Future<void> _navigateToReader(
      Chapter chapter, ChapterListState state) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(
          novel: widget.novel,
          chapter: chapter,
          chapters: state.chapters,
        ),
      ),
    );

    // 返回时重新加载上次阅读位置并跳转
    if (mounted) {
      await ref
          .read(chapterListProvider(widget.novel).notifier)
          .reloadLastReadChapter();
      // 刷新章节缓存标记：阅读期间被缓存的章节需要更新 isCached
      // ReaderContentController 直接写入 chapter_cache 时不经过 PreloadService，
      // 因此返回时需主动从本地数据库重新读取最新状态
      await ref
          .read(chapterListProvider(widget.novel).notifier)
          .refreshCacheStatus();
      // 滚动到上次阅读位置
      _scrollToLastReadChapter();
    }
  }

  /// 滚动到上次阅读章节
  void _scrollToLastReadChapter() {
    final state = ref.read(chapterListProvider(widget.novel));
    if (state.lastReadChapterIndex < 0 || state.chapters.isEmpty) {
      return;
    }

    // 1. 计算目标页码
    const chaptersPerPage = ChapterConstants.chaptersPerPage;
    final targetPage = (state.lastReadChapterIndex ~/ chaptersPerPage) + 1;

    // 2. 如果目标页不是当前页，先跳转到目标页
    if (targetPage != state.currentPage) {
      ref.read(chapterListProvider(widget.novel).notifier).goToPage(targetPage);
    }

    // 3. 延迟滚动，确保页面跳转和ListView重建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;

        // 4. 计算目标章节在目标页中的索引
        final startIndex = (targetPage - 1) * chaptersPerPage;
        final indexInPage = state.lastReadChapterIndex - startIndex;

        // 5. 计算滚动位置
        final itemHeight = 56.0;
        final targetOffset = indexInPage * itemHeight;

        // 获取可视区域高度
        final viewportHeight = _scrollController.position.viewportDimension;
        final adjustedOffset = (targetOffset - viewportHeight * 0.25)
            .clamp(0.0, _scrollController.position.maxScrollExtent);

        // 6. 执行滚动动画
        _scrollController.animateTo(
          adjustedOffset,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  /// 显示插入章节对话框
  Future<void> _showInsertChapterDialog(int afterIndex) async {
    final state = ref.read(chapterListProvider(widget.novel));

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => InsertChapterScreen(
          novel: widget.novel,
          afterIndex: afterIndex,
          chapters: state.chapters,
        ),
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    final title = result['title'] as String;
    final content = result['content'] as String;
    final insertIndex = state.chapters.isEmpty ? 0 : afterIndex + 1;

    try {
      // 走 ChapterMutationNotifier 收口：单事务 shift+insert + bump signal
      // 触发章节列表软刷新
      await ref.read(chapterMutationProvider.notifier).createChapter(
            novelUrl: widget.novel.url,
            title: title,
            content: content,
            insertIndex: insertIndex,
          );

      // 刷新章节列表
      if (mounted) {
        await ref
            .read(chapterListProvider(widget.novel).notifier)
            .refreshChapters(context);
      }

      if (mounted) {
        final newState = ref.read(chapterListProvider(widget.novel));

        // 查找刚插入的章节
        final insertedChapter = newState.chapters.firstWhere(
          (c) => c.title == title,
          orElse: () => newState.chapters.isNotEmpty
              ? newState.chapters[insertIndex]
              : newState.chapters.last,
        );

        // 跳转到阅读页面
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => ReaderScreen(
              novel: widget.novel,
              chapter: insertedChapter,
              chapters: newState.chapters,
            ),
          ),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('插入章节失败: $e');
      }
    }
  }

  /// 显示删除章节确认对话框
  Future<void> _showDeleteChapterDialog(
    Chapter chapter,
    int index,
  ) async {
    final state = ref.read(chapterListProvider(widget.novel));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除章节'),
        content: Text(
          '确定要删除章节"${chapter.title}"吗？\n\n'
          '共有 ${state.chapters.length} 个章节，删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteChapter(chapter);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 删除章节
  Future<void> _deleteChapter(Chapter chapter) async {
    try {
      // 显示加载提示
      if (mounted) {
        ToastUtils.show('正在删除章节...');
      }

      // 走 ChapterMutationNotifier 收口：单事务 delete+reindex + bump signal
      // 触发章节列表软刷新
      await ref
          .read(chapterMutationProvider.notifier)
          .deleteChapter(widget.novel.url, chapter.url);

      // 重新加载章节列表
      if (mounted) {
        await ref
            .read(chapterListProvider(widget.novel).notifier)
            .refreshChapters(context);
      }

      // 显示成功提示
      if (mounted) {
        ToastUtils.showSuccess('章节删除成功');
      }
    } catch (e) {
      // 显示错误提示
      if (mounted) {
        ToastUtils.showError('删除章节失败: $e');
      }
    }
  }
}

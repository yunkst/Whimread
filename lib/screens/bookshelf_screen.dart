import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/toast_utils.dart';
import '../models/novel.dart';
import '../services/logger_service.dart';
import '../services/image_picker_service.dart';
import '../services/media/media_proxy.dart';
import '../services/media/media_types.dart';
import '../utils/error_helper.dart';
import '../widgets/bookshelf_selector.dart';
import '../widgets/common/common_widgets.dart';
import '../widgets/empty_states/empty_bookshelf.dart';
import '../widgets/novel/novel_cover.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../screens/chapter_list_screen_riverpod.dart';
import '../screens/reader_screen.dart';
import '../core/providers/bookshelf_providers.dart';
import '../core/providers/bookshelf_mutation_provider.dart';
import '../core/providers/database_providers.dart';
import '../core/providers/service_providers.dart';
import '../core/providers/webview_providers.dart';
import '../dialogs/novel_edit_dialog.dart';
import '../models/site_script.dart';
import '../widgets/site_bookshelf_refresh_sheet.dart';

class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends ConsumerState<BookshelfScreen> {
  /// 弹出「刷新网站书架」域名选择 sheet
  ///
  /// 仅传入有 bookshelf_js 缓存脚本的域名（按钮可见性已保证非空，但保险起见
  /// 再过滤一次；空列表直接 return 不弹空 sheet）。
  void _showRefreshSheet(BuildContext context) {
    final scripts =
        ref.read(siteScriptListProvider).valueOrNull ?? const <SiteScript>[];
    final candidates =
        scripts.where((s) => s.hasBookshelfJs).toList(growable: false);
    if (candidates.isEmpty) return;
    showSiteBookshelfRefreshSheet(context, candidates);
  }

  Future<void> _removeFromBookshelf(Novel novel) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '确认删除',
      message: '确定要从书架移除《${novel.title}》吗？',
      confirmText: '删除',
    );

    if (confirmed == true) {
      try {
        // 从数据库中删除小说（这会删除bookshelf表中的记录）
        // 写路径经 BookshelfMutationNotifier，自动 invalidate bookshelfNovelsProvider
        await ref
            .read(bookshelfMutationProvider.notifier)
            .removeNovel(novel.url);
        if (mounted) {
          ToastUtils.showSuccess('已从书架移除', context: context);
        }
      } catch (e, stackTrace) {
        if (!mounted) return;
        ErrorHelper.showErrorWithLog(
          context,
          '从书架移除失败',
          error: e,
          stackTrace: stackTrace,
          category: LogCategory.database,
          tags: ['bookshelf', 'remove', 'failed'],
        );
      }
    }
  }

  /// 编辑小说书名
  Future<void> _editNovelTitle(Novel novel) async {
    await NovelEditDialog.show(
      context: context,
      originalTitle: novel.title,
      onConfirm: (newTitle) async {
        try {
          // 写路径经 BookshelfMutationNotifier，自动 invalidate bookshelfNovelsProvider
          await ref
              .read(bookshelfMutationProvider.notifier)
              .updateTitle(novel.url, newTitle);
          if (mounted) {
            ToastUtils.showSuccess('书名修改成功', context: context);
          }
        } catch (e, stackTrace) {
          if (!mounted) return;
          ErrorHelper.showErrorWithLog(
            context,
            '修改书名失败',
            error: e,
            stackTrace: stackTrace,
            category: LogCategory.database,
            tags: ['bookshelf', 'edit_title', 'failed'],
          );
        }
      },
    );
  }

  /// 从相册选图、裁剪并设为小说封面。
  ///
  /// 复用 [ImagePickerService]（相册选图 + 自由裁剪）+ [MediaProxy.upload]
  /// 生成 `local_` mediaId，写入 bookshelf.coverMediaId，并刷新书架列表。
  /// 用户在选图/裁剪任一步取消则静默返回；图片 >10MB 提示。
  ///
  /// 注意：用 url 定位（书架页 Novel 不含 id，避免 novelId==null 静默失败）。
  Future<void> _setNovelCover(Novel novel) async {
    Uint8List? bytes;
    try {
      bytes = await ImagePickerService().pickAndCrop();
    } on ImageTooLargeException catch (e) {
      if (!mounted) return;
      ToastUtils.showError('$e', context: context);
      return;
    } catch (e, stackTrace) {
      if (!mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '选择图片失败',
        error: e,
        stackTrace: stackTrace,
        category: LogCategory.database,
        tags: ['bookshelf', 'cover', 'pick', 'failed'],
      );
      return;
    }
    if (bytes == null) return; // 用户取消

    try {
      final mediaId =
          await ref.read(mediaProxyProvider).upload(bytes, MediaKind.image);
      // 写路径经 BookshelfMutationNotifier，自动 invalidate bookshelfNovelsProvider
      await ref
          .read(bookshelfMutationProvider.notifier)
          .updateCoverMediaId(novel.url, mediaId);
      if (mounted) {
        ToastUtils.showSuccess('封面已设置', context: context);
      }
      LoggerService.instance.i(
        '设置封面: novelUrl=${novel.url} mediaId=$mediaId',
        category: LogCategory.database,
        tags: ['bookshelf', 'cover', 'set'],
      );
    } catch (e, stackTrace) {
      if (!mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '设置封面失败',
        error: e,
        stackTrace: stackTrace,
        category: LogCategory.database,
        tags: ['bookshelf', 'cover', 'set', 'failed'],
      );
    }
  }

  /// 删除小说封面（仅清空 coverMediaId，不删除 media 文件）。
  ///
  /// 与 set_novel_cover 工具的 mediaId=null 语义一致——media 是共享资源，
  /// 同一张图也可能被章节插图/角色头像引用，故不在此级联删除文件。
  ///
  /// 用 url 定位（书架页 Novel 不含 id，避免 novelId==null 静默失败）。
  Future<void> _removeNovelCover(Novel novel) async {
    try {
      // 写路径经 BookshelfMutationNotifier，自动 invalidate bookshelfNovelsProvider
      await ref
          .read(bookshelfMutationProvider.notifier)
          .removeCoverMediaId(novel.url);
      if (mounted) {
        ToastUtils.showSuccess('封面已删除', context: context);
      }
      LoggerService.instance.i(
        '删除封面: novelUrl=${novel.url}',
        category: LogCategory.database,
        tags: ['bookshelf', 'cover', 'remove'],
      );
    } catch (e, stackTrace) {
      if (!mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '删除封面失败',
        error: e,
        stackTrace: stackTrace,
        category: LogCategory.database,
        tags: ['bookshelf', 'cover', 'remove', 'failed'],
      );
    }
  }

  /// 继续阅读 - 直接打开上次阅读的章节
  ///
  /// [novel] 要阅读的小说
  Future<void> _continueReading(Novel novel) async {
    try {
      // 1. 从数据库重新查询最新的阅读进度(修复缓存问题)
      // 不使用缓存的novel.lastReadChapterIndex,而是从数据库实时查询
      final novelRepository = ref.read(novelRepositoryProvider);
      final lastChapterIndex =
          await novelRepository.getLastReadChapter(novel.url);

      if (lastChapterIndex < 0) {
        if (mounted) {
          ToastUtils.showWarning('暂无阅读记录', context: context);
        }
        return;
      }

      // 2. 使用 ChapterLoader 加载章节列表
      final chapterLoader = ref.read(chapterLoaderProvider);
      final chapters = await chapterLoader.loadChapters(novel.url);

      // 3. 检查章节列表
      if (chapters.isEmpty) {
        if (mounted) {
          ToastUtils.showWarning('章节列表为空', context: context);
        }
        return;
      }

      // 4. 验证索引是否越界
      if (lastChapterIndex >= chapters.length) {
        if (mounted) {
          ToastUtils.showWarning(
            '上次阅读的章节不存在，已跳转到第一章',
            context: context,
          );
        }
        // 跳转到第一章
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReaderScreen(
                novel: novel,
                chapter: chapters.first,
                chapters: chapters,
              ),
            ),
          );
        }
        return;
      }

      // 5. 直接打开阅读器
      final targetChapter = chapters[lastChapterIndex];
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReaderScreen(
              novel: novel,
              chapter: targetChapter,
              chapters: chapters,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '打开章节失败',
        error: e,
        stackTrace: stackTrace,
        category: LogCategory.ui,
        tags: ['bookshelf', 'continue_reading', 'failed'],
      );
    }
  }

  /// 显示小说操作菜单（编辑/封面/移除）
  ///
  /// 新设计：书架分类由"小说来源"派生（URL 前缀），
  /// 不再提供"移动到书架/复制到书架/加入书架"等分类调整入口。
  void _showNovelMenu(Novel novel) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final colors = sheetCtx.appColors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '《${novel.title}》',
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 16,
                      color: colors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: colors.info),
                title: const Text('编辑书名'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _editNovelTitle(novel);
                },
              ),
              ListTile(
                leading: Icon(Icons.image_outlined, color: colors.info),
                title: const Text('设置封面'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _setNovelCover(novel);
                },
              ),
              if (novel.coverMediaId != null)
                ListTile(
                  leading: Icon(Icons.hide_image_outlined, color: colors.chatHintText),
                  title: const Text('删除封面'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _removeNovelCover(novel);
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: colors.error),
                title: const Text('从书架移除'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _removeFromBookshelf(novel);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookshelfAsync = ref.watch(bookshelfNovelsProvider);
    final cacheStats = ref.watch(bookshelfCacheStatsProvider).valueOrNull;
    final colors = context.appColors;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '我的书架',
                    style: AppTypography.shelfTitle.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Midnight Library',
                    style: AppTypography.metaItalic.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () {
              // 搜索入口暂沿用浏览器；后续可接入书架内搜索
              ToastUtils.showInfo('在浏览器中搜索并加入书架', context: context);
            },
          ),
          // 刷新网站书架：仅当任一域名有 bookshelf_js 缓存脚本时显示
          // （脚本存在性感知由 siteScriptListProvider 同步加载所有 SiteScript，
          // 此处仅读取 .valueOrNull 避免在 widget build 阶段主动 await DB，
          // 减少 widget 测试的 pending-Timer 风险）。
          Consumer(
            builder: (context, ref, _) {
              final scripts =
                  ref.watch(siteScriptListProvider).valueOrNull ?? const [];
              final hasBookshelfScript =
                  scripts.any((SiteScript s) => s.hasBookshelfJs);
              if (!hasBookshelfScript) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.cloud_sync_outlined),
                tooltip: '刷新网站书架',
                onPressed: () => _showRefreshSheet(context),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 书架分类切换（顶部 TabBar，单步直达）
          const BookshelfTabBar(),
          // 书架内容
          Expanded(
            child: bookshelfAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: colors.error,
                    ),
                    const SizedBox(height: 16),
                    Text('加载失败: $error'),
                  ],
                ),
              ),
              data: (bookshelf) {
                if (bookshelf.isEmpty) {
                  return const EmptyBookshelfView();
                }

                final totalCached = cacheStats?.values.fold<int>(
                      0,
                      (s, v) => s + v.cached,
                    ) ??
                    0;
                final totalChapters = cacheStats?.values.fold<int>(
                      0,
                      (s, v) => s + v.total,
                    ) ??
                    0;

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(bookshelfNovelsProvider);
                    ref.invalidate(bookshelfCacheStatsProvider);
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _ShelfMetaBar(
                          count: bookshelf.length,
                          cached: totalCached,
                          total: totalChapters,
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.58,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final novel = bookshelf[index];
                              final stats = cacheStats?[novel.url];
                              final total = stats?.total ?? 0;
                              final cached = stats?.cached ?? 0;
                              return _NovelCard(
                                novel: novel,
                                totalChapters: total,
                                cachedChapters: cached,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ChapterListScreenRiverpod(
                                        novel: novel,
                                      ),
                                    ),
                                  );
                                },
                                onContinue: () => _continueReading(novel),
                                onMenu: () => _showNovelMenu(novel),
                              );
                            },
                            childCount: bookshelf.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 书架元信息条 · 馆藏数 / 缓存进度
class _ShelfMetaBar extends StatelessWidget {
  const _ShelfMetaBar({
    required this.count,
    required this.cached,
    required this.total,
  });

  final int count;
  final int cached;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          _MetaChip(
            icon: Icons.menu_book_outlined,
            label: '馆藏',
            value: '$count',
            color: colors.agentAccent,
          ),
          const SizedBox(width: 14),
          _MetaChip(
            icon: Icons.cloud_download_outlined,
            label: '已缓存',
            value: total > 0 ? '$cached / $total' : '—',
            color: colors.success,
          ),
          const Spacer(),
          Text(
            '长按管理',
            style: AppTypography.metaItalic.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// 小说卡片 · 封面网格单元
class _NovelCard extends StatelessWidget {
  const _NovelCard({
    required this.novel,
    required this.totalChapters,
    required this.cachedChapters,
    required this.onTap,
    required this.onContinue,
    required this.onMenu,
  });

  final Novel novel;
  final int totalChapters;
  final int cachedChapters;
  final VoidCallback onTap;
  final VoidCallback onContinue;
  final VoidCallback onMenu;

  bool get _hasReadingRecord =>
      novel.lastReadChapterIndex != null && novel.lastReadChapterIndex! > 0;

  double get _readPercent {
    if (!_hasReadingRecord || totalChapters <= 0) return 0.0;
    final v = novel.lastReadChapterIndex! / totalChapters;
    if (v < 0) return 0.0;
    if (v > 1) return 1.0;
    return v;
  }

  double get _cachePercent {
    if (totalChapters <= 0) return 0.0;
    final v = cachedChapters / totalChapters;
    if (v < 0) return 0.0;
    if (v > 1) return 1.0;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    final isOriginal = novel.url.startsWith('custom://');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMenu,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 封面 · 外层 InkWell 已处理 onLongPress，此处不重复绑定
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: NovelCover(
                        novel: novel,
                        isReading: _hasReadingRecord,
                        isOriginal: isOriginal,
                      ),
                    ),
                    // 右上 · 更多操作（封面内浮层固定黑白：封面恒为深色渐变，不随主题变）
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: onMenu,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.more_horiz,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 标题
              Text(
                novel.title,
                style: AppTypography.novelTitle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // 作者
              Text(
                novel.author,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // 双进度：阅读 + 缓存
              if (totalChapters > 0)
                _DualProgress(
                  readPercent: _readPercent,
                  cachePercent: _cachePercent,
                )
              else
                Text(
                  '未获取章节',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.chatHintText,
                    fontSize: 11,
                  ),
                ),
              // 继续阅读按钮
              if (_hasReadingRecord) ...[
                const SizedBox(height: 8),
                _ContinueButton(onPressed: onContinue),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 双进度条 · 阅读进度（琥珀）+ 缓存进度（苔绿）
class _DualProgress extends StatelessWidget {
  const _DualProgress({
    required this.readPercent,
    required this.cachePercent,
  });

  final double readPercent;
  final double cachePercent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    final trackColor = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 阅读进度
        Row(
          children: [
            Text(
              '读',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: colors.agentAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: readPercent,
                  minHeight: 3,
                  backgroundColor: trackColor,
                  valueColor: AlwaysStoppedAnimation(colors.agentAccent),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(readPercent * 100).round()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 缓存进度
        Row(
          children: [
            Text(
              '缓',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: colors.success,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: cachePercent,
                  minHeight: 3,
                  backgroundColor: trackColor,
                  valueColor: AlwaysStoppedAnimation(colors.success),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(cachePercent * 100).round()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 继续阅读按钮
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.menu_book, size: 14, color: colors.agentAccent),
        label: Text(
          '继续阅读',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.agentAccent,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          side: BorderSide(color: colors.agentAccent.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}

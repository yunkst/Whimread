import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/toast_utils.dart';
import '../models/novel.dart';
import '../models/bookshelf.dart';
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

class _BookshelfScreenState extends ConsumerState<BookshelfScreen>
    with SingleTickerProviderStateMixin {
  /// 卡片滑动位移（逻辑像素，带符号）：0 = 当前卡片居中；<0 向左拖（去下一个
  /// 书架），>0 向右拖（回上一个）。拖拽跟手累加（钳制在 ±视口宽），松手后由
  /// settle 动画驱动归零。
  ///
  /// 位移即"滚动位置"：提交切换时先把当前书架替换为新书架，再把位移重定位
  /// 到新当前卡片的连续位置（offset + dir*宽），视觉无跳变，快速连续滑动
  /// 逐次成立。
  final ValueNotifier<double> _dragOffset = ValueNotifier(0);

  /// 卡片滑动区宽度（LayoutBuilder 测得），用于位移↔进度换算与边界阻尼
  double _viewportWidth = 0;

  /// 是否处于拖动 / settle 过程中（决定是否构建相邻书架的侧卡片，
  /// 闲置时不订阅相邻书架 provider）
  bool _swiping = false;

  /// 松手后的 settle 动画（回弹归零或提交后滑入归零）
  late final AnimationController _settleController;
  late final CurvedAnimation _settleCurve;
  Tween<double>? _settleTween;

  /// 提交路径中 setBookshelf 会触发 [_onCurrentShelfChanged]，
  /// 此标记避免把自己的提交误判为外部切换而归零位移
  bool _commitInProgress = false;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _settleCurve = CurvedAnimation(
      parent: _settleController,
      curve: Curves.easeOutCubic,
    );
    _settleController.addListener(_onSettleTick);
    _settleController.addStatusListener(_onSettleStatus);
    // 监听外部书架切换（Tab 点击 / Agent 指令）：终止进行中的滑动视觉直接归位。
    // 订阅随 ConsumerState 卸载自动关闭。
    ref.listenManual(currentBookshelfProvider, _onCurrentShelfChanged);
  }

  @override
  void dispose() {
    _settleController
      ..removeListener(_onSettleTick)
      ..removeStatusListener(_onSettleStatus)
      ..dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    final tween = _settleTween;
    if (tween != null) {
      _dragOffset.value = tween.evaluate(_settleCurve);
    }
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _swiping) {
      setState(() => _swiping = false);
    }
  }

  /// 外部路径切换书架（非卡片滑动提交）：停掉动画，位移直接归位
  void _onCurrentShelfChanged(Bookshelf? previous, Bookshelf next) {
    if (_commitInProgress || !mounted) return;
    _settleController.stop();
    if (_dragOffset.value != 0) _dragOffset.value = 0;
    if (_swiping) setState(() => _swiping = false);
  }

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
                  // 事件回调内显式 unawaited：上传期间避免重复进入菜单触发并发写 coverMediaId
                  unawaited(_setNovelCover(novel));
                },
              ),
              if (novel.coverMediaId != null)
                ListTile(
                  leading: Icon(Icons.hide_image_outlined,
                      color: colors.chatHintText),
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

    /// 滑动跟手累加（钳制在 ±视口宽，避免越界过量；中断 settle 后从当前位移续跟手）
  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_settleController.isAnimating) {
      // 中断 settle：保持当前位移值继续跟手（统一模型下无需归零再重定）
      _settleController.stop();
    }
    if (_viewportWidth <= 0) return;
    final next = (_dragOffset.value + details.delta.dx)
        .clamp(-_viewportWidth, _viewportWidth);
    if (next == _dragOffset.value) return;
    _dragOffset.value = next;
    if (!_swiping) setState(() => _swiping = true);
  }

  /// 手势被系统打断（如返回手势接管）→ 回弹归位
  void _onHorizontalDragCancel() {
    if (_dragOffset.value != 0) {
      _animateSettleTo(0);
    } else if (_swiping) {
      setState(() => _swiping = false);
    }
  }

  /// 左右滑动切换书架（卡片式过渡）
  ///
  /// 阈值：累计位移 ≥64px 或释放速度 ≥350px/s（互补覆盖慢拖与快甩）。
  ///
  /// 与翻页手势同向：向左滑（offset<0）进入下一个书架，向右滑回上一个。
  ///
  /// 命中后**立即**调用 `setBookshelf` 把当前书架换成目标，再把位移重定位到
  /// 新当前卡片的连续位置（offset + dir*宽），由 settle 动画驱动它滑入归零；
  /// 旧卡片作为侧卡片自然滑出。模型与分页器一致，快速连续滑动也逐次成立。
  ///
  /// 越界（已在边界书架）或 Tab 列表未就绪则回弹归位。
  void _handleHorizontalDragEnd(double velocity) {
    final offset = _dragOffset.value;
    const minDistance = 64.0;
    const minVelocity = 350.0;
    final int? dir;
    if (offset < -minDistance || velocity < -minVelocity) {
      dir = 1;
    } else if (offset > minDistance || velocity > minVelocity) {
      dir = -1;
    } else {
      dir = null;
    }
    if (dir == null) {
      if (offset != 0) _animateSettleTo(0);
      return;
    }

    final shelves = ref.read(bookshelfShelvesProvider).valueOrNull;
    if (shelves == null || shelves.isEmpty || _viewportWidth <= 0) {
      if (offset != 0) _animateSettleTo(0);
      return;
    }
    final index = shelves.indexOf(ref.read(currentBookshelfProvider));
    if (index < 0) {
      if (offset != 0) _animateSettleTo(0);
      return;
    }
    final target = (index + dir).clamp(0, shelves.length - 1);
    if (target == index) {
      // 边界书架：没有相邻卡片可切入，回弹
      if (offset != 0) _animateSettleTo(0);
      return;
    }

    // 提交 + 位移重定位（统一模型：位移即滚动位置，连续无缝）
    _commitInProgress = true;
    _dragOffset.value = offset + dir * _viewportWidth;
    ref.read(currentBookshelfProvider.notifier).setBookshelf(shelves[target]);
    _commitInProgress = false;
    _animateSettleTo(0);
  }

  /// 启动 settle 动画，从当前位移滑向 [target]
  void _animateSettleTo(double target) {
    _settleTween = Tween<double>(begin: _dragOffset.value, end: target);
    _settleController.forward(from: 0);
  }

  /// 边界阻尼：朝没有相邻书架的方向拖动时施加橡皮筋阻力
  ///
  /// display 是 raw 的纯函数（settle 动画只动 raw），回弹过程自然连续。
  double _displayOffset(
    double raw, {
    required bool hasPrev,
    required bool hasNext,
  }) {
    if (raw > 0 && !hasPrev) return _resist(raw);
    if (raw < 0 && !hasNext) return _resist(raw);
    return raw;
  }

  /// 橡皮筋阻尼：位移折 25%，并软钳制在 ±18% 视口宽
  double _resist(double raw) {
    final cap = _viewportWidth * 0.18;
    return (raw * 0.25).clamp(-cap, cap);
  }

  @override
  Widget build(BuildContext context) {
    final shelves = ref.watch(bookshelfShelvesProvider).valueOrNull;
    final currentShelf = ref.watch(currentBookshelfProvider);
    final theme = Theme.of(context);
    final currentIdx = shelves?.indexOf(currentShelf) ?? -1;
    final hasPrev = currentIdx > 0;
    final hasNext =
        shelves != null && currentIdx >= 0 && currentIdx < shelves.length - 1;

    // 卡片内容在 build 期构造一次（滑动 tick 只重算变换，不重建内容子树；
    // 相邻书架内容仅在滑动过程构造，闲置时不订阅其 provider）
    final currentContent = _ShelfContent(
      shelf: currentShelf,
      onTapNovel: (novel) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChapterListScreenRiverpod(novel: novel),
          ),
        );
      },
      onContinue: _continueReading,
      onMenu: _showNovelMenu,
    );
    Widget? prevContent;
    Widget? nextContent;
    if (_swiping && shelves != null && currentIdx >= 0) {
      if (currentIdx > 0) {
        prevContent = IgnorePointer(
          child: _ShelfContent(
            shelf: shelves[currentIdx - 1],
            onTapNovel: (novel) {},
            onContinue: (_) {},
            onMenu: (_) {},
          ),
        );
      }
      if (currentIdx < shelves.length - 1) {
        nextContent = IgnorePointer(
          child: _ShelfContent(
            shelf: shelves[currentIdx + 1],
            onTapNovel: (novel) {},
            onContinue: (_) {},
            onMenu: (_) {},
          ),
        );
      }
    }

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
          // 书架内容（卡片式过渡：左右滑动切换到相邻书架，
          // 跟手位移 + 缩放 + 阴影 + 侧卡片压暗呈现卡片堆叠景深）
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportWidth = constraints.maxWidth;
                return GestureDetector(
                  // 只听水平拖拽：纵向滚动 / 下拉刷新由内层组件接管，互不抢占；
                  // opaque 让空态视图的空白间隙也能响应滑动（deferToChild 会漏）
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: (details) =>
                      _handleHorizontalDragEnd(details.primaryVelocity ?? 0),
                  onHorizontalDragCancel: _onHorizontalDragCancel,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _dragOffset,
                    builder: (context, rawOffset, _) {
                      final width = _viewportWidth;
                      final display = _displayOffset(
                        rawOffset,
                        hasPrev: hasPrev,
                        hasNext: hasNext,
                      );

                      final cards = <Widget>[];

                      // 相邻书架侧卡片（仅滑动过程存在，越出视口即不渲染）
                      if (_swiping &&
                          shelves != null &&
                          currentIdx >= 0 &&
                          width > 0) {
                        for (final neighbor in [currentIdx - 1, currentIdx + 1]) {
                          if (neighbor < 0 || neighbor >= shelves.length) {
                            continue;
                          }
                          final x = display + (neighbor - currentIdx) * width;
                          if (x.abs() > width * 1.05) continue;
                          final sideShelfDistance =
                              (x.abs() / width).clamp(0.0, 1.0);
                          cards.add(
                            _ShelfCard(
                              content: neighbor == currentIdx - 1
                                  ? prevContent!
                                  : nextContent!,
                              x: x,
                              viewportWidth: width,
                              dim: sideShelfDistance * 0.22,
                            ),
                          );
                        }
                      }

                      // 当前书架卡片（最上层，永远渲染）
                      cards.add(
                        _ShelfCard(
                          content: currentContent,
                          x: display,
                          viewportWidth: width,
                          dim: 0,
                        ),
                      );

                      return Stack(fit: StackFit.expand, children: cards);
                    },
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

/// 单个书架的内容（小说网格 / 空态 / 错误态 / 元信息条）
///
/// 直接订阅 [shelfNovelsProvider] / [shelfCacheStatsProvider]（按书架分桶 · keepAlive），
/// 因此相邻书架的卡片可以在滑动开始时就用已缓存的数据渲染，
/// 提交切换时无需等待重新加载。
class _ShelfContent extends ConsumerWidget {
  const _ShelfContent({
    required this.shelf,
    required this.onTapNovel,
    required this.onContinue,
    required this.onMenu,
  });

  final Bookshelf shelf;
  final ValueChanged<Novel> onTapNovel;
  final ValueChanged<Novel> onContinue;
  final ValueChanged<Novel> onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novelsAsync = ref.watch(shelfNovelsProvider(shelf));
    final cacheStats = ref.watch(shelfCacheStatsProvider(shelf)).valueOrNull;
    final colors = context.appColors;

    return novelsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.error),
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
            // 按书架 family · keepAlive，整体 invalidate 让所有书架数据同步刷新
            ref.invalidate(shelfNovelsProvider);
            ref.invalidate(shelfCacheStatsProvider);
            ref.invalidate(onlineNovelsProvider);
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
                        onTap: () => onTapNovel(novel),
                        onContinue: () => onContinue(novel),
                        onMenu: () => onMenu(novel),
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
    );
  }
}

/// 书架卡片容器：圆角纸面 + 阴影随离中心距离加深 + 侧卡片压暗
///
/// 位置与缩放由 BookshelfScreen 的 Stack + Transform.translate/scale 计算，
/// 本组件只根据 [x] / [viewportWidth] 算出卡片自身的距离（用于阴影/压暗）
/// 并渲染圆角纸面容器。
class _ShelfCard extends StatelessWidget {
  const _ShelfCard({
    required this.content,
    required this.x,
    required this.viewportWidth,
    required this.dim,
  });

  final Widget content;
  final double x;
  final double viewportWidth;

  /// 侧卡片压暗强度（0 = 当前卡片不压暗）
  final double dim;

  @override
  Widget build(BuildContext context) {
    final distance =
        viewportWidth > 0 ? (x.abs() / viewportWidth).clamp(0.0, 1.0) : 0.0;
    final colors = context.appColors;
    return Transform.translate(
      offset: Offset(x, 0),
      child: Transform.scale(
        // 离中心越远越缩小，营造卡片堆叠景深
        scale: 1 - 0.05 * distance,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          clipBehavior: Clip.antiAlias,
          foregroundDecoration: dim > 0.005
              ? BoxDecoration(
                  color: Colors.black.withValues(alpha: dim),
                  borderRadius: BorderRadius.circular(20),
                )
              : null,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.divider.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08 + 0.20 * distance),
                blurRadius: 10 + 22 * distance,
                offset: Offset(0, 3 + 8 * distance),
              ),
            ],
          ),
          child: content,
        ),
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

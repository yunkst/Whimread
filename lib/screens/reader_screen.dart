/// Reader Screen - 阅读器主屏幕
///
/// 职责：
/// - 章节内容加载和显示
/// - 阅读进度管理
/// - 用户交互处理
/// - 章节导航控制
///
/// 架构：
/// - 使用 ReaderContentController 处理内容加载
/// - 使用 ReaderConcatController 处理无限滚动拼接（块几何缓存/回收/锚点）
/// - 使用 ReaderInteractionController 处理用户交互
/// - 使用 AutoScrollMixin 处理自动滚动
///
/// 依赖：
/// - ReaderContentController (lib/controllers/reader_content_controller.dart)
/// - ReaderConcatController (lib/controllers/reader_concat_controller.dart)
/// - ReaderInteractionController (lib/controllers/reader_interaction_controller.dart)
/// - AutoScrollMixin (lib/mixins/reader/auto_scroll_mixin.dart)
///
/// 状态管理：
/// - 使用 Riverpod 管理全局设置（字体大小、滚动速度、编辑模式）
/// - 使用 Controller 管理本地状态（内容、交互、拼接块）

library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/search_result.dart';
import '../services/api_service_wrapper.dart';
import '../services/novel_agent/agent_scenario.dart'; // ScenarioIds：FAB 显式声明 writing 场景
import '../mixins/reader/auto_scroll_mixin.dart';
import '../widgets/paragraph_widget.dart'; // 拼接章节的 Offstage 高度测量
import '../widgets/reader/reader_chapter_segment.dart'; // 正文分段/扁平布局
import '../widgets/reader_settings_dialog.dart'; // 阅读设置合并对话框（字体大小/文字亮度/滚动速度）
import '../widgets/theme_mode_dialog.dart'; // 主题模式选择对话框（亮色/暗色/跟随系统）
import '../widgets/reader_action_buttons.dart'; // 新增导入
import '../widgets/reader/reader_app_bar.dart'; // ReaderAppBar组件
import '../widgets/reader/reader_bottom_bar.dart'; // ReaderBottomBar组件
import '../widgets/reader/reader_content_view.dart'; // ReaderContentView组件
import '../widgets/reader/reader_error_view.dart'; // ReaderErrorView组件
import '../utils/toast_utils.dart';
import '../controllers/reader_content_controller.dart';
import '../controllers/reader_concat_controller.dart';
import '../services/logger_service.dart';
import '../utils/error_helper.dart';
// Riverpod Providers
import '../core/providers/services/network_service_providers.dart';
import '../core/providers/chapter_mutation_provider.dart';
import '../core/providers/database_providers.dart';
import '../core/providers/reader_settings_state.dart';
import '../core/providers/reader_edit_mode_provider.dart';
import '../core/providers/reader_state_providers.dart'; // 新增：细粒度状态Provider
import '../core/providers/reading_context_providers.dart';
import '../widgets/agent_chat/agent_floating_button.dart';
import '../widgets/agent_chat/agent_chat_launcher_entry.dart'; // 标注重写入口打开对话窗口
import '../widgets/reader/version_history_sheet.dart';
import '../widgets/reader/paragraph_annotation_sheet.dart'; // 段落标注编辑弹层
import '../models/chapter_version.dart';
import '../models/paragraph_annotation.dart';
import '../core/providers/scenario_sessions_provider.dart'; // 标注重写场景会话
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Novel novel;
  final Chapter chapter;
  final List<Chapter> chapters;
  final ChapterSearchResult? searchResult;

  const ReaderScreen({
    super.key,
    required this.novel,
    required this.chapter,
    required this.chapters,
    this.searchResult,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

// ============ State Fields ============
class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with
        TickerProviderStateMixin,
        AutoScrollMixin {
  late final ApiServiceWrapper _apiService;

  final ScrollController _scrollController = ScrollController();

  // ========== 新增：ReaderContentController ==========
  late ReaderContentController _contentController;

  // ========== 便捷访问器（向后兼容） ==========
  // ⚠️ 注意：这些 getter 使用 ref.read()，不会触发 UI 重建
  // 在 build() 方法中应该使用 ref.watch() 直接监听 Provider
  String get _errorMessage => _contentController.errorMessage;

  // ========== 计算属性 ==========
  /// 当前章节索引（避免重复查找）
  int get _currentChapterIndex =>
      widget.chapters.indexWhere((c) => c.url == _currentChapter.url);

  late Chapter _currentChapter;

  // 文字亮度 0.0=最暗, 1.0=最亮（默认）
  // 以下设置项统一从 readerSettingsStateNotifierProvider 即时读取（getter），
  // 避免在 build 中给可变字段赋值产生副作用（build 期间修改 State 成员）。
  double get _fontSize =>
      ref.read(readerSettingsStateNotifierProvider).value?.fontSize ?? 18.0;

  double get _textBrightness =>
      ref.read(readerSettingsStateNotifierProvider).value?.textBrightness ??
      1.0;

  // 滚动速度倍数，1.0为默认速度（供 AutoScrollMixin 使用）
  double get _scrollSpeed =>
      ref.read(readerSettingsStateNotifierProvider).value?.scrollSpeed ?? 1.0;

  // 各章节的段落标注（key = 章节 URL → 章内段落序号 → 标注）。
  // 无限滚动下正文可能同时展示多个章节，标注按章节归属存放；
  // 当前章标注通过 [_annotations] getter 读取（改写 FAB 等仍按当前章判断）。
  final Map<String, Map<int, ParagraphAnnotation>> _annotationsByChapter = {};

  /// 当前章节的段落标注（key = 章内段落序号）
  Map<int, ParagraphAnnotation> get _annotations =>
      _annotationsByChapter[_currentChapter.url] ?? const {};

  // ========== 沉浸模式（点击正文切换 UI 显隐） ==========
  bool _isChromeVisible = true;

  /// 工具栏/底栏覆盖层淡入淡出时长
  static const Duration _chromeFadeDuration = Duration(milliseconds: 150);

  // ========== 无限滚动拼接控制器 ==========
  /// 章节块列表、块几何缓存（块高/起点偏移）、顶/底边缘拼接、当前章检测、
  /// 块窗口回收与章内阅读锚点（采样/落库/恢复跳转）全部由它持有。
  /// 本 State 经其只读快照渲染 build 产物，经其显式方法变更拼接状态。
  late ReaderConcatController _concat;

  // ========== 章内锚点装载时序 ==========
  /// 首次内容加载完成后是否尝试恢复锚点（切章/刷新/搜索跳转不恢复）。
  /// 与搜索跳转互斥的装载决策，属阅读页时序，不属拼接控制器。
  bool _anchorRestorePending = true;

  // ========== 按标注重写（annotation_rewrite 场景会话驱动）==========
  /// 改写 agent 正在运行（本地态；用于控制 FAB 显示转圈 + 防重复点击）。
  /// 实际跑动状态由 [ScenarioSession.isRunning] 提供，过程可在 agent 对话窗口查看。
  bool _isRewriteRunning = false;

  /// 本次改写锁定的章节（启动时快照）。
  /// 用户改写期间可原地切章（_currentChapter 会变），清理标注 / 内容 diff /
  /// 成功 banner 都必须对准启动时的章节，不能用实时 _currentChapter。
  String? _rewriteChapterUrl;
  String? _rewriteChapterTitle;

  // 段落级延迟揭示动画：
  // - agent 写库 → ref.listen diff 新旧段落 → 变化段落登记到 _pendingReveals
  //   （_pendingOldTexts 存该段落改写前的文本，用于动画前的占位显示）
  // - 显示层对该段落保留旧文本；滚动进入视口后 ParagraphWidget 启动
  //   淡出+打字机，播完回调 onParagraphRevealComplete 撤销登记
  // - 切章/退出即丢（不持久化），重新进入直接显示新文本
  final Map<int, String> _pendingReveals = {};
  final Map<int, String> _pendingOldTexts = {};

  // 重写完成后顶部 banner（5s 自动消失）
  bool _showRewriteBanner = false;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();

    // 使用 Riverpod 获取依赖
    _apiService = ref.read(apiServiceWrapperProvider);

    _currentChapter = widget.chapter;

    // ========== 加载持久化设置 ==========
    // 设置会在 ReaderSettingsStateNotifier 中自动加载
    // 我们通过 ref.watch 在 build 方法中获取

    // ========== 初始化 ReaderContentController ==========
    // 新版本：不再需要onStateChanged回调，状态通过Riverpod Provider自动管理
    _contentController = ReaderContentController(
      ref: ref,
      apiService: _apiService,
      chapterRepository: ref.read(chapterRepositoryProvider),
      headlessService: ref.read(headlessWebViewContentServiceProvider),
    );

    // ========== 初始化 ReaderConcatController（无限滚动拼接 + 锚点） ==========
    // 拼接块状态由控制器持有；需要重建 UI 时经 setState 回调回到本 State，
    // mounted 判断/当前章/章节列表/块内容加载也以回调形式注入。
    _concat = ReaderConcatController(
      ref: ref,
      scrollController: _scrollController,
      isMounted: () => mounted,
      setState: (fn) => setState(fn),
      currentChapter: () => _currentChapter,
      chapters: () => widget.chapters,
      novelUrl: () => widget.novel.url,
      loadBlockContent: _loadBlockContent,
      onCurrentChapterDetected: _setCurrentChapter,
      onAppendApplied: resumeAutoScrollIfIntended,
    );

    // 初始化自动滚动控制器
    initAutoScroll(scrollController: _scrollController);

    // 滚动监听：无限滚动的当前章检测 + 顶/底边缘拼接触发 + 锚点采样
    _scrollController.addListener(_concat.handleScrollChanged);

    // 设置 Agent 阅读上下文（小说 + 章节）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(readingContextProvider.notifier).state = ReadingContext(
          novelTitle: widget.novel.title,
          chapterTitle: widget.chapter.title,
          novelUrl: widget.novel.url,
        );
      }
    });

    _initApiAndLoadContent();
  }

  /// 初始化API并加载内容
  Future<void> _initApiAndLoadContent() async {
    try {
      await _contentController.initialize();
      // 初始加载时不重置滚动位置，以保持搜索匹配跳转行为
      _loadChapterContent(resetScrollPosition: false);
      // 新系统不需要 _loadIllustrations()
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '初始化API并加载内容失败',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['initialization', 'load-content'],
      );
    }
  }

  // ========== 以下方法已迁移到 ReaderContentController ==========

  @override
  void deactivate() {
    // 清除 Agent 阅读上下文（deactivate 中 ref 仍有效，同步执行即可）
    // 注：复用 mounted 兜底，防止极端时序下 widget 已 dispose
    if (mounted) {
      ref.read(readingContextProvider.notifier).state = const ReadingContext();
    }
    // 章内阅读位置兜底落库（节流窗口内的最后位置不丢；deactivate 阶段
    // ref 仍有效，写库异步完成即可，幂等写入无副作用）
    final anchor = _concat.lastReadingAnchor;
    if (anchor != null) {
      unawaited(_concat.writeReadingAnchor(anchor));
    }
    super.deactivate();
  }

  @override
  void dispose() {
    disposeAutoScroll(); // 清理自动滚动资源（AutoScrollMixin）
    _scrollController.removeListener(_concat.handleScrollChanged);
    _scrollController.dispose();
    _bannerTimer?.cancel();
    // 恢复系统状态栏/导航栏（沉浸模式可能隐藏了它们）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

// ============ Chapter Content Loading ============
  Future<void> _loadChapterContent(
      {bool resetScrollPosition = true, bool forceRefresh = false}) async {
    // 暂停预加载，释放 WebView 给阅读器使用
    final preloadService = ref.read(preloadServiceProvider);
    preloadService.pause();

    try {
      await _contentController.loadChapter(
        _currentChapter,
        widget.novel,
        forceRefresh: forceRefresh,
        resetScrollPosition: resetScrollPosition,
      );
    } finally {
      // 恢复预加载
      preloadService.resume();
    }

    // 标记章节为已读（走 ChapterMutationNotifier 收口：写库 + bump signal
    // 触发章节列表已读高亮软刷新）
    await ref.read(chapterMutationProvider.notifier).markChapterAsRead(
          widget.novel.url,
          _currentChapter.url,
        );

    // 加载当前章节的段落标注
    await _loadAnnotationsFor(_currentChapter);

    // 处理滚动位置（保留在 reader_screen 中，因为这涉及到 ScrollController）
    _handleScrollPosition(resetScrollPosition);

    // 启动预加载（保留在 reader_screen 中，因为这需要完整的章节列表）
    await _startPreloadingChapters();
  }

  /// 启动预加载章节（使用新的PreloadService）
  Future<void> _startPreloadingChapters() async {
    try {
      final currentIndex = _currentChapterIndex;
      if (currentIndex == -1) return;

      final chapterUrls = widget.chapters.map((c) => c.url).toList();

      LoggerService.instance.d(
        '触发预加载: 当前章节=${_currentChapter.title}, '
        '总章节数=${widget.chapters.length}, '
        '当前索引=$currentIndex',
        category: LogCategory.cache,
        tags: ['preload', 'chapter', 'start'],
      );

      // 使用PreloadService进行预加载（通过Provider获取）
      final preloadService = ref.read(preloadServiceProvider);
      await preloadService.enqueueTasks(
        novelUrl: widget.novel.url,
        novelTitle: widget.novel.title,
        chapterUrls: chapterUrls,
        currentIndex: currentIndex,
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '预加载启动失败',
        stackTrace: stackTrace.toString(),
        category: LogCategory.cache,
        tags: ['preload', 'chapter'],
      );
    }
  }

  // 处理滚动位置的通用方法
  void _handleScrollPosition(bool resetScrollPosition) {
    // 如果有搜索结果，跳转到匹配位置（优先级最高，不做锚点恢复）
    if (widget.searchResult != null &&
        widget.searchResult!.chapterUrl == _currentChapter.url) {
      _anchorRestorePending = false;
      _scrollToSearchMatch();
      return;
    }
    // 首次进入阅读页：尝试恢复上次章内阅读位置
    if (_anchorRestorePending) {
      _anchorRestorePending = false;
      unawaited(_restoreReadingAnchor());
    } else if (resetScrollPosition) {
      // 没有搜索结果且需要重置滚动位置时，滚动到顶部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        // 无限滚动视图下，当前章上方可能已拼接前序章节，
        // 重定位到当前章起点；起点不可测（尚未布局）则回退到 0
        final target = _concat.scrollOffsetOfChapterStart(_currentChapter.url);
        _scrollController.jumpTo(target ?? 0);
      });
    }
  }

  /// 滚动到搜索匹配位置
  void _scrollToSearchMatch() {
    if (widget.searchResult == null ||
        widget.searchResult!.matchPositions.isEmpty) {
      return;
    }

    // 延迟执行滚动，确保内容已经渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final firstMatch = widget.searchResult!.firstMatch;
        if (firstMatch != null) {
          // 估算滚动位置（基于字符位置的粗略估算）
          // 这里假设平均每个字符占用一定的高度
          final estimatedScrollOffset = (firstMatch.start * 0.3).toDouble();

          final maxScrollExtent = _scrollController.position.maxScrollExtent;
          final targetOffset =
              estimatedScrollOffset.clamp(0.0, maxScrollExtent);

          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
          );

          // 显示跳转提示
          ToastUtils.showInfo(
            '已跳转到匹配位置 (${widget.searchResult!.matchCount} 处匹配)',
            context: context,
          );
        }
      }
    });
  }

  /// 导航到指定章节（支持自动滚动状态保持）
  ///
  /// [targetChapter] 目标章节

// ============ Chapter Navigation ============
  Future<void> _navigateToChapter(Chapter targetChapter) async {
    // 记录当前自动滚动状态
    final wasAutoScrolling = shouldAutoScroll;

    // 重置章节块与拼接状态：导航是"单章视图"重建，拼接内容全部丢弃
    setState(() {
      _currentChapter = targetChapter;
      // 显式切章到章首，不做章内位置恢复
      _anchorRestorePending = false;
      _concat.resetForNavigation();
      // 切章即丢揭示登记（与原语义一致）
      _pendingReveals.clear();
      _pendingOldTexts.clear();
    });
    // 更新 Agent 阅读上下文中的章节信息
    ref.read(readingContextProvider.notifier).state = ReadingContext(
      novelTitle: widget.novel.title,
      chapterTitle: targetChapter.title,
      novelUrl: widget.novel.url,
    );

    // 加载新章节内容
    await _loadChapterContent(resetScrollPosition: true);

    // 如果之前处于自动滚动状态，则恢复自动滚动
    if (wasAutoScrolling && mounted) {
      // 延迟一帧确保UI已更新
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          startAutoScroll();
          LoggerService.instance.d(
            '翻页后恢复自动滚动',
            category: LogCategory.ui,
            tags: ['navigation', 'auto-scroll', 'resume'],
          );
        }
      });
    }
  }

  void _goToPreviousChapter() {
    final currentIndex = _currentChapterIndex;
    if (currentIndex > 0) {
      _navigateToChapter(widget.chapters[currentIndex - 1]);
    } else {
      ToastUtils.showInfo('已经是第一章了', context: context);
    }
  }

  void _goToNextChapter() {
    final currentIndex = _currentChapterIndex;
    if (currentIndex != -1 && currentIndex < widget.chapters.length - 1) {
      _navigateToChapter(widget.chapters[currentIndex + 1]);
    } else {
      ToastUtils.showInfo('已经是最后一章了', context: context);
    }
  }

  // 刷新当前章节 - 删除本地缓存并重新获取最新内容
  // 注意：自动滚动相关方法已提取到 AutoScrollMixin
  // 注意：使用 startAutoScroll(), pauseAutoScroll(), stopAutoScroll(), toggleAutoScroll()

// ============ Content Refresh ============
  Future<void> _refreshChapter() async {
    // 先显示确认对话框
    final shouldRefresh = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 禁用空白区域点击关闭
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.refresh),
            SizedBox(width: 8),
            Text(
              '刷新章节',
              style: AppTypography.chapterTitle.copyWith(fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '将从服务器重新获取最新内容并覆盖本地缓存。',
              style: AppTypography.bodyProse.copyWith(
                fontSize: 15,
                height: 1.6,
                color: context.appColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '这可能会花费一些时间，请确认是否继续？',
              style: AppTypography.metaItalic.copyWith(
                color: context.appColors.inkSoft,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('确认刷新'),
          ),
        ],
      ),
    );

    if (shouldRefresh != true) return;

    // 调用重构后的加载方法，并强制刷新
    await _loadChapterContent(resetScrollPosition: true, forceRefresh: true);

    if (mounted && _errorMessage.isEmpty) {
      ToastUtils.showSuccess('章节已刷新到最新内容', context: context);
    }
  }

  // 处理菜单动作

// ============ Dialog Handlers ============
  void _handleMenuAction(String action) {
    switch (action) {
      case 'reader_settings':
        _showReaderSettingsDialog();
        break;
      case 'theme_mode':
        _showThemeModeDialog();
        break;
      case 'font_size':
      case 'scroll_speed':
        // 兼容旧菜单项，统一跳转合并的阅读设置对话框
        _showReaderSettingsDialog();
        break;
      case 'refresh':
        _refreshChapter();
        break;
      case 'version_history':
        _showVersionHistory();
        break;
      case 'create_snapshot':
        _createSnapshot();
        break;
    }
  }

  // 显示主题模式选择对话框（应用全局生效并持久化）
  void _showThemeModeDialog() {
    ThemeModeDialog.show(context, ref);
  }

  // 显示版本历史面板
  void _showVersionHistory() {
    VersionHistorySheet.show(
      context,
      chapterUrl: _currentChapter.url,
      chapterTitle: _currentChapter.title,
      novelUrl: widget.novel.url,
      onRestored: () {
        // 还原后重新加载章节内容
        _loadChapterContent(resetScrollPosition: false);
      },
    );
  }

  // 手动创建当前内容的快照
  Future<void> _createSnapshot() async {
    try {
      final content = _contentController.content;
      if (content.isEmpty) {
        if (mounted) {
          ToastUtils.showError('当前章节内容为空，无法创建快照', context: context);
        }
        return;
      }

      final versionRepo = ref.read(chapterVersionRepositoryProvider);
      await versionRepo.saveVersion(ChapterVersion(
        chapterUrl: _currentChapter.url,
        content: content,
        source: 'manual_snapshot',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        contentLength: content.length,
      ));

      // 版本淘汰
      await versionRepo.evictOldestVersions(_currentChapter.url, maxCount: 5);

      if (mounted) {
        ToastUtils.showSuccess('快照已创建', context: context);
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '创建快照失败',
        stackTrace: stackTrace,
        category: LogCategory.database,
        tags: ['chapter_version', 'snapshot', 'failed'],
      );
    }
  }

// ============ Paragraph Annotations ============
  /// 加载章节的段落标注（key = 章内段落序号），合并进按章节归档的标注表
  Future<void> _loadAnnotationsFor(Chapter chapter) async {
    if (_annotationsByChapter.containsKey(chapter.url)) return;
    try {
      final repo = ref.read(paragraphAnnotationRepositoryProvider);
      final list = await repo.getForChapter(chapter.url);
      if (!mounted) return;
      setState(() {
        _annotationsByChapter[chapter.url] = {
          for (final a in list) a.paragraphIndex: a,
        };
      });
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '加载段落标注失败',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'load', 'failed'],
      );
    }
  }

  /// 长按段落：弹出标注编辑弹层（已有标注则回显编辑）
  void _showAnnotationEditor(String chapterUrl, int index, String paragraph) {
    ParagraphAnnotationSheet.show(
      context,
      paragraphPreview: ParagraphAnnotation.buildPreview(paragraph),
      existing: _annotationsByChapter[chapterUrl]?[index],
      onSave: (content) => _saveAnnotation(chapterUrl, index, paragraph, content),
      onDelete: () => _deleteAnnotation(chapterUrl, index),
    );
  }

  /// 保存段落标注（新增或更新），返回是否成功
  Future<bool> _saveAnnotation(
      String chapterUrl, int index, String paragraph, String content) async {
    try {
      final repo = ref.read(paragraphAnnotationRepositoryProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = _annotationsByChapter[chapterUrl]?[index];
      final annotation = ParagraphAnnotation(
        novelUrl: widget.novel.url,
        chapterUrl: chapterUrl,
        paragraphIndex: index,
        paragraphPreview: ParagraphAnnotation.buildPreview(paragraph),
        content: content,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      );

      final id = await repo.upsert(annotation);
      if (!mounted) return false;
      setState(() {
        _annotationsByChapter
            .putIfAbsent(chapterUrl, () => {})[index] = annotation.copyWith(id: id);
      });
      ToastUtils.showSuccess(
        old == null ? '标注已保存' : '标注已更新',
        context: context,
      );
      return true;
    } catch (e, stackTrace) {
      if (!mounted) return false;
      ErrorHelper.showErrorWithLog(
        context,
        '保存标注失败',
        stackTrace: stackTrace,
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'save', 'failed'],
      );
      return false;
    }
  }

  /// 删除段落标注，返回是否成功
  Future<bool> _deleteAnnotation(String chapterUrl, int index) async {
    final existing = _annotationsByChapter[chapterUrl]?[index];
    if (existing?.id == null) return false;
    try {
      final repo = ref.read(paragraphAnnotationRepositoryProvider);
      await repo.delete(existing!.id!);
      if (!mounted) return false;
      setState(() {
        _annotationsByChapter[chapterUrl]?.remove(index);
      });
      ToastUtils.showSuccess('标注已删除', context: context);
      return true;
    } catch (e, stackTrace) {
      if (!mounted) return false;
      ErrorHelper.showErrorWithLog(
        context,
        '删除标注失败',
        stackTrace: stackTrace,
        category: LogCategory.database,
        tags: ['paragraph_annotation', 'delete', 'failed'],
      );
      return false;
    }
  }

  // ===================== 按标注重写（annotation_rewrite 场景会话）=====================

  /// 启动按标注重写：改写交给 annotation_rewrite 场景的 [ScenarioSession]，
  /// 过程（读章/替换/思考）通过对话窗口实时可见。
  ///
  /// 点击入口前：`_annotations.isNotEmpty` 由按钮构造条件保证；
  /// 运行中：不重复启动，点击转为重新打开对话窗口查看进度；
  /// 编辑模式下拒绝启动。
  /// 成功后清理本章节标注（已被 AI 消化，保留会误导「还有待重写标注」）。
  Future<void> _startAnnotationRewrite() async {
    if (_isRewriteRunning) {
      // 会话存在全局 scenarioSessionsProvider，启动时弹出的对话窗口被关掉后，
      // 点击 FAB 重开仍能看到正在跑的过程；静默 return 会让用户误以为按钮失灵。
      AgentChatLauncherEntry.open(
          context, scenarioId: ScenarioIds.annotationRewrite);
      return;
    }
    if (_annotations.isEmpty) return;
    final isEditMode = ref.read(readerEditModeProvider);
    if (isEditMode) {
      ToastUtils.showError('编辑模式下不可重写，请先退出编辑', context: context);
      return;
    }

    // 锁定章节在 widget.chapters 列表里的 1-based position。
    // 真实写库走 _currentChapter.url，与 position 无关（仅在 list_chapters
    // 返回结果里标注给 LLM 看）。list_chapters 走 DB getCachedNovelChapters
    // 按 chapterIndex ASC 排序，与 widget.chapters 在阅读页保持一致。
    final lockedPosition = _currentChapterIndex + 1;
    final annotations = _annotations.values.toList();

    // 启动时快照改写目标章节：改写期间用户可原地切章（_currentChapter 被换掉），
    // 完成后的标注清理、内容 diff、banner 都必须对准这里记录的章节。
    _rewriteChapterUrl = _currentChapter.url;
    _rewriteChapterTitle = _currentChapter.title;

    setState(() => _isRewriteRunning = true);

    LoggerService.instance.i(
      '启动按标注重写: chapter=${_currentChapter.title} '
      'annotations=${annotations.length} position=$lockedPosition',
      category: LogCategory.ai,
      tags: ['reader', 'rewrite', 'start'],
    );

    try {
      // 打开对话窗口（切到 annotation_rewrite 场景），让用户实时看到 agent 工作过程
      AgentChatLauncherEntry.open(context, scenarioId: ScenarioIds.annotationRewrite);

      final session = ref
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.annotationRewrite);
      final outcome = await session.startAnnotationRewrite(
        novelUrl: widget.novel.url,
        novelTitle: widget.novel.title,
        chapterUrl: _currentChapter.url,
        chapterTitle: _currentChapter.title,
        lockedPosition: lockedPosition,
        annotations: annotations,
      );

      if (!mounted) return;
      setState(() => _isRewriteRunning = false);

      if (outcome.success) {
        // 标注已被 AI 重写消化 → 清理（DB + 内存），对准启动时锁定的章节
        await _clearAnnotationsAfterRewrite();
        if (!mounted) return;
        // 用户改写期间可能已切到其它章节，提示语对准被改写的章节
        final stillViewing = _currentChapter.url == _rewriteChapterUrl;
        ToastUtils.showSuccess(
          stillViewing
              ? '已按标注重写本章（${outcome.updateCount} 处修改）'
              : '已按标注重写《$_rewriteChapterTitle》（${outcome.updateCount} 处修改）',
          context: context,
        );
        // 顶部 banner 只在用户仍停留在被改写章节时展示（banner 文案是"本章"），
        // 5s 后自动消失
        if (stillViewing) {
          _bannerTimer?.cancel();
          setState(() => _showRewriteBanner = true);
          _bannerTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() => _showRewriteBanner = false);
          });
        }
      } else {
        ErrorHelper.showErrorWithLog(
          context,
          '按标注重写失败: ${outcome.error}',
          category: LogCategory.ai,
          tags: ['reader', 'rewrite', 'failed'],
        );
      }
    } catch (e, st) {
      LoggerService.instance.e(
        '按标注重写异常: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['reader', 'rewrite', 'exception'],
      );
      if (!mounted) return;
      setState(() => _isRewriteRunning = false);
      ErrorHelper.showErrorWithLog(
        context,
        '按标注重写异常: $e',
        category: LogCategory.ai,
        tags: ['reader', 'rewrite', 'exception'],
      );
    }
  }

  /// 重写成功后清理本章节标注（DB + 内存状态）。
  /// 对准启动时锁定的 [_rewriteChapterUrl]——改写期间用户可能已原地切章，
  /// 实时 [_currentChapter] 已不可信。
  Future<void> _clearAnnotationsAfterRewrite() async {
    final chapterUrl = _rewriteChapterUrl ?? _currentChapter.url;
    try {
      await ref
          .read(paragraphAnnotationRepositoryProvider)
          .deleteByChapter(chapterUrl);
    } catch (e, st) {
      LoggerService.instance.e(
        '清理章节标注失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['reader', 'rewrite', 'clear_annotations', 'failed'],
      );
    }
    if (mounted) setState(() => _annotationsByChapter.remove(chapterUrl));
  }

  /// ref.listen 回调：agent 写库 → diff 新旧段落 → 登记待揭示段落
  ///
  /// 守卫：
  /// - 仅在改写运行期间消化内容更新；其它来源的变化（用户编辑保存/切章/刷新）
  ///   直接清空揭示状态。
  /// - 仅消化「正在展示被改写章节」的更新：用户切到其它章节后，全局内容状态
  ///   属于那个章节，与改写 diff 语义完全对不上，必须忽略（防跨章节污染）。
  ///
  /// 对齐策略：段落级公共前缀/后缀对齐。中段长度一致时逐段配对，变化段登记
  /// 揭示（含改写前文本占位）；中段有段落增删（合并/拆分）时索引整体错位，
  /// 丢弃中段及之后的登记、该区域瞬时替换——前缀区域已登记的揭示不受影响。
  void _onContentChangedForRewrite(
      ChapterContentState? prev, ChapterContentState next) {
    if (!_isRewriteRunning) {
      // 非 agent 期间的内容变化（用户编辑保存/切章/刷新）：清空揭示状态
      if (_pendingReveals.isNotEmpty || _pendingOldTexts.isNotEmpty) {
        _pendingReveals.clear();
        _pendingOldTexts.clear();
      }
      return;
    }
    if (prev == null || prev.content == next.content) return;
    if (next.currentChapter?.url != _rewriteChapterUrl) {
      // 阅读页已切到其它章节（或内容状态尚未挂上目标章节）：忽略，
      // 场景层此时也不会再写入内容状态（双保险）
      return;
    }

    // 段落拆分与显示层同源（ReaderChapterSegment.splitParagraphs）
    final oldParas = ReaderChapterSegment.splitParagraphs(prev.content);
    final newParas = ReaderChapterSegment.splitParagraphs(next.content);

    var prefix = 0;
    while (prefix < oldParas.length &&
        prefix < newParas.length &&
        oldParas[prefix] == newParas[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldParas.length - prefix &&
        suffix < newParas.length - prefix &&
        oldParas[oldParas.length - 1 - suffix] ==
            newParas[newParas.length - 1 - suffix]) {
      suffix++;
    }
    final oldMidEnd = oldParas.length - suffix;
    final newMidEnd = newParas.length - suffix;

    var changed = 0;
    if (oldMidEnd - prefix == newMidEnd - prefix) {
      // 中段可逐段配对：变化段落登记揭示（允许已揭示段落再次动画）
      for (var i = prefix; i < newMidEnd; i++) {
        if (oldParas[i] == newParas[i]) continue;
        changed++;
        _pendingOldTexts[i] = oldParas[i];
        _pendingReveals[i] = newParas[i];
      }
    } else {
      // 中段段落增删（合并/拆分）：索引错位，登记失效 → 中段瞬时替换
      LoggerService.instance.d(
        '标注重写 中段段落数变化 (${oldParas.length} → ${newParas.length})，'
        '[$prefix, $newMidEnd) 区间回退瞬时替换',
        category: LogCategory.ai,
        tags: ['reader', 'rewrite', 'fallback_instant'],
      );
      _pendingReveals.removeWhere((i, _) => i >= prefix);
      _pendingOldTexts.removeWhere((i, _) => i >= prefix);
    }
    if (changed > 0 && mounted) {
      setState(() {}); // 触发显示层按 pending 重建（未揭示段落显示旧文本）
    }
    LoggerService.instance.d(
      '标注重写 内容变化: $changed 段待揭示 (pending=${_pendingReveals.length})',
      category: LogCategory.ai,
      tags: ['reader', 'rewrite', 'pending'],
    );
  }

  /// ParagraphWidget 打字机动画播完回调：撤销该段的揭示登记，
  /// 让段落静态显示新文本。**不匹配则保留登记**——动画期间 agent 又改了
  /// 这一段时，登记里已是最新文本，下一次构建会以新目标重启动画。
  /// 揭示登记只归属被改写章节（chapterUrl 仅用于确认），清理无需区分。
  void _onParagraphRevealComplete(
      String chapterUrl, int index, String revealedText) {
    if (_pendingReveals[index] != revealedText) return;
    _pendingReveals.remove(index);
    _pendingOldTexts.remove(index);
    if (mounted) setState(() {});
  }

  /// 改写模式 FAB 内容：auto_fix_high 图标 + 标注数量徽标 + 运行中转圈
  ///
  /// 由 [AgentFloatingShell] 通过 overrideChild 渲染（仅本章节有标注时）。
  /// 角标数量 = `_annotations.length`，让用户一眼看到有几条待消化批注。
  Widget _buildRewriteFabChild() {
    final appColors = context.appColors;
    final badgeBackground = Theme.of(context).colorScheme.surface;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (_isRewriteRunning)
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor:
                  AlwaysStoppedAnimation<Color>(appColors.agentOnBrand),
            ),
          )
        else
          Icon(
            Icons.auto_fix_high,
            color: appColors.agentOnBrand,
            size: 22,
          ),
        Positioned(
          right: -6,
          top: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: badgeBackground,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              '${_annotations.length}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: appColors.agentAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 顶部 banner：重写成功后短暂展示，可一键打开版本历史还原
  Widget _buildRewriteBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.auto_fix_high,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '本章已按标注重写',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _bannerTimer?.cancel();
                setState(() => _showRewriteBanner = false);
                _showVersionHistory();
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('还原'),
            ),
          ],
        ),
      ),
    );
  }

  // 显示阅读设置对话框（合并字体大小、文字亮度、滚动速度）
  void _showReaderSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁用空白区域点击关闭
      builder: (context) => ReaderSettingsDialog(
        initialFontSize: _fontSize,
        initialTextBrightness: _textBrightness,
        initialScrollSpeed: _scrollSpeed,
        onConfirm: ({
          required double fontSize,
          required double textBrightness,
          required double scrollSpeed,
        }) async {
          final notifier =
              ref.read(readerSettingsStateNotifierProvider.notifier);
          // 字体大小
          await notifier.setFontSize(fontSize);
          // 文字亮度
          await notifier.setTextBrightness(textBrightness);
          // 滚动速度
          await notifier.setScrollSpeed(scrollSpeed);
          // 速度改变后重新启动自动滚动以应用新速度（Mixin方法）
          startAutoScroll();
        },
      ),
    );
  }

  // ========== 辅助方法 ==========

  // 保存编辑后的章节内容

// ============ Content Editing ============
  Future<void> _saveEditedContent() async {
    try {
      // 走 ChapterMutationNotifier 收口：写库 + bump signal 触发章节列表软刷新
      await ref.read(chapterMutationProvider.notifier).updateChapterContent(
        _currentChapter.url,
        _contentController.content,
        source: 'edit',
        novelUrl: widget.novel.url,
      );

      if (mounted) {
        ToastUtils.showSuccess('章节内容已保存', context: context);
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '保存编辑内容失败',
        stackTrace: stackTrace,
        category: LogCategory.database,
        tags: ['save', 'chapter-content', 'edit'],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听设置状态变化（仅用于触发 rebuild；字段值通过 getter 实时读取）
    ref.watch(readerSettingsStateNotifierProvider);

    // 字体大小变化 → 全部内容重新排版，块高与起点偏移缓存整体失效。
    // 经拼接控制器显式失效（原实现在此直接改写 _knownBlockHeights 等
    // State 成员，现收敛为控制器方法，行为不变）。
    _concat.invalidateGeometryForFontSize(_fontSize);

    // 使用 ref.watch 监听编辑模式状态
    final isEditMode = ref.watch(readerEditModeProvider);

    // ⭐ 关键修复：监听章节内容状态，确保内容加载后UI重建（修复空白页面问题）
    final contentState = ref.watch(chapterContentStateNotifierProvider);

    // 监听内容变化 → agent 写库时 diff 段落并登记待揭示
    ref.listen<ChapterContentState>(
      chapterContentStateNotifierProvider,
      _onContentChangedForRewrite,
    );

    // 全局内容状态 → 章节块同步（导航装载 / 刷新 / 编辑保存 / 改写落库）。
    // ⚠️ 时序约束：必须保留在 build 内、_buildSegments 之前**同步**执行，
    // 不能改成 ref.listen 回调——loadChapter 的装载序列是「setCurrentContext
    // → setLoading(true) → clearContent → 抓取 → setContent →
    // setLoading(false)」多次离散赋值，Riverpod 监听器会在每次赋值时同步
    // 触发，会观察到「新章节上下文 + 旧章节内容」的中间态（setCurrentContext
    // 已写入、clearContent 尚未执行），把旧内容错建成新章节的块；而 build
    // 只在状态“落定”后的帧边界执行（要么 isLoading=true、要么内容已与当前章
    // 一致），天然规避中间态。每帧重复调用幂等。块变更经拼接控制器的显式
    // 方法完成（不再直接改写 State 成员）。
    _concat.syncCurrentBlockFrom(contentState);

    // 正文分段：阅读模式 = 全部已拼接章节；编辑模式 = 仅当前章
    final segments = _buildSegments(isEditMode);

    // 有标注时 AI 悬浮按钮自动切换为「按标注重写」入口（点击启动改写并打开
    // 对话窗口查看过程）；无标注时保持默认「打开写作对话」行为。
    final hasAnnotations = _annotations.isNotEmpty;

    return AgentFloatingShell(
      scenarioId: ScenarioIds.writing,
      showFloatingButton: _isChromeVisible,
      overrideChild: hasAnnotations ? _buildRewriteFabChild() : null,
      overrideOnTap: hasAnnotations ? _startAnnotationRewrite : null,
      child: Scaffold(
        // 顶栏不用 Scaffold.appBar 而以悬浮覆盖层呈现（见 _buildBody）：
        // Scaffold.appBar 显隐会推挤 body 导致正文抖动，覆盖层不动正文布局
        body: _buildBody(context, isEditMode, segments, contentState),
        floatingActionButton:
            (contentState.content.isEmpty || !_isChromeVisible)
                ? null
                : ReaderActionButtons(
                    isAutoScrolling: isAutoScrolling, // Mixin getter
                    isAutoScrollPaused: isAutoScrollPaused, // Mixin getter
                    onToggleAutoScroll: toggleAutoScroll, // Mixin method
                  ),
      ),
    );
  }

  /// 顶部工具栏覆盖层总高（状态栏 + 工具栏），banner 等提示在
  /// 工具栏可见时需避让到其下方
  double get _toolbarOverlayHeight =>
      MediaQuery.paddingOf(context).top + kToolbarHeight;

  /// 构建阅读器主体内容。
  ///
  /// 正文（含加载/错误态）永远全屏铺满；工具栏/底栏为悬浮覆盖层，
  /// 显隐只做淡入淡出——正文布局不随沉浸切换移动（修复抖动）。
  Widget _buildBody(
    BuildContext context,
    bool isEditMode,
    List<ReaderChapterSegment> segments,
    ChapterContentState contentState,
  ) {
    Widget content;
    if (contentState.isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (contentState.errorMessage.isNotEmpty) {
      content = ReaderErrorView(
        errorMessage: contentState.errorMessage,
        onRetry: () => _loadChapterContent(resetScrollPosition: false),
      );
    } else if (contentState.content.trim().isEmpty) {
      // 检查内容是否为空（修复空白页面问题）
      content = ReaderErrorView(
        errorMessage: '章节内容为空，请尝试刷新或联系开发者',
        onRetry: () => _loadChapterContent(
          resetScrollPosition: false,
          forceRefresh: true,
        ),
      );
    } else {
      // 主要内容区域（点击正文切换沉浸模式；段落级延迟揭示见 ReaderContentView）
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleChrome,
        child: ReaderContentView(
          segments: segments,
          blockStartKeys: _concat.blockStartKeys,
          fontSize: _fontSize,
          textBrightness: _textBrightness,
          isEditMode: isEditMode,
          isAutoScrolling: isAutoScrolling,
          onParagraphLongPress: _showAnnotationEditor,
          onParagraphRevealComplete: _onParagraphRevealComplete,
          onContentChanged: (index, newContent) {
            // 仅支持全文编辑模式（index=-1）
            assert(index == -1, '只支持全文编辑模式，段落编辑模式已废弃');
            // 使用 addPostFrameCallback 避免在构建阶段调用 setState
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _contentController.setContent(newContent);
              });
            });
          },
          scrollController: _scrollController,
          onPointerDown: () {
            // 手指接触屏幕，暂停自动滚动
            if (isAutoScrolling) {
              handleTouch();
            }
          },
          onPointerUp: () {
            // handleTouch() 已经设置了恢复定时器，所以这里不需要额外处理
          },
          onScrollNotification: (notification) {
            // 保留以兼容现有代码（不再处理用户滚动）
            return handleScrollNotification(notification);
          },
        ),
      );
    }

    final currentIndex = _currentChapterIndex;
    final hasPrevious = currentIndex > 0;
    final hasNext =
        currentIndex != -1 && currentIndex < widget.chapters.length - 1;

    // 工具栏可见时，顶部提示避让到工具栏下方
    final topTipOffset =
        _isChromeVisible ? _toolbarOverlayHeight + 8 : 8.0;
    // 底部提示避让到底栏（底栏含安全区）上方
    final bottomTipOffset = _isChromeVisible
        ? MediaQuery.paddingOf(context).bottom + 88
        : 88.0;

    // 拼接控制器状态的只读快照（帧内取一次，供下方覆盖层/测高层使用）
    final pendingPrepend = _concat.pendingPrependBlock;

    return Stack(
      children: [
        content,
        // 顶部「已按标注重写」banner（重写成功后短暂展示，可一键还原）
        if (_showRewriteBanner)
          Positioned(
            top: topTipOffset,
            left: 16,
            right: 16,
            child: _buildRewriteBanner(context),
          ),
        // 拼接失败重试入口（上一章：顶部；下一章：底栏上方）
        if (_concat.prevConcatFailed)
          Positioned(
            top: topTipOffset,
            left: 16,
            right: 16,
            child: Center(
              child: _buildConcatRetryChip('上一章加载失败，点击重试', () {
                setState(() => _concat.clearPrevConcatFailure());
                _concat.prependPreviousChapter(force: true);
              }),
            ),
          ),
        if (_concat.concatDirection == ReaderConcatDirection.next)
          Positioned(
            bottom: bottomTipOffset,
            left: 0,
            right: 0,
            child: Center(child: _buildConcatStatusChip('正在加载下一章…')),
          ),
        if (_concat.nextConcatFailed)
          Positioned(
            bottom: bottomTipOffset,
            left: 16,
            right: 16,
            child: Center(
              child: _buildConcatRetryChip('下一章加载失败，点击重试', () {
                setState(() => _concat.clearNextConcatFailure());
                _concat.appendNextChapter(force: true);
              }),
            ),
          ),
        // 上一章的 Offstage 测量层（与正文同宽同构，测高后插入 + 滚动补偿）
        if (pendingPrepend != null)
          Positioned(
            left: 0,
            top: 0,
            width: MediaQuery.sizeOf(context).width - 32,
            child: Offstage(
              child: SizedBox(
                key: _concat.prependMeasureKey,
                width: MediaQuery.sizeOf(context).width - 32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 与正文列表同构：分隔线也计入插入高度
                    ReaderChapterDivider(
                      title: pendingPrepend.chapter.title,
                    ),
                    for (var i = 0; i < pendingPrepend.paragraphs.length; i++)
                      ParagraphWidget(
                        paragraph: pendingPrepend.paragraphs[i],
                        index: i,
                        fontSize: _fontSize,
                        textBrightness: _textBrightness,
                        isEditMode: false,
                        hasAnnotation: _annotationsByChapter[
                                pendingPrepend.chapter.url]
                            ?.containsKey(i) ??
                            false,
                      ),
                  ],
                ),
              ),
            ),
          ),
        // 底部章节切换栏（悬浮覆盖层，随沉浸显隐淡入淡出，不推动正文）
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_isChromeVisible,
            child: AnimatedOpacity(
              opacity: _isChromeVisible ? 1.0 : 0.0,
              duration: _chromeFadeDuration,
              child: ReaderBottomBar(
                currentIndex: currentIndex,
                totalChapters: widget.chapters.length,
                hasPrevious: hasPrevious,
                hasNext: hasNext,
                onPreviousChapter: _goToPreviousChapter,
                onNextChapter: _goToNextChapter,
              ),
            ),
          ),
        ),
        // 顶部工具栏（悬浮覆盖层：正文铺到状态栏后面，工具栏覆盖其上，
        // 显隐不再推挤正文；加载/错误态同样覆盖，保证始终有返回入口）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_isChromeVisible,
            child: AnimatedOpacity(
              opacity: _isChromeVisible ? 1.0 : 0.0,
              duration: _chromeFadeDuration,
              child: ReaderAppBar(
                novel: widget.novel,
                currentChapter: _currentChapter,
                chapters: widget.chapters,
                isEditMode: isEditMode,
                onToggleEditMode: () =>
                    ref.read(readerEditModeProvider.notifier).toggle(),
                onSaveAndExitEditMode: () async {
                  await _saveEditedContent();
                  ref.read(readerEditModeProvider.notifier).toggle();
                },
                onMenuAction: _handleMenuAction,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 注意：插图处理相关方法已迁移（IllustrationHandlerMixin 已移除）

  // ========== 沉浸模式（点击正文隐藏/显示阅读 UI） ==========

  void _showChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_isChromeVisible) {
      setState(() => _isChromeVisible = true);
    }
    // 唤出工具栏 = 用户要操作菜单：取消触摸暂停的 1 秒自动恢复，
    // 自动滚动保持暂停，直到隐藏工具栏或按 FAB 显式控制
    pauseAutoScrollUntilResumed();
  }

  void _hideChrome() {
    // immersiveSticky：隐藏状态栏/导航栏，从屏幕边缘滑入时临时显示后自动隐藏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_isChromeVisible) {
      setState(() => _isChromeVisible = false);
    }
    // 回到沉浸阅读：若此前有自动滚动意图（如唤菜单前在滚动）则接续滚动
    resumeAutoScrollIfIntended();
  }

  void _toggleChrome() {
    // 编辑模式需要工具栏与键盘布局，不进入沉浸
    if (ref.read(readerEditModeProvider)) return;
    if (_isChromeVisible) {
      _hideChrome();
    } else {
      _showChrome();
    }
  }

  // ========== 章内阅读位置锚点（重开恢复入口） ==========
  // 锚点的滚动采样、节流落库与恢复跳转执行都在 ReaderConcatController；
  // 这里只负责「何时恢复」的决策（读取锚点 + 各类互斥守卫 + 恢复提示）。

  /// 恢复上次章内阅读位置（仅首次进入阅读页时经 [_handleScrollPosition] 触发）。
  Future<void> _restoreReadingAnchor() async {
    try {
      final anchor = await ref
          .read(novelRepositoryProvider)
          .getLastReadAnchor(widget.novel.url);
      if (!mounted || anchor == null) return;
      // 锚点不属于当前打开的章节（如从章节列表点了别的章）→ 不恢复
      if (anchor.chapterUrl != _currentChapter.url) return;
      if (ref.read(readerEditModeProvider)) return;
      if (widget.searchResult != null &&
          widget.searchResult!.chapterUrl == _currentChapter.url) {
        return;
      }
      final restored = await _concat.restoreAnchor(anchor);
      if (restored && mounted) {
        ToastUtils.showInfo('已回到上次阅读位置', context: context);
        LoggerService.instance.i(
          '恢复章内阅读位置: p=${anchor.paragraphIndex} r=${anchor.paragraphRatio}',
          category: LogCategory.ui,
          tags: ['reader', 'anchor', 'restore'],
        );
      }
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        '恢复章内阅读位置失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ui,
        tags: ['reader', 'anchor', 'restore-failed'],
      );
    }
  }

  // ========== 视口当前章检测与拼接（执行体在 ReaderConcatController） ==========

  /// 视口滚动跨入新章节：切换当前章并同步标题/进度/标注/预加载/全局内容状态。
  /// 由拼接控制器在滚动回调中检测到章节越界后回调（onCurrentChapterDetected）。
  void _setCurrentChapter(Chapter chapter) {
    final rawContent = _concat.rawContentOf(chapter.url);
    if (rawContent == null) return;

    setState(() => _currentChapter = chapter);
    LoggerService.instance.i(
      '无限滚动切章: ${chapter.title}',
      category: LogCategory.ui,
      tags: ['reader', 'concat', 'chapter-switch'],
    );

    ref.read(readingContextProvider.notifier).state = ReadingContext(
      novelTitle: widget.novel.title,
      chapterTitle: chapter.title,
      novelUrl: widget.novel.url,
    );

    // 同步全局内容状态到新当前章（快照/编辑保存/改写场景依赖三者一致）。
    // 改写运行期间跳过：切章触发的内容 diff 会误登记揭示。
    if (!_isRewriteRunning) {
      final notifier = ref.read(chapterContentStateNotifierProvider.notifier);
      notifier.setCurrentContext(chapter, widget.novel);
      notifier.setContent(rawContent);
      notifier.setLoading(false);
      notifier.setError('');
    }

    // 进度上报与已读标记（收口到对应 Notifier）
    unawaited(
        _contentController.updateReadingProgress(widget.novel.url, chapter));
    unawaited(ref
        .read(chapterMutationProvider.notifier)
        .markChapterAsRead(widget.novel.url, chapter.url));
    unawaited(_loadAnnotationsFor(chapter));
    // 以新当前章为锚点重排预加载队列
    unawaited(_startPreloadingChapters());

    // 切章后窗口外章节块可回收
    _concat.trimDistantBlocks();
  }

  /// 加载拼接章节内容（缓存优先，未命中走 HeadlessWebView 抓取并写缓存）。
  /// 抓取期间暂停预加载让出 WebView（与主章节加载一致）。
  /// 注入给拼接控制器使用（loadBlockContent 回调）。
  Future<String> _loadBlockContent(Chapter chapter) async {
    final preloadService = ref.read(preloadServiceProvider);
    preloadService.pause();
    try {
      return await _contentController.loadChapterRaw(chapter, widget.novel);
    } finally {
      preloadService.resume();
    }
  }

  /// 组装正文分段（阅读模式 = 全部章节块；编辑模式 = 仅当前章）
  List<ReaderChapterSegment> _buildSegments(bool isEditMode) {
    final blocks = _concat.blocks;
    if (blocks.isEmpty) return const [];
    final currentUrl = _currentChapter.url;
    final Iterable<ReaderChapterBlock> blocksToShow = isEditMode
        ? blocks.where((b) => b.chapter.url == currentUrl)
        : blocks;
    return [for (final block in blocksToShow) _buildSegment(block, isEditMode)];
  }

  ReaderChapterSegment _buildSegment(ReaderChapterBlock block, bool isEditMode) {
    // 章节起点标记 key（0 高度条目携带，供视口检测/重定位）
    _concat.registerStartKey(block.chapter.url);

    var paragraphs = block.paragraphs;
    final pendingReveals = <int, String>{};
    // 改写揭示：旧文本占位 + 新文本目标，只作用于被改写章节的展示。
    // （原实现隐式作用于"当前显示内容"，多章拼接下必须显式锁定改写目标章节）
    final revealTargetUrl = _rewriteChapterUrl;
    if (!isEditMode &&
        revealTargetUrl != null &&
        block.chapter.url == revealTargetUrl &&
        _pendingReveals.isNotEmpty) {
      paragraphs = List.of(block.paragraphs);
      for (final entry in _pendingReveals.entries) {
        final i = entry.key;
        if (i >= paragraphs.length) continue;
        final oldText = _pendingOldTexts[i];
        if (oldText != null && oldText != paragraphs[i]) {
          paragraphs[i] = oldText;
        }
        pendingReveals[i] = entry.value;
      }
    }

    return ReaderChapterSegment(
      chapterUrl: block.chapter.url,
      chapterTitle: block.chapter.title,
      paragraphs: paragraphs,
      annotatedIndexes: _annotationsByChapter[block.chapter.url]?.keys.toSet() ??
          const <int>{},
      pendingReveals: pendingReveals,
    );
  }

  /// 拼接失败重试入口
  Widget _buildConcatRetryChip(String text, VoidCallback onRetry) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 拼接进行中提示
  Widget _buildConcatStatusChip(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  // ========== AutoScrollMixin 抽象字段实现 ==========

  @override
  ScrollController get scrollController => _scrollController;

  @override
  double get scrollSpeed => _scrollSpeed;
}

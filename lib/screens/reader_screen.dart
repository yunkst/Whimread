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
/// - 使用 ReaderInteractionController 处理用户交互
/// - 使用 AutoScrollMixin 处理自动滚动
///
/// 依赖：
/// - ReaderContentController (lib/controllers/reader_content_controller.dart)
/// - ReaderInteractionController (lib/controllers/reader_interaction_controller.dart)
/// - AutoScrollMixin (lib/mixins/reader/auto_scroll_mixin.dart)
///
/// 状态管理：
/// - 使用 Riverpod 管理全局设置（字体大小、滚动速度、编辑模式）
/// - 使用 Controller 管理本地状态（内容、交互）

library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/search_result.dart';
import '../services/api_service_wrapper.dart';
import '../services/novel_agent/agent_scenario.dart'; // ScenarioIds：FAB 显式声明 writing 场景
import '../mixins/reader/auto_scroll_mixin.dart';
import '../widgets/reader_settings_dialog.dart'; // 阅读设置合并对话框（字体大小/文字亮度/滚动速度）
import '../widgets/reader_action_buttons.dart'; // 新增导入
import '../widgets/reader/reader_app_bar.dart'; // ReaderAppBar组件
import '../widgets/reader/reader_bottom_bar.dart'; // ReaderBottomBar组件
import '../widgets/reader/reader_content_view.dart'; // ReaderContentView组件
import '../widgets/reader/reader_error_view.dart'; // ReaderErrorView组件
import '../utils/toast_utils.dart';
import '../controllers/reader_content_controller.dart';
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
import '../widgets/reader/version_history_sheet.dart';
import '../models/chapter_version.dart';
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
  bool get _isLoading => _contentController.isLoading;
  String get _errorMessage => _contentController.errorMessage;

  // ========== 计算属性 ==========
  /// 当前章节索引（避免重复查找）
  int get _currentChapterIndex =>
      widget.chapters.indexWhere((c) => c.url == _currentChapter.url);

  late Chapter _currentChapter;
  double? _fontSize;

  // 文字亮度 0.0=最暗, 1.0=最亮（默认）
  double? _textBrightness;

  // 注意：自动滚动相关的字段和方法已提取到 AutoScrollMixin

  // 保留滚动速度配置（供 AutoScrollMixin 使用）
  double? _scrollSpeed; // 滚动速度倍数，1.0为默认速度

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

    // 初始化自动滚动控制器
    initAutoScroll(scrollController: _scrollController);

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
    super.deactivate();
  }

  @override
  void dispose() {
    disposeAutoScroll(); // 清理自动滚动资源（AutoScrollMixin）
    _scrollController.dispose();
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

    // 处理滚动位置（保留在 reader_screen 中，因为这涉及到 ScrollController）
    _handleScrollPosition(resetScrollPosition);

    // 启动预加载（保留在 reader_screen 中，因为这需要完整的章节列表）
    await _startPreloadingChapters();
  }

  /// 启动预加载章节（使用新的PreloadService）
  Future<void> _startPreloadingChapters() async {
    try {
      final currentIndex =
          widget.chapters.indexWhere((c) => c.url == _currentChapter.url);
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
    // 如果有搜索结果，跳转到匹配位置
    if (widget.searchResult != null &&
        widget.searchResult!.chapterUrl == _currentChapter.url) {
      _scrollToSearchMatch();
    } else if (resetScrollPosition) {
      // 没有搜索结果且需要重置滚动位置时，滚动到顶部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
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

    // 更新当前章节 - 使用 addPostFrameCallback 避免在构建阶段调用 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _currentChapter = targetChapter;
        });
        // 更新 Agent 阅读上下文中的章节信息
        ref.read(readingContextProvider.notifier).state = ReadingContext(
          novelTitle: widget.novel.title,
          chapterTitle: targetChapter.title,
          novelUrl: widget.novel.url,
        );
      }
    });

    // 等待一帧确保状态更新已生效
    await Future.delayed(const Duration(milliseconds: 50));

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
    final currentIndex =
        widget.chapters.indexWhere((c) => c.url == _currentChapter.url);
    if (currentIndex > 0) {
      _navigateToChapter(widget.chapters[currentIndex - 1]);
    } else {
      ToastUtils.showInfo('已经是第一章了', context: context);
    }
  }

  void _goToNextChapter() {
    final currentIndex =
        widget.chapters.indexWhere((c) => c.url == _currentChapter.url);
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

  // 显示阅读设置对话框（合并字体大小、文字亮度、滚动速度）
  void _showReaderSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁用空白区域点击关闭
      builder: (context) => ReaderSettingsDialog(
        initialFontSize: _fontSize ?? 18.0,
        initialTextBrightness: _textBrightness ?? 1.0,
        initialScrollSpeed: _scrollSpeed ?? 1.0,
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
    // 使用 ref.watch 监听设置状态变化
    final settingsState = ref.watch(readerSettingsStateNotifierProvider);
    _fontSize = settingsState.value?.fontSize ?? 18.0;
    _scrollSpeed = settingsState.value?.scrollSpeed ?? 1.0;
    _textBrightness = settingsState.value?.textBrightness ?? 1.0;

    // 使用 ref.watch 监听编辑模式状态
    final isEditMode = ref.watch(readerEditModeProvider);

    // ⭐ 关键修复：监听章节内容状态，确保内容加载后UI重建（修复空白页面问题）
    final contentState = ref.watch(chapterContentStateNotifierProvider);

    // ⭐ 关键修复：直接使用 contentState.content，而不是 _content getter
    // _content getter 内部使用 ref.read()，不会触发 UI 重建
    // 这里已经通过 ref.watch(chapterContentStateNotifierProvider) 建立了响应式依赖
    final content = contentState.content;
    final paragraphs =
        content.split('\n').where((p) => p.trim().isNotEmpty).toList();

    return AgentFloatingShell(
      scenarioId: ScenarioIds.writing,
      child: Scaffold(
        // 直接返回 Scaffold，不使用 ChangeNotifierProvider 包装
        appBar: ReaderAppBar(
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
        body: _buildBody(context, isEditMode, paragraphs, content),
        floatingActionButton: content.isEmpty
            ? null
            : ReaderActionButtons(
                isAutoScrolling: isAutoScrolling, // Mixin getter
                isAutoScrollPaused: isAutoScrollPaused, // Mixin getter
                onToggleAutoScroll: toggleAutoScroll, // Mixin method
              ),
      ),
    );
  }

  /// 构建阅读器主体内容
  Widget _buildBody(
    BuildContext context,
    bool isEditMode,
    List<String> paragraphs,
    String content,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return ReaderErrorView(
        errorMessage: _errorMessage,
        onRetry: () => _loadChapterContent(resetScrollPosition: false),
      );
    }

    // 新增：检查内容是否为空（修复空白页面问题）
    if (!_isLoading &&
        content.trim().isEmpty &&
        paragraphs.isEmpty) {
      return ReaderErrorView(
        errorMessage: '章节内容为空，请尝试刷新或联系开发者',
        onRetry: () => _loadChapterContent(
          resetScrollPosition: false,
          forceRefresh: true,
        ),
      );
    }

    final currentIndex = _currentChapterIndex;
    final hasPrevious = currentIndex > 0;
    final hasNext =
        currentIndex != -1 && currentIndex < widget.chapters.length - 1;

    return Stack(
      children: [
        // 主要内容区域
        ReaderContentView(
          paragraphs: paragraphs,
          fontSize: _fontSize ?? 18.0,
          textBrightness: _textBrightness ?? 1.0,
          isEditMode: isEditMode,
          isAutoScrolling: isAutoScrolling,
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
        // 固定在底部的章节切换按钮
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ReaderBottomBar(
            currentIndex: currentIndex,
            totalChapters: widget.chapters.length,
            hasPrevious: hasPrevious,
            hasNext: hasNext,
            onPreviousChapter: _goToPreviousChapter,
            onNextChapter: _goToNextChapter,
          ),
        ),
      ],
    );
  }

  // 注意：插图处理相关方法已迁移（IllustrationHandlerMixin 已移除）

  // ========== AutoScrollMixin 抽象字段实现 ==========

  @override
  ScrollController get scrollController => _scrollController;

  @override
  double get scrollSpeed => _scrollSpeed ?? 1.0;
}

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
import '../widgets/theme_mode_dialog.dart'; // 主题模式选择对话框（亮色/暗色/跟随系统）
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

  // 当前章节的段落标注（key = 段落序号）
  Map<int, ParagraphAnnotation> _annotations = {};

  // ========== 按标注重写（annotation_rewrite 场景会话驱动）==========
  /// 改写 agent 正在运行（本地态；用于控制 FAB 显示转圈 + 防重复点击）。
  /// 实际跑动状态由 [ScenarioSession.isRunning] 提供，过程可在 agent 对话窗口查看。
  bool _isRewriteRunning = false;

  // 段落级延迟揭示动画：
  // - agent 写库 → ref.listen diff 新旧段落 → 待揭示段落登记到 _pendingReveals
  // - 显示层对该段落保留旧文本；滚动进入视口后 ParagraphWidget 启动
  //   淡出+打字机，并回调 onParagraphRevealStart 把索引记入 _revealedParas
  // - 切章/退出即丢（不持久化），重新进入直接显示新文本
  final Map<int, String> _pendingReveals = {};
  final Set<int> _revealedParas = {};
  List<String> _oldParasCache = const [];

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
    _bannerTimer?.cancel();
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
    await _loadAnnotations();

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
  /// 加载当前章节的段落标注（key = 段落序号）
  Future<void> _loadAnnotations() async {
    try {
      final repo = ref.read(paragraphAnnotationRepositoryProvider);
      final list = await repo.getForChapter(_currentChapter.url);
      if (!mounted) return;
      setState(() {
        _annotations = {for (final a in list) a.paragraphIndex: a};
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
  void _showAnnotationEditor(int index, String paragraph) {
    ParagraphAnnotationSheet.show(
      context,
      paragraphPreview: ParagraphAnnotation.buildPreview(paragraph),
      existing: _annotations[index],
      onSave: (content) => _saveAnnotation(index, paragraph, content),
      onDelete: () => _deleteAnnotation(index),
    );
  }

  /// 保存段落标注（新增或更新），返回是否成功
  Future<bool> _saveAnnotation(
      int index, String paragraph, String content) async {
    try {
      final repo = ref.read(paragraphAnnotationRepositoryProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = _annotations[index];
      final annotation = ParagraphAnnotation(
        novelUrl: widget.novel.url,
        chapterUrl: _currentChapter.url,
        paragraphIndex: index,
        paragraphPreview: ParagraphAnnotation.buildPreview(paragraph),
        content: content,
        createdAt: old?.createdAt ?? now,
        updatedAt: now,
      );

      final id = await repo.upsert(annotation);
      if (!mounted) return false;
      setState(() {
        _annotations[index] = annotation.copyWith(id: id);
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
  Future<bool> _deleteAnnotation(int index) async {
    final existing = _annotations[index];
    if (existing?.id == null) return false;
    try {
      final repo = ref.read(paragraphAnnotationRepositoryProvider);
      await repo.delete(existing!.id!);
      if (!mounted) return false;
      setState(() {
        _annotations.remove(index);
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
  /// 运行中：禁止重复点击，编辑模式下拒绝启动。
  /// 成功后清理本章节标注（已被 AI 消化，保留会误导「还有待重写标注」）。
  Future<void> _startAnnotationRewrite() async {
    if (_isRewriteRunning) return;
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
        // 标注已被 AI 重写消化 → 清理（DB + 内存）
        await _clearAnnotationsAfterRewrite();
        if (!mounted) return;
        ToastUtils.showSuccess(
          '已按标注重写本章（${outcome.updateCount} 处修改）',
          context: context,
        );
        // 顶部 banner 5s 后自动消失
        _bannerTimer?.cancel();
        setState(() => _showRewriteBanner = true);
        _bannerTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _showRewriteBanner = false);
        });
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

  /// 重写成功后清理本章节标注（DB + 内存状态）
  Future<void> _clearAnnotationsAfterRewrite() async {
    try {
      await ref
          .read(paragraphAnnotationRepositoryProvider)
          .deleteByChapter(_currentChapter.url);
    } catch (e, st) {
      LoggerService.instance.e(
        '清理章节标注失败: $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['reader', 'rewrite', 'clear_annotations', 'failed'],
      );
    }
    if (mounted) setState(() => _annotations = {});
  }

  /// ref.listen 回调：agent 写库 → diff 新旧段落 → 登记待揭示段落
  ///
  /// 段落数量不变：逐项比对，变化段落登记 pending（若已被揭示过则先移出
  /// revealed 以允许再次动画）。
  /// 段落数量变化（合并/拆分段落）：无法对齐索引 → 回退为瞬时替换（不动画，
  /// 显示层直接用新内容，因为 pending 为空时 display == new）。
  void _onContentChangedForRewrite(
      ChapterContentState? prev, ChapterContentState next) {
    if (!_isRewriteRunning) {
      // 非 agent 期间的内容变化（用户编辑保存/切章/刷新）：清空揭示状态
      if (_pendingReveals.isNotEmpty || _revealedParas.isNotEmpty) {
        _pendingReveals.clear();
        _revealedParas.clear();
        _oldParasCache = const [];
      }
      return;
    }
    if (prev == null || prev.content == next.content) return;

    final oldParas =
        prev.content.split('\n').where((p) => p.trim().isNotEmpty).toList();
    final newParas =
        next.content.split('\n').where((p) => p.trim().isNotEmpty).toList();

    if (oldParas.length != newParas.length) {
      LoggerService.instance.d(
        '标注重写 段落数变化 (${oldParas.length} → ${newParas.length})，回退瞬时替换',
        category: LogCategory.ai,
        tags: ['reader', 'rewrite', 'fallback_instant'],
      );
      _pendingReveals.clear();
      _revealedParas.clear();
      return;
    }

    _oldParasCache = oldParas;
    var changed = 0;
    for (var i = 0; i < newParas.length; i++) {
      if (oldParas[i] == newParas[i]) continue;
      changed++;
      // 允许已揭示段落再次动画（agent 又改了一次）
      _revealedParas.remove(i);
      _pendingReveals[i] = newParas[i];
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

  /// ParagraphWidget 启动揭示动画时回调。**不 setState**：
  /// ListView.builder 的 itemBuilder 闭包持有 Set 引用，滚动重建时读到的
  /// 是最新内容；可见项动画不受重建打断，滚走再滚回直接静态显示新文本。
  void _onParagraphRevealStart(int index) {
    _revealedParas.add(index);
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

    // 监听内容变化 → agent 写库时 diff 段落并登记待揭示
    ref.listen<ChapterContentState>(
      chapterContentStateNotifierProvider,
      _onContentChangedForRewrite,
    );

    // ⭐ 关键修复：直接使用 contentState.content，而不是 _content getter
    // _content getter 内部使用 ref.read()，不会触发 UI 重建
    // 这里已经通过 ref.watch(chapterContentStateNotifierProvider) 建立了响应式依赖
    final content = contentState.content;
    final paragraphs =
        content.split('\n').where((p) => p.trim().isNotEmpty).toList();

    // 有标注时 AI 悬浮按钮自动切换为「按标注重写」入口（点击启动改写并打开
    // 对话窗口查看过程）；无标注时保持默认「打开写作对话」行为。
    final hasAnnotations = _annotations.isNotEmpty;

    return AgentFloatingShell(
      scenarioId: ScenarioIds.writing,
      overrideChild: hasAnnotations ? _buildRewriteFabChild() : null,
      overrideOnTap: hasAnnotations ? _startAnnotationRewrite : null,
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

    // 计算待揭示段落：未揭示的索引 → 旧文本占位 + revealNewText 触发子 Widget 动画
    final activeReveals = <int, String>{};
    if (!isEditMode) {
      for (final entry in _pendingReveals.entries) {
        final i = entry.key;
        if (_revealedParas.contains(i)) continue;
        if (i >= paragraphs.length) continue;
        if (i < _oldParasCache.length) {
          paragraphs[i] = _oldParasCache[i];
        }
        activeReveals[i] = entry.value;
      }
    }

    return Stack(
      children: [
        // 主要内容区域（段落级延迟揭示：进入视口才淡出+打字机替换）
        ReaderContentView(
          paragraphs: paragraphs,
          fontSize: _fontSize ?? 18.0,
          textBrightness: _textBrightness ?? 1.0,
          isEditMode: isEditMode,
          isAutoScrolling: isAutoScrolling,
          annotations: _annotations,
          onParagraphLongPress: _showAnnotationEditor,
          pendingReveals: activeReveals,
          onParagraphRevealStart: _onParagraphRevealStart,
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
        // 顶部「已按标注重写」banner（重写成功后短暂展示，可一键还原）
        if (_showRewriteBanner)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: _buildRewriteBanner(context),
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

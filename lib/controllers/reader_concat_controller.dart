/// ReaderConcatController - 无限滚动拼接控制器
///
/// 自 reader_screen.dart 的 `_ReaderScreenState` 抽离，职责：
/// - 章节块列表（[ReaderChapterBlock]）与块起点 GlobalKey 登记
/// - 块几何缓存：实测块高 / 起点偏移（采样、推导、失效）
/// - 滚到顶/底自动拼接前/后章节（冷却 / 方向互斥 / Offstage 测高 / 滚动补偿）
/// - 视口当前章检测 + 章节块窗口回收（长会话内存治理）
/// - 章内阅读位置锚点：滚动采样 + 节流落库 + 重开恢复跳转
///
/// 组织方式与 [ReaderContentController] 一致：普通类，依赖经构造注入；
/// 不持有 BuildContext、不自持状态所有权之外的副作用——需要 UI 重建时
/// 调用注入的 `setState` 回调（即阅读页的 setState），挂载判断经
/// `isMounted` 回调，与原先 State 内 `if (mounted) setState(...)`
/// 的语义一一对应。
///
/// 时序注意：章节块与全局内容状态（chapterContentStateNotifierProvider）
/// 的同步入口是 [syncCurrentBlockFrom]，它必须在阅读页 build 内调用，
/// 原因见其 doc 注释。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/database_providers.dart';
import '../core/providers/reader_edit_mode_provider.dart';
import '../core/providers/reader_state_providers.dart';
import '../models/chapter.dart';
import '../models/reading_anchor.dart';
import '../services/logger_service.dart';
import '../utils/reading_anchor_math.dart';
import '../widgets/reader/reader_chapter_segment.dart';

/// 已拼接进阅读视图的章节内容块
class ReaderChapterBlock {
  final Chapter chapter;

  /// 原始正文（快照/编辑保存/全局内容状态同步使用，保留原始格式）
  final String rawContent;

  /// 展示段落（按 '\n' 拆 + 过滤空行，与显示层一致）
  late final List<String> paragraphs =
      ReaderChapterSegment.splitParagraphs(rawContent);

  ReaderChapterBlock({required this.chapter, required this.rawContent});
}

/// 拼接方向
enum ReaderConcatDirection { none, next, prev }

/// 无限滚动拼接 + 块几何缓存/回收 + 阅读锚点采样恢复
class ReaderConcatController {
  // ========== 注入依赖 ==========
  final WidgetRef _ref;
  final ScrollController _scrollController;

  /// 阅读页挂载判断（对应原 State.mounted）
  final bool Function() _isMounted;

  /// 阅读页 setState（控制器状态变化需要重建 UI 时调用）
  final void Function(VoidCallback fn) _setState;

  /// 当前章实时读取（阅读页在拼接/导航中会切换当前章）
  final Chapter Function() _currentChapter;

  /// 章节列表实时读取（= ReaderScreen.widget.chapters）
  final List<Chapter> Function() _chapters;

  /// 小说 URL 实时读取（锚点落库使用）
  final String Function() _novelUrl;

  /// 加载拼接章节内容（缓存优先，未命中走 HeadlessWebView；阅读页负责
  /// 抓取期间暂停/恢复预加载）
  final Future<String> Function(Chapter chapter) _loadBlockContent;

  /// 视口滚动跨入新章节时的回调（阅读页据其同步标题/进度/标注/全局内容状态）
  final void Function(Chapter chapter) _onCurrentChapterDetected;

  /// 下一章拼接上屏（extent 增长）后的回调：接续自动滚动
  final VoidCallback _onAppendApplied;

  ReaderConcatController({
    required WidgetRef ref,
    required ScrollController scrollController,
    required bool Function() isMounted,
    required void Function(VoidCallback fn) setState,
    required Chapter Function() currentChapter,
    required List<Chapter> Function() chapters,
    required String Function() novelUrl,
    required Future<String> Function(Chapter chapter) loadBlockContent,
    required void Function(Chapter chapter) onCurrentChapterDetected,
    required VoidCallback onAppendApplied,
  })  : _ref = ref,
        _scrollController = scrollController,
        _isMounted = isMounted,
        _setState = setState,
        _currentChapter = currentChapter,
        _chapters = chapters,
        _novelUrl = novelUrl,
        _loadBlockContent = loadBlockContent,
        _onCurrentChapterDetected = onCurrentChapterDetected,
        _onAppendApplied = onAppendApplied;

  // ========== 章节块与拼接状态（自 _ReaderScreenState 迁入） ==========

  /// 已拼接进阅读视图的章节块（按显示顺序）
  List<ReaderChapterBlock> _blocks = [];

  /// 章节起点标记的 GlobalKey（key = 章节 URL），供当前章检测与重定位
  final Map<String, GlobalKey> _blockStartKeys = {};

  /// 拼接进行中的方向（两方向互斥，进行中不再触发新拼接）
  ReaderConcatDirection _concatDirection = ReaderConcatDirection.none;

  /// 待插入的上一章块（先 Offstage 测高，再插入 + 滚动补偿）
  ReaderChapterBlock? _pendingPrependBlock;
  final GlobalKey _prependMeasureKey = GlobalKey();

  /// 拼接失败标记（正文区显示重试入口）
  bool _prevConcatFailed = false;
  bool _nextConcatFailed = false;

  /// 上次结构变化（拼接/失败）时间，作为冷却防止边缘反复触发
  DateTime _lastConcatAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 距顶/底多远（像素）即触发拼接
  static const double _concatEdgeTriggerPx = 600;

  /// 章节切换检测锚点：章节起点越过「视口顶 + 此值」即视为进入该章
  static const double _chapterAnchorPx = 96;

  /// 两次拼接动作之间的最小间隔
  static const Duration _concatCooldown = Duration(milliseconds: 800);

  // ----- 章节块内存回收（窗口裁剪） -----
  /// 各章节块的实测高度（key = 章节 URL）：滚过章节边界时由相邻起点标记
  /// 采样累计。顶部回收用它补偿滚动位置；字体变化/正文刷新即失效。
  final Map<String, double> _knownBlockHeights = {};

  /// 各章节起点的内容偏移（key = 章节 URL）：可测标记直接采样，
  /// 不可测时由相邻块高推导（首块恒为顶部 padding）。
  /// 当前章检测基于它——不依赖标记是否还在布局里（ListView 缓存区
  /// 只有几百像素，整章之外的上/下章标记早已销毁）。
  final Map<String, double> _blockStartOffsets = {};

  /// 章节块保留窗口：当前章前后各保留多少章，超出即回收正文内存
  static const int _keepBlocksPerSide = 3;

  /// 正文 ListView 的顶部 padding（回收补偿量 = 顶部 padding + Σ块高）
  static const double _contentTopPadding = 16.0;

  /// 字体变化检测（变更即清空块高缓存）
  double? _lastSeenFontSize;

  // ========== 章内阅读位置锚点（自 _ReaderScreenState 迁入） ==========
  /// 最近一次采样到的锚点（滚动时持续更新，退出阅读页时兜底落库）
  ReadingAnchor? _lastReadingAnchor;

  /// 上次锚点落库时间（节流，避免高频滚动反复写库）
  DateTime _lastAnchorWriteAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 锚点落库最小间隔
  static const Duration _anchorWriteInterval = Duration(seconds: 5);

  /// 恢复跳转进行中：跳转自身触发的滚动不采样、不落库
  bool _isRestoringAnchor = false;

  /// 恢复跳转的最大「估算→跳转」迭代轮数（目标段落进入缓存区即精确校正）
  static const int _anchorRestoreMaxAttempts = 4;

  // ========== 只读快照（供阅读页 build 展示） ==========

  /// 已拼接章节块（按显示顺序）。UI 层只读；变更一律经本控制器方法。
  List<ReaderChapterBlock> get blocks => _blocks;

  /// 章节起点标记表（ReaderContentView 渲染分隔线时挂 key 用）
  Map<String, GlobalKey> get blockStartKeys => _blockStartKeys;

  /// 拼接进行中的方向（正文区据其显示「正在加载下一章…」提示）
  ReaderConcatDirection get concatDirection => _concatDirection;

  /// 待插入的上一章块（非 null 时正文区渲染 Offstage 测高层）
  ReaderChapterBlock? get pendingPrependBlock => _pendingPrependBlock;

  /// 上一章 Offstage 测量层 key
  GlobalKey get prependMeasureKey => _prependMeasureKey;

  /// 拼接失败标记（正文区显示重试入口）
  bool get prevConcatFailed => _prevConcatFailed;
  bool get nextConcatFailed => _nextConcatFailed;

  /// 最近一次采样到的阅读锚点（退出阅读页时兜底落库用）
  ReadingAnchor? get lastReadingAnchor => _lastReadingAnchor;

  // ========== 公开操作 ==========

  /// 滚动回调：当前章检测（经 [_onCurrentChapterDetected] 通知阅读页切换）
  /// + 边缘拼接触发 + 阅读锚点采样。三步顺序与原实现一致，不可调整。
  void handleScrollChanged() {
    if (!_isMounted() || _blocks.isEmpty) return;
    if (_ref.read(readerEditModeProvider)) return;
    final detected = _detectCurrentChapterByViewport();
    if (detected != null) {
      _onCurrentChapterDetected(detected);
    }
    _maybeTriggerConcat();
    _trackReadingAnchor();
  }

  /// 显式切章导航时重置拼接状态：导航是"单章视图"重建，拼接内容全部丢弃。
  /// 须在阅读页 setState 内调用（本方法只改数据，不触发重建）。
  void resetForNavigation() {
    _blocks = [];
    _blockStartKeys.clear();
    _knownBlockHeights.clear();
    _blockStartOffsets.clear();
    _concatDirection = ReaderConcatDirection.none;
    _pendingPrependBlock = null;
    _prevConcatFailed = false;
    _nextConcatFailed = false;
  }

  /// 取章节起点标记 GlobalKey（无则登记），供分段构建时挂到分隔线上。
  /// 与原实现一致：在 build 组装分段时惰性登记。
  GlobalKey registerStartKey(String chapterUrl) =>
      _blockStartKeys.putIfAbsent(chapterUrl, () => GlobalKey());

  /// 按章节 URL 查块的原始正文（当前章检测切章时同步全局内容状态用）
  String? rawContentOf(String chapterUrl) {
    for (final block in _blocks) {
      if (block.chapter.url == chapterUrl) return block.rawContent;
    }
    return null;
  }

  /// 重试入口点击后先清失败标记（配合阅读页 setState 触发重建）
  void clearPrevConcatFailure() => _prevConcatFailed = false;

  /// 重试入口点击后先清失败标记（配合阅读页 setState 触发重建）
  void clearNextConcatFailure() => _nextConcatFailed = false;

  /// 字体大小变化 → 全部内容重新排版，块高与起点偏移缓存整体失效。
  ///
  /// ⚠️ 必须在阅读页 build 内调用（内部维护「上次见过的字号」，
  /// 按需清缓存；幂等，可每帧调用）。
  void invalidateGeometryForFontSize(double fontSize) {
    if (_lastSeenFontSize != null && _lastSeenFontSize != fontSize) {
      _knownBlockHeights.clear();
      _blockStartOffsets.clear();
    }
    _lastSeenFontSize = fontSize;
  }

  /// 把全局内容状态同步进章节块：
  /// - 导航重置后的首章装载（块缺失 → 建块）
  /// - 刷新 / 编辑保存 / 改写落库（同章内容变化 → 原位替换，不移动视野）
  ///
  /// ⚠️ 时序约束：必须在阅读页 build 内、分段组装之前**同步**调用，
  /// 不能改为 ref.listen 回调或任何异步时机。原因：loadChapter 的装载
  /// 序列是「setCurrentContext → setLoading(true) → clearContent → 抓取 →
  /// setContent → setLoading(false)」多次离散赋值，Riverpod 监听器会在
  /// 每次赋值时同步触发；若在监听器里同步块列表，会观察到「新章节上下文
  /// + 旧章节内容」的中间态（setCurrentContext 已写入、clearContent 尚未
  /// 执行），把旧内容错建成新章节的块。而 build 只在状态“落定”后的帧
  /// 边界执行（此时要么 isLoading=true、要么内容已与当前章一致），天然
  /// 规避中间态。每帧重复调用幂等：块已存在且内容相同即原地返回。
  void syncCurrentBlockFrom(ChapterContentState contentState) {
    final chapter = contentState.currentChapter;
    if (chapter == null || contentState.isLoading) return;
    if (chapter.url != _currentChapter().url) return;
    if (contentState.content.trim().isEmpty) return;

    final index = _blocks.indexWhere((b) => b.chapter.url == chapter.url);
    if (index == -1) {
      _blocks = [
        ReaderChapterBlock(chapter: chapter, rawContent: contentState.content),
      ];
    } else if (_blocks[index].rawContent != contentState.content) {
      // 内容变化（刷新/编辑保存/改写落库）→ 原位替换并失效该块高度缓存
      _blocks[index] =
          ReaderChapterBlock(chapter: chapter, rawContent: contentState.content);
      _knownBlockHeights.remove(chapter.url);
      // 该章之后的块整体位移未知，废弃其起点采样，滚动经过时重新采样
      for (var i = index + 1; i < _blocks.length; i++) {
        _blockStartOffsets.remove(_blocks[i].chapter.url);
      }
    }
  }

  /// 计算章节起点标记相对于滚动内容原点的偏移；标记未布局时返回 null
  double? scrollOffsetOfChapterStart(String chapterUrl) {
    final markerContext = _blockStartKeys[chapterUrl]?.currentContext;
    if (markerContext == null) return null;
    final renderBox = markerContext.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.attached || !renderBox.hasSize) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderBox);
    if (viewport == null) return null;
    final viewportTop = (viewport as RenderBox).localToGlobal(Offset.zero).dy;
    final markerTop = renderBox.localToGlobal(Offset.zero).dy;
    return _scrollController.offset + (markerTop - viewportTop);
  }

  /// 视口贴近顶部 → 拼接上一章；贴近底部 → 拼接下一章
  void _maybeTriggerConcat() {
    if (_concatDirection != ReaderConcatDirection.none) return;
    if (_pendingPrependBlock != null) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    if (DateTime.now().difference(_lastConcatAt) < _concatCooldown) return;

    if (position.pixels <= _concatEdgeTriggerPx) {
      prependPreviousChapter();
    } else if (position.pixels >=
        position.maxScrollExtent - _concatEdgeTriggerPx) {
      appendNextChapter();
    }
  }

  /// 当前章检测（基于章节起点的内容偏移）：
  /// 当前章 = 「视口顶 + 锚点」之上起点最近的章节块。
  ///
  /// 起点偏移来源分三层，保证视口外的章节也能参与判定：
  /// 1. 采样——分隔线标记进入缓存区时直接实测；
  /// 2. 推导——首块恒为顶部 padding，其余由相邻块高前向/后向推导；
  /// 3. 兜底——都未知（如刚改字体后未重滚）的章节不参判，保持当前章不变。
  ///
  /// 返回应切换到的章节（与实时当前章不同时）；无需切换返回 null。
  /// 采样/推导的缓存写入照常发生。
  Chapter? _detectCurrentChapterByViewport() {
    if (_blocks.length <= 1) return null;

    // 采样：可测标记 → 实测起点偏移；相邻两个可测标记 → 实测块高
    int? lastMeasuredIndex;
    var lastMeasuredOffset = 0.0;
    for (var i = 0; i < _blocks.length; i++) {
      final markerContext =
          _blockStartKeys[_blocks[i].chapter.url]?.currentContext;
      if (markerContext == null) continue;
      final renderBox = markerContext.findRenderObject();
      if (renderBox is! RenderBox ||
          !renderBox.attached ||
          !renderBox.hasSize) {
        continue;
      }
      final viewport = RenderAbstractViewport.maybeOf(renderBox);
      if (viewport == null) continue;
      final viewportTop = (viewport as RenderBox).localToGlobal(Offset.zero).dy;
      final visualY = renderBox.localToGlobal(Offset.zero).dy - viewportTop;
      final contentOffset = _scrollController.offset + visualY;

      _blockStartOffsets[_blocks[i].chapter.url] = contentOffset;
      final lm = lastMeasuredIndex;
      if (lm != null && lm == i - 1) {
        final h = contentOffset - lastMeasuredOffset;
        if (h > 0) {
          _knownBlockHeights[_blocks[lm].chapter.url] = h;
        }
      }
      lastMeasuredIndex = i;
      lastMeasuredOffset = contentOffset;
    }

    _deriveBlockStartOffsets();

    // 判定：起点 ≤ 「滚动位置 + 锚点」的最近章节
    Chapter? target;
    var best = double.negativeInfinity;
    final anchor = _scrollController.offset + _chapterAnchorPx;
    for (final block in _blocks) {
      final start = _blockStartOffsets[block.chapter.url];
      if (start == null) continue;
      if (start <= anchor && start > best) {
        best = start;
        target = block.chapter;
      }
    }
    if (target != null && target.url != _currentChapter().url) {
      return target;
    }
    return null;
  }

  /// 用已知块高推导未采样章节的起点偏移
  void _deriveBlockStartOffsets() {
    if (_blocks.isEmpty) return;
    // 首块起点 = 内容原点 + 顶部 padding
    _blockStartOffsets[_blocks.first.chapter.url] ??= _contentTopPadding;
    // 前向：起点(i) = 起点(i-1) + 高度(i-1)
    for (var i = 1; i < _blocks.length; i++) {
      final prevStart = _blockStartOffsets[_blocks[i - 1].chapter.url];
      final h = _knownBlockHeights[_blocks[i - 1].chapter.url];
      if (prevStart != null && h != null) {
        _blockStartOffsets.putIfAbsent(_blocks[i].chapter.url, () => prevStart + h);
      }
    }
    // 后向：起点(i-1) = 起点(i) - 高度(i-1)
    for (var i = _blocks.length - 1; i >= 1; i--) {
      final nextStart = _blockStartOffsets[_blocks[i].chapter.url];
      final h = _knownBlockHeights[_blocks[i - 1].chapter.url];
      if (nextStart != null && h != null) {
        _blockStartOffsets[_blocks[i - 1].chapter.url] ??= nextStart - h;
      }
    }
  }

  /// 回收远离当前章的章节块（保留窗口：前后各 [_keepBlocksPerSide] 章）。
  ///
  /// ListView 只保留视口附近的渲染对象，但 [_blocks] 里的正文文本会随
  /// 会话无限累积，长会话需要窗口裁剪：
  /// - 下方回收（视口之下）：直接移除，无需补偿；滚回去会经 append 重载。
  /// - 上方回收（视口之上）：移除会把下方内容上推，需把滚动位置等量上移。
  ///   补偿量 = 顶部 padding + Σ被移除块高；任一块高度未采样到
  ///   （如刚改过字体）则放弃本次回收，宁晚勿跳。
  void trimDistantBlocks() {
    final currentIdx =
        _blocks.indexWhere((b) => b.chapter.url == _currentChapter().url);
    if (currentIdx == -1 || _blocks.length <= _keepBlocksPerSide * 2 + 1) {
      return;
    }
    final before = _blocks;

    // 下方回收
    final tailFrom = currentIdx + _keepBlocksPerSide + 1;
    if (tailFrom < _blocks.length) {
      for (final b in _blocks.sublist(tailFrom)) {
        _blockStartKeys.remove(b.chapter.url);
        _knownBlockHeights.remove(b.chapter.url);
        _blockStartOffsets.remove(b.chapter.url);
      }
      LoggerService.instance.d(
        '回收尾部章节块: ${_blocks.sublist(tailFrom).map((b) => b.chapter.title).join("、")}',
        category: LogCategory.ui,
        tags: ['reader', 'concat', 'trim'],
      );
      _blocks = _blocks.sublist(0, tailFrom);
    }

    // 上方回收（需被移除块高全部已知才补偿）
    var headTo = currentIdx - _keepBlocksPerSide;
    if (headTo > 0) {
      var removedHeight = _contentTopPadding;
      for (var i = 0; i < headTo; i++) {
        final h = _knownBlockHeights[_blocks[i].chapter.url];
        if (h == null) {
          LoggerService.instance.d(
            '跳过顶部回收：前 $headTo 章块高未全部采样',
            category: LogCategory.ui,
            tags: ['reader', 'concat', 'trim'],
          );
          headTo = 0;
          break;
        }
        removedHeight += h;
      }
      // 视口须明显低于被移除区域末端，避免补偿期间视野异常
      if (headTo > 0 &&
          _scrollController.hasClients &&
          _scrollController.offset > removedHeight + 200) {
        for (final b in _blocks.sublist(0, headTo)) {
          _blockStartKeys.remove(b.chapter.url);
          _knownBlockHeights.remove(b.chapter.url);
          _blockStartOffsets.remove(b.chapter.url);
        }
        LoggerService.instance.d(
          '回收顶部章节块: ${_blocks.sublist(0, headTo).map((b) => b.chapter.title).join("、")} '
          '(补偿 ${removedHeight.round()}px)',
          category: LogCategory.ui,
          tags: ['reader', 'concat', 'trim'],
        );
        _blocks = _blocks.sublist(headTo);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isMounted()) return;
          // 剩余块整体上移被回收区域的高度，起点偏移同步平移
          // （新首块的采样起点恰为补偿量，平移后回到顶部 padding）
          _blockStartOffsets.updateAll((_, off) => off - removedHeight);
          if (!_scrollController.hasClients) return;
          _scrollController.jumpTo(_scrollController.offset - removedHeight);
        });
      }
    }

    if (!identical(before, _blocks)) {
      _setState(() {});
    }
  }

  /// 拼接下一章（滚动接近底部触发）。底部追加不影响上方内容的滚动位置，
  /// 无需补偿。
  Future<void> appendNextChapter({bool force = false}) async {
    if (_concatDirection != ReaderConcatDirection.none) return;
    if (_pendingPrependBlock != null) return;
    if (!force && DateTime.now().difference(_lastConcatAt) < _concatCooldown) {
      return;
    }
    final lastChapter = _blocks.last.chapter;
    final lastIndex =
        _chapters().indexWhere((c) => c.url == lastChapter.url);
    if (lastIndex == -1 || lastIndex >= _chapters().length - 1) {
      return; // 已是最后一章
    }
    final nextChapter = _chapters()[lastIndex + 1];
    if (_blocks.any((b) => b.chapter.url == nextChapter.url)) return;

    _concatDirection = ReaderConcatDirection.next;
    if (_isMounted()) _setState(() {});
    try {
      final content = await _loadBlockContent(nextChapter);
      if (!_isMounted()) return;
      _setState(() {
        _blocks = [
          ..._blocks,
          ReaderChapterBlock(chapter: nextChapter, rawContent: content),
        ];
        _nextConcatFailed = false;
        _lastConcatAt = DateTime.now();
      });
      LoggerService.instance.i(
        '已拼接下一章: ${nextChapter.title}',
        category: LogCategory.ui,
        tags: ['reader', 'concat', 'append'],
      );
      // 新内容上屏（extent 增长）后接续自动滚动：等待加载期间，
      // 自动滚动可能已在旧内容底部触底停止（控制器触底即 stop）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isMounted()) _onAppendApplied();
      });
      // 拼接后窗口外章节块可回收
      trimDistantBlocks();
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '拼接下一章失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ui,
        tags: ['reader', 'concat', 'append', 'failed'],
      );
      _lastConcatAt = DateTime.now();
      if (_isMounted()) {
        _setState(() => _nextConcatFailed = true);
      }
    } finally {
      _concatDirection = ReaderConcatDirection.none;
      if (_isMounted()) _setState(() {});
    }
  }

  /// 拼接上一章（滚动接近顶部触发）。
  ///
  /// 顶部插入会推挤下方内容，直接重建会让视野跳变。这里分两步：
  /// 1. 先把上一章段落放进与正文同宽同构的 Offstage 测量层，测出总高度；
  /// 2. 插入章节块，布局完成后把滚动位置等量下移该高度——
  ///    视野内的段落纹丝不动，实现真正"无限上滚"。
  Future<void> prependPreviousChapter({bool force = false}) async {
    if (_concatDirection != ReaderConcatDirection.none) return;
    if (_pendingPrependBlock != null) return;
    if (!force && DateTime.now().difference(_lastConcatAt) < _concatCooldown) {
      return;
    }
    final firstChapter = _blocks.first.chapter;
    final firstIndex =
        _chapters().indexWhere((c) => c.url == firstChapter.url);
    if (firstIndex <= 0) return; // 已是第一章
    final prevChapter = _chapters()[firstIndex - 1];
    if (_blocks.any((b) => b.chapter.url == prevChapter.url)) return;

    _concatDirection = ReaderConcatDirection.prev;
    if (_isMounted()) _setState(() {});
    try {
      final content = await _loadBlockContent(prevChapter);
      if (!_isMounted()) return;
      _setState(() {
        _pendingPrependBlock =
            ReaderChapterBlock(chapter: prevChapter, rawContent: content);
      });

      final height = await _measurePendingPrependBlock();
      if (!_isMounted()) return;
      final block = _pendingPrependBlock;
      if (block == null) return;
      _setState(() {
        _blocks = [block, ..._blocks];
        _pendingPrependBlock = null;
        _prevConcatFailed = false;
        _lastConcatAt = DateTime.now();
      });
      // 布局完成后补偿滚动位置（插入高度 = 视野下移量）；
      // 已采样的起点偏移同步整体平移，新首块起点回到顶部 padding
      final prependedUrl = block.chapter.url;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;
        _blockStartOffsets.updateAll((_, off) => off + height);
        _blockStartOffsets[prependedUrl] = _contentTopPadding;
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.offset + height);
      });
      // 拼接后窗口外章节块可回收
      trimDistantBlocks();
      LoggerService.instance.i(
        '已拼接上一章: ${prevChapter.title} (补偿 ${height.round()}px)',
        category: LogCategory.ui,
        tags: ['reader', 'concat', 'prepend'],
      );
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '拼接上一章失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ui,
        tags: ['reader', 'concat', 'prepend', 'failed'],
      );
      _lastConcatAt = DateTime.now();
      if (_isMounted()) {
        _setState(() {
          _pendingPrependBlock = null;
          _prevConcatFailed = true;
        });
      }
    } finally {
      _concatDirection = ReaderConcatDirection.none;
      if (_isMounted()) _setState(() {});
    }
  }

  /// 测量 Offstage 测量层中待插入上一章的总高度
  Future<double> _measurePendingPrependBlock() {
    final completer = Completer<double>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) {
        completer.completeError(Exception('阅读页已销毁，测量中止'));
        return;
      }
      final renderBox = _prependMeasureKey.currentContext?.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize) {
        completer.complete(renderBox.size.height);
      } else {
        completer.completeError(Exception('上一章高度测量失败'));
      }
    });
    return completer.future;
  }

  // ========== 章内阅读位置锚点（采样保存 + 重开恢复） ==========

  /// 滚动时持续采样锚点并节流落库。
  ///
  /// 采样走渲染树（SliverList 子节点遍历），布局不可采样时自然跳过；
  /// 恢复跳转期间不采样不落库，避免把中间估算位置写进库。
  void _trackReadingAnchor() {
    if (_isRestoringAnchor) return;
    final anchor = _captureReadingAnchor();
    if (anchor == null) return;
    if (!ReadingAnchorMath.anchorChangedSignificantly(
        _lastReadingAnchor, anchor)) {
      return;
    }
    _lastReadingAnchor = anchor;
    final now = DateTime.now();
    if (now.difference(_lastAnchorWriteAt) < _anchorWriteInterval) return;
    _lastAnchorWriteAt = now;
    unawaited(writeReadingAnchor(anchor));
  }

  /// 立即落库指定锚点（滚动节流写入与退出兜底共用）
  Future<void> writeReadingAnchor(ReadingAnchor anchor) async {
    try {
      await _ref
          .read(novelRepositoryProvider)
          .updateLastReadAnchor(_novelUrl(), anchor);
    } catch (e, stackTrace) {
      LoggerService.instance.w(
        '章内阅读位置锚点写入失败: $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.ui,
        tags: ['reader', 'anchor', 'write-failed'],
      );
    }
  }

  /// 采样当前章内阅读锚点（视口顶所在段落）；渲染树不可采样时返回 null。
  ReadingAnchor? _captureReadingAnchor() {
    if (_blocks.isEmpty) return null;
    if (!_scrollController.hasClients) return null;
    if (_ref.read(readerEditModeProvider)) return null;
    final items = _sampleListItems();
    if (items.isEmpty) return null;
    final topItem =
        ReadingAnchorMath.topVisibleItem(items, _scrollController.offset);
    if (topItem == null) return null;
    return ReadingAnchorMath.anchorFromTopItem(
      topItem: topItem,
      scrollOffset: _scrollController.offset,
      paragraphInfoAt: _paragraphInfoAtFlatIndex,
      chapterUrlOfFlat: _chapterUrlAtFlatIndex,
    );
  }

  // ----- 渲染树采样 -----

  /// 正文 ListView 的 RenderViewport（从章节起点标记向上找），拿不到返回 null
  RenderViewport? _contentViewport() {
    for (final key in _blockStartKeys.values) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport is RenderViewport) return viewport;
    }
    return null;
  }

  /// 采样正文 ListView 全部已布局条目（按扁平索引升序）。
  ///
  /// 走 SliverList 渲染子节点遍历，不依赖段落组件挂 GlobalKey——
  /// 顶部拼接的 Offstage 测高树与正文同构，挂 GlobalKey 会重复注册崩溃。
  List<ReaderListItemSample> _sampleListItems() {
    final viewport = _contentViewport();
    if (viewport == null || !_scrollController.hasClients) return const [];
    final samples = <ReaderListItemSample>[];
    for (var sliver = viewport.firstChild;
        sliver != null;
        sliver = viewport.childAfter(sliver)) {
      // ListView 结构 = SliverPadding(padding) → SliverList
      final RenderSliverMultiBoxAdaptor? adaptor;
      if (sliver is RenderSliverMultiBoxAdaptor) {
        adaptor = sliver;
      } else if (sliver is RenderSliverPadding &&
          sliver.child is RenderSliverMultiBoxAdaptor) {
        adaptor = sliver.child as RenderSliverMultiBoxAdaptor;
      } else {
        adaptor = null;
      }
      if (adaptor == null) continue;
      for (var child = adaptor.firstChild;
          child != null;
          child = adaptor.childAfter(child)) {
        final index = child.parentData is SliverMultiBoxAdaptorParentData
            ? (child.parentData as SliverMultiBoxAdaptorParentData).index
            : null;
        final offset = _contentOffsetOf(child);
        if (index == null || offset == null) continue;
        samples.add(ReaderListItemSample(
          index: index,
          contentOffset: offset,
          height: child.size.height,
        ));
      }
      break;
    }
    samples.sort((a, b) => a.index.compareTo(b.index));
    return samples;
  }

  /// 已布局条目顶在滚动内容坐标系里的偏移（与当前章检测同款换算）
  double? _contentOffsetOf(RenderBox box) {
    if (!box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null || !viewport.attached) return null;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.hasSize) return null;
    if (!_scrollController.hasClients) return null;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final visualY = box.localToGlobal(Offset.zero).dy - viewportTop;
    return _scrollController.offset + visualY;
  }

  // ----- 扁平条目 ↔ 章内段落换算 -----
  // 与 ReaderContentView 的条目序列一致：每章 = 分隔线 + 段落，末位尾部占位

  /// 扁平条目序号 →（章节 URL, 章内段落序号）；分隔线/尾部占位返回 null
  (String, int)? _paragraphInfoAtFlatIndex(int flatIndex) {
    var cursor = 0;
    for (final block in _blocks) {
      final inSegment = flatIndex - cursor - 1; // 跳过分隔线
      if (inSegment >= 0 && inSegment < block.paragraphs.length) {
        return (block.chapter.url, inSegment);
      }
      cursor += 1 + block.paragraphs.length;
    }
    return null;
  }

  /// 扁平条目序号 → 所属章节 URL（分隔线归属其后章节；尾部占位返回 null）
  String? _chapterUrlAtFlatIndex(int flatIndex) {
    var cursor = 0;
    for (final block in _blocks) {
      if (flatIndex <= cursor + block.paragraphs.length) {
        return block.chapter.url;
      }
      cursor += 1 + block.paragraphs.length;
    }
    return null;
  }

  /// 锚点目标条目的扁平索引（段落越界 clamp 到末段；章不在块列表返回 null）
  int? _targetFlatIndex(ReadingAnchor anchor) {
    var cursor = 0;
    for (final block in _blocks) {
      if (block.chapter.url == anchor.chapterUrl) {
        if (block.paragraphs.isEmpty) return cursor;
        final paraIdx = anchor.paragraphIndex
            .clamp(0, block.paragraphs.length - 1)
            .toInt();
        return cursor + 1 + paraIdx;
      }
      cursor += 1 + block.paragraphs.length;
    }
    return null;
  }

  /// 恢复跳转：设置「恢复进行中」窗口并执行迭代定位（估算→跳转→精确校正）。
  ///
  /// 锚点读取与守卫判断（章节匹配/编辑模式/搜索跳转互斥）由阅读页负责，
  /// 这里只负责跳转执行与窗口管理——窗口内的滚动不采样、不落库。
  /// 收敛（目标条目实测到位）返回 true。
  Future<bool> restoreAnchor(ReadingAnchor anchor) async {
    _isRestoringAnchor = true;
    try {
      return await _jumpToAnchor(anchor);
    } finally {
      _isRestoringAnchor = false;
    }
  }

  /// 按锚点迭代定位并跳转；收敛（目标条目实测到位）返回 true。
  ///
  /// 目标段落通常在 ListView 缓存区外（未布局），无法直接测偏移：
  /// 用已布局条目线性外推估算偏移 → 跳转 → 目标进入缓存区后按实测
  /// 偏移精确校正，最多迭代 [_anchorRestoreMaxAttempts] 轮。
  Future<bool> _jumpToAnchor(ReadingAnchor anchor) async {
    // 等内容首帧布局完成（loadChapter 完成时 ListView 可能还没构建）
    await WidgetsBinding.instance.endOfFrame;
    final targetFlat = _targetFlatIndex(anchor);
    if (targetFlat == null || !_scrollController.hasClients) return false;

    for (var attempt = 0; attempt < _anchorRestoreMaxAttempts; attempt++) {
      final items = _sampleListItems();
      final exact = ReadingAnchorMath.locateItem(items, targetFlat);
      if (exact != null) {
        // 目标已布局：按实测偏移精确校正（含段内比例）
        final maxOffset = _scrollController.position.maxScrollExtent;
        final precise =
            (exact.contentOffset + anchor.paragraphRatio * exact.height)
                .clamp(0.0, maxOffset)
                .toDouble();
        if ((_scrollController.offset - precise).abs() >= 0.5) {
          _scrollController.jumpTo(precise);
          await WidgetsBinding.instance.endOfFrame;
          if (!_isMounted() || !_scrollController.hasClients) return false;
        }
        return true;
      }
      // 未布局：外推估算并跳转，让目标进入 ListView 缓存区
      final estimate = ReadingAnchorMath.estimateJumpOffset(
        items: items,
        targetIndex: targetFlat,
        intraRatio: anchor.paragraphRatio,
      );
      if (estimate == null) return false;
      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController
          .jumpTo(estimate.clamp(0.0, maxOffset).toDouble());
      await WidgetsBinding.instance.endOfFrame;
      if (!_isMounted() || !_scrollController.hasClients) return false;
    }
    LoggerService.instance.w(
      '章内阅读位置恢复未收敛: targetFlat=$targetFlat',
      category: LogCategory.ui,
      tags: ['reader', 'anchor', 'restore-unconverged'],
    );
    return false;
  }
}

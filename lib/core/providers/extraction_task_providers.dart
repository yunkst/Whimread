/// 提取任务状态 Provider
///
/// 提供 Agent 提取任务的状态订阅入口，任意 APP 页面（包括 WebView 浏览器页、
/// 书架、设置等）都可以订阅此 Provider 显示任务进度。
///
/// ## 设计目的
///
/// 旧架构中，提取任务状态只存在于 Agent 事件流里（`NovelAgentService.events`），
/// 只有 AgentChatDialog 订阅。
/// 改造后，提取任务使用 Headless WebView 后台执行，
/// 用户可能在 AgentChatDialog 关闭、页面切换时也想看到任务状态。
///
/// ## 数据流
///
/// ```
/// WebViewExtractScenario.executeTool()
///   ↓
/// 读取 extractionTaskNotifierProvider（通过 ref.read 获取 notifier）
///   ↓
/// 更新状态（setState）
///   ↓
/// 任意页面 ref.watch(extractionTaskProvider) 收到通知
/// ```
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 提取阶段
enum ExtractionPhase {
  /// 空闲（无任务）
  idle,

  /// 正在分析页面（get_page_info / navigate_to）
  analyzing,

  /// 正在执行 JS（execute_js）
  executing,

  /// 正在保存脚本（save_script）
  saving,

  /// 任务完成
  done,

  /// 任务错误
  error,
}

/// 提取任务状态
class ExtractionTaskState {
  /// 当前阶段
  final ExtractionPhase phase;

  /// 当前正在处理的域名
  final String? domain;

  /// 当前正在执行的工具名
  final String? currentTool;

  /// 累计执行轮数
  final int roundCount;

  /// 错误信息（phase=error 时）
  final String? error;

  /// 任务开始时间
  final DateTime? startedAt;

  /// 任务完成时间
  final DateTime? completedAt;

  const ExtractionTaskState({
    this.phase = ExtractionPhase.idle,
    this.domain,
    this.currentTool,
    this.roundCount = 0,
    this.error,
    this.startedAt,
    this.completedAt,
  });

  /// 是否正在进行中
  bool get isRunning =>
      phase != ExtractionPhase.idle &&
      phase != ExtractionPhase.done &&
      phase != ExtractionPhase.error;

  ExtractionTaskState copyWith({
    ExtractionPhase? phase,
    String? domain,
    String? currentTool,
    int? roundCount,
    String? error,
    DateTime? startedAt,
    DateTime? completedAt,
    bool clearError = false,
    bool clearDomain = false,
    bool clearCurrentTool = false,
  }) {
    return ExtractionTaskState(
      phase: phase ?? this.phase,
      domain: clearDomain ? null : (domain ?? this.domain),
      currentTool: clearCurrentTool ? null : (currentTool ?? this.currentTool),
      roundCount: roundCount ?? this.roundCount,
      error: clearError ? null : (error ?? this.error),
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// 提取任务状态管理器
class ExtractionTaskNotifier extends StateNotifier<ExtractionTaskState> {
  ExtractionTaskNotifier() : super(const ExtractionTaskState());

  /// 当前是否空闲（无任务）
  bool get isIdle => state.phase == ExtractionPhase.idle;

  /// 当前是否正在进行中
  bool get isRunning => state.isRunning;

  /// 任务开始
  void start(String domain) {
    state = ExtractionTaskState(
      phase: ExtractionPhase.analyzing,
      domain: domain,
      startedAt: DateTime.now(),
    );
  }

  /// 切换阶段
  void setPhase(ExtractionPhase phase, {String? toolName}) {
    state = state.copyWith(
      phase: phase,
      currentTool: toolName ?? state.currentTool,
    );
  }

  /// 工具开始
  void toolStart(String toolName) {
    state = state.copyWith(
      currentTool: toolName,
    );
  }

  /// 工具结束
  void toolEnd() {
    state = state.copyWith(
      clearCurrentTool: true,
    );
  }

  /// 增加轮数
  void incrementRound() {
    state = state.copyWith(roundCount: state.roundCount + 1);
  }

  /// 任务完成
  void complete() {
    state = state.copyWith(
      phase: ExtractionPhase.done,
      completedAt: DateTime.now(),
      clearCurrentTool: true,
    );
  }

  /// 任务错误
  void fail(String error) {
    state = state.copyWith(
      phase: ExtractionPhase.error,
      error: error,
      completedAt: DateTime.now(),
      clearCurrentTool: true,
    );
  }

  /// 重置（清除）
  void reset() {
    state = const ExtractionTaskState();
  }
}

/// 提取任务状态 Provider
///
/// 任何页面都可以 ref.watch(extractionTaskProvider) 订阅状态。
/// 写入由 `WebViewExtractScenario` 触发（通过 `extractionTaskNotifierProvider`）。
final extractionTaskProvider =
    StateNotifierProvider<ExtractionTaskNotifier, ExtractionTaskState>((ref) {
  return ExtractionTaskNotifier();
});

/// 提取任务 notifier Provider（供场景写入）
final extractionTaskNotifierProvider =
    Provider<ExtractionTaskNotifier>((ref) {
  return ref.watch(extractionTaskProvider.notifier);
});

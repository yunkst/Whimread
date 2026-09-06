/// Agent 对话框编程式展开入口
///
/// 从 [AgentFloatingButton._showChatDialog] 抽出的公共函数，
/// 供 ContextualAgentLauncher 等非悬浮按钮入口复用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_dialog.dart';

class AgentChatLauncherEntry {
  AgentChatLauncherEntry._();

  /// 打开 AgentChatDialog
  ///
  /// [initialDraft] 非空时预填输入框（draftOnly 模式用）。
  /// [scenarioId] 非空时在弹窗前写入 [currentAgentScenarioProvider]——
  /// 页面入口（FAB 等）显式声明"我这个页面该用哪个场景"，避免沿用全局
  /// provider 的残留值（如从浏览器 Tab push 出的阅读页会继承 webview_extract）。
  /// 必须在 showDialog 之前写入：dialog build 时 ref.read(currentSessionProvider)
  /// 依赖此值解析 ScenarioSession。null = 不干预（ContextualAgentLauncher
  /// 已自行写入）。
  static void open(
    BuildContext context, {
    String? initialDraft,
    String? scenarioId,
  }) {
    if (scenarioId != null) {
      // 用 containerOf 在事件回调上下文同步写 provider，
      // 不依赖 ConsumerWidget，也避开 widget 构建期写保护。
      ProviderScope.containerOf(context, listen: false)
          .read(currentAgentScenarioProvider.notifier)
          .state = scenarioId;
    }
    showDialog(
      context: context,
      builder: (context) => AgentChatDialog(initialDraft: initialDraft),
    );
  }
}

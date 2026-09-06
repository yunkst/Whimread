/// 上下文式 Agent 启动器
///
/// 把"按钮点击"转化为"一次准备好上下文的 agent 对话"：
/// 1. 切换当前场景到 [AgentLaunchRequest.scenarioId]
/// 2. 防重入：若该场景已有 agent 在跑，聚焦现有对话框并提示
/// 3. switchSession(scenarioId, null) 触发全新会话（_ensureSessionId 自动新建）
/// 4. 打开 AgentChatDialog（draftOnly 模式预填草稿）
/// 5. autoSend 模式：调 ScenarioSession.sendMessage(draftMessage) 立即发送
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/services/agent_launcher/agent_launch_request.dart';
import 'package:novel_app/services/novel_agent/novel_agent_service.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_launcher_entry.dart';

class ContextualAgentLauncher {
  final Ref _ref;

  ContextualAgentLauncher(this._ref);

  /// 启动一次上下文式 agent 对话
  Future<void> launch(BuildContext context, AgentLaunchRequest request) async {
    final notifier = _ref.read(scenarioSessionsProvider.notifier);

    // 1. 切换场景
    _ref.read(currentAgentScenarioProvider.notifier).state = request.scenarioId;

    // 2. 防重入：该场景已有 agent 运行中 -> 聚焦现有对话框并提示
    final agentService = _ref.read(novelAgentServiceProvider);
    if (agentService.isRunningFor(request.scenarioId)) {
      AgentChatLauncherEntry.open(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上一次提取仍在进行中')),
      );
      return;
    }

    // 3. 触发全新会话：adoptSession(null) 清空 sessionId/状态，
    //    下次 sendMessage 时 _ensureSessionId 自动新建 ChatSession。
    await notifier.switchSession(request.scenarioId, null);

    // 4. 打开对话框；draftOnly 模式预填草稿
    AgentChatLauncherEntry.open(
      context,
      initialDraft:
          request.mode == LaunchMode.draftOnly ? request.draftMessage : null,
    );

    // 5. autoSend 模式：立即发送（草稿作为首条可见 user message）
    if (request.mode == LaunchMode.autoSend) {
      final session = notifier.get(request.scenarioId);
      await session.sendMessage(content: request.draftMessage);
    }
  }
}

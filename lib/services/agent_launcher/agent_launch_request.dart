/// 上下文式 Agent 启动器请求
library;

/// 启动模式
///
/// - [autoSend]：触发后自动发送草稿，agent 立即开跑（草稿作为可见首条 user message）
/// - [draftOnly]：草稿预填到输入框，等用户编辑后手动发送
enum LaunchMode { autoSend, draftOnly }

/// 通用 Agent 启动请求
///
/// 任意按钮点击 -> 注入上下文 -> 新建 agent 对话 -> 预填草稿 -> autoSend/draftOnly。
/// 字段 [context] 由调用方按场景自由填充，启动器本身不解读其内容；
/// 对 webview_extract 场景，currentUrl 等由 ScenarioSession._buildScenarioContext
/// 自动从 providers 读取，context 仅作为 draftMessage 生成的来源。
class AgentLaunchRequest {
  /// 目标场景 ID（'webview_extract' / 'writing'）
  final String scenarioId;

  /// 场景上下文（URL/domain/novel/失败原因/旧脚本…），由调用方填充
  final Map<String, dynamic> context;

  /// 预填草稿（autoSend 下作为首条 user message；draftOnly 下填入输入框）
  final String draftMessage;

  /// 启动模式
  final LaunchMode mode;

  /// 会话标题（可选）
  final String? title;

  AgentLaunchRequest({
    required this.scenarioId,
    required this.context,
    required this.draftMessage,
    required this.mode,
    this.title,
  })  : assert(scenarioId.isNotEmpty, 'scenarioId 不应为空'),
        assert(draftMessage.isNotEmpty, 'draftMessage 不应为空');
}

/// FAB 降级触发 agent 的请求构造器
///
/// 把 FAB 三分支中的"失败/无脚本"情况转化为 AgentLaunchRequest，
/// 分流指令靠 draftMessage 承载（agent 读首条 user message 自行判断目录页）。
library;

import 'package:novel_app/services/agent_launcher/agent_launch_request.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';

/// FAB 降级原因
enum FabFailureReason {
  /// 当前域名无提取脚本
  noScript,

  /// 脚本执行报错（JS 异常 / 超时）
  scriptError,

  /// 脚本返回空结果（可能不在目录页，或脚本失效）
  emptyResult,
}

class FabLaunchRequestBuilder {
  FabLaunchRequestBuilder._();

  /// 构造降级请求
  ///
  /// [errorMessage] 仅 reason==scriptError 时提供（JS 错误信息）。
  static AgentLaunchRequest build({
    required String currentUrl,
    required String domain,
    required String? oldScript,
    required FabFailureReason reason,
    String? errorMessage,
  }) {
    final draftMessage = _buildDraftMessage(
      currentUrl: currentUrl,
      domain: domain,
      reason: reason,
      errorMessage: errorMessage,
    );

    return AgentLaunchRequest(
      scenarioId: ScenarioIds.webviewExtract,
      context: {
        'currentUrl': currentUrl,
        'domain': domain,
        'oldScript': oldScript,
        'failureReason': reason.name,
        if (errorMessage != null) 'errorMessage': errorMessage,
      },
      draftMessage: draftMessage,
      mode: LaunchMode.autoSend,
    );
  }

  static String _buildDraftMessage({
    required String currentUrl,
    required String domain,
    required FabFailureReason reason,
    String? errorMessage,
  }) {
    switch (reason) {
      case FabFailureReason.noScript:
        return '当前站点($domain)还没有提取脚本。'
            '请为目录页 $currentUrl 编写目录提取脚本和正文提取脚本：'
            '先用 get_page_info 确认是否为目录页，'
            '若是目录页则生成 chapter_list_js 并验证，'
            '再 navigate_to 第一章生成验证 chapter_content_js，'
            '最后 save_script 保存。';
      case FabFailureReason.scriptError:
        return '现有目录提取脚本执行失败：${errorMessage ?? "未知错误"}。'
            '请先用 get_page_info 确认当前 $currentUrl 是否为目录页，'
            '若不是请引导用户前往目录页；若是请修复脚本。'
            '旧脚本可由 get_cached_script(domain="$domain") 读取。';
      case FabFailureReason.emptyResult:
        return '现有脚本未提取到章节。请先用 get_page_info 确认当前 '
            '$currentUrl 是否为目录页：若不是，请在回复中引导用户前往小说目录页；'
            '若是目录页，请修复脚本（旧脚本由 get_cached_script(domain="$domain") 读取）。';
    }
  }
}

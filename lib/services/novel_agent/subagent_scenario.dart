/// 子 Agent 场景：AgentScenario 子类
///
/// 与主场景（WritingScenario）的差异：
/// - tools 由 allowedTools 白名单过滤（强制不含 dispatch_subagent）
/// - system prompt 用通用子 Agent 模板（纪律 + 结果格式 + 单层嵌套约束）
/// - executeTool 调用前校验白名单，越权返回 guidanceError
/// - 不持久化、不挂经验记忆（getMemories 返回空）
library;

import 'dart:convert';

import 'agent_scenario.dart';
import 'agent_tools.dart';

class SubagentScenario with AgentScenarioCleanupMixin implements AgentScenario {
  final String task;
  final List<String> allowedTools;

  SubagentScenario({required this.task, required this.allowedTools});

  @override
  String get id => 'subagent';

  @override
  String get displayName => '子 Agent';

  @override
  List<Map<String, dynamic>> get tools => AgentTools.filterTools(allowedTools);

  @override
  String buildSystemPrompt(AgentScenarioContext context) {
    return '''你是一个专注的子 Agent。你的任务由父 Agent 明确指定，你只能使用被授权的工具列表。

## 你的任务
$task

## 纪律
1. 每次调用工具前，先用一行简洁说明你的思考。
2. 只能使用 allowed_tools 中的工具；越权调用会被拒绝。
3. 读-写分离：写入工具（如 update_outline、update_chapter_content）前必须先读取当前内容。
4. 完成或失败后必须停止，不要再派子 Agent（你也没有这个能力）。

## 结果格式
最终结果必须是结构化的 Markdown，包含：
- ## 任务目标
- ## 执行步骤
- ## 关键发现
- ## 最终结论
''';
  }

  @override
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  }) async {
    // 双重保险：dispatch_subagent 永远不在子 Agent 可调工具里
    if (name == 'dispatch_subagent') {
      return jsonEncode({
        'error': 'forbidden_tool',
        'message': '子 Agent 不能调用 dispatch_subagent。',
      });
    }
    // 白名单校验
    if (!allowedTools.contains(name)) {
      return jsonEncode({
        'error': 'forbidden_tool',
        'message': '工具 $name 不在你被授权的工具列表中。'
            '你只能使用：${allowedTools.join(", ")}',
      });
    }
    // 实际工具执行委托：子 Agent 场景不自己执行具体工具，
    // 由 SubagentRunner（任务 6）注入 delegate。
    // delegate 未注入时返回错误（测试覆盖的就是白名单拒绝路径，不触发到这里）。
    final delegate = _toolDelegate;
    if (delegate == null) {
      return jsonEncode({
        'error': 'not_configured',
        'message': '子 Agent 工具执行未配置。',
      });
    }
    return delegate(name, args, onProgress);
  }

  /// 由 SubagentRunner 注入的实际工具执行委托。
  /// 签名与 `AgentScenario.executeTool` 一致（返回 `Future<String>`）。
  Future<String> Function(String, Map<String, dynamic>, void Function(int)?)?
      _toolDelegate;

  void setToolDelegate(
      Future<String> Function(String, Map<String, dynamic>, void Function(int)?)
          delegate) {
    _toolDelegate = delegate;
  }

  @override
  Future<List<String>> getMemories() async => const [];

  @override
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async => null;

  @override
  Future<MemoryPatchResult> patchMemory(
    int? index,
    String newText,
  ) async {
    return MemoryPatchResult.error(
      '子 Agent 场景不支持持久化记忆',
      const [],
    );
  }
}

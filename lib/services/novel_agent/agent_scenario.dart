/// Agent 场景抽象 + 场景上下文
///
/// 将 Agent 的 system prompt、工具定义、工具执行、破坏性标记
/// 抽象为可插拔的场景接口，不同 UI 页面可使用不同场景。
library;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/providers/reading_context_providers.dart';
import '../../repositories/agent_memory_repository.dart';
import '../dsl_engine/llm_provider.dart' show ChatMessage;

// 导出 ChatMessage：AgentScenario 接口方法签名依赖它，
// 所有场景实现（implements AgentScenario）需可见。
export '../dsl_engine/llm_provider.dart' show ChatMessage;

/// Agent 场景上下文（动态参数，由调用方提供）
class AgentScenarioContext {
  /// 当前对话场景 ID（如 `ScenarioIds.writing`）。
  ///
  /// 工具内部调 LLM 时据此选择对应场景的供应商配置；为 null 时回退到 writing。
  final String? scenarioId;

  /// 小说/章节阅读上下文
  final ReadingContext? readingContext;

  /// WebView 控制器（webview_extract 场景必需，Headless 模式可为 null）
  final InAppWebViewController? webviewController;

  /// 当前页面 URL（webview_extract 场景使用）
  final String? currentUrl;

  /// 是否使用 Headless WebView 模式（webview_extract 场景专用）
  ///
  /// 设为 true 时，`AgentScenarioFactory` 从 `HeadlessWebViewPool` 获取后台
  /// WebView controller，使 AI 提取进程不依赖可见 WebView 页面生命周期。
  final bool useHeadlessWebView;

  /// 当前小说的数据库主键 ID（写作场景专用）
  ///
  /// AI 通过 `select_novel` 工具设置；该值确定所有隐式工具操作的目标小说。
  /// 为 null 时调用需要小说的工具会返回 `no_current_novel` 错误，
  /// 提示 AI 先调用 `list_novels` + `select_novel`。
  final int? currentNovelId;

  /// 当前小说的标题（写作场景专用，用于 system prompt 与 UI 展示）
  final String? currentNovelTitle;

  const AgentScenarioContext({
    this.scenarioId,
    this.readingContext,
    this.webviewController,
    this.currentUrl,
    this.useHeadlessWebView = false,
    this.currentNovelId,
    this.currentNovelTitle,
  });
}

/// Agent 场景抽象
///
/// 每个场景定义自己的 system prompt、工具集、执行逻辑和破坏性工具标记。
/// [AgentLoop] 只依赖此接口，不关心具体场景。
abstract class AgentScenario {
  /// 场景唯一标识（'writing' | 'webview_extract' | ...）
  String get id;

  /// 场景显示名（用于 UI 展示）
  String get displayName;

  /// 工具定义列表（OpenAI Function Calling schema）
  List<Map<String, dynamic>> get tools;

  /// 构建系统提示词
  String buildSystemPrompt(AgentScenarioContext context);

  /// 执行工具调用
  ///
  /// [onProgress] 可选进度回调，供内部走 LLM 流式的工具（如 create_chapter /
  /// update_chapter_content）上报已生成字符数。不传或工具无流式生成时忽略。
  ///
  /// [toolCallId] LLM tool_calls[i].id（任务 7 引入），用于：
  /// - WritingScenario.executeTool 透传给 SubagentRunner.dispatch(parentToolCallId:)
  /// - 未来场景内按 toolCallId 做幂等 / 关联查询
  /// 不使用此参数的场景实现忽略即可（默认 null）。
  Future<String> executeTool(
    String name,
    Map<String, dynamic> args, {
    void Function(int generatedChars)? onProgress,
    String? toolCallId,
  });

  /// 当本轮 LLM 响应无 tool_calls（即将结束循环）时的注入钩子
  ///
  /// 场景可返回一条提示消息（将作为 user 角色追加到 messages 并继续下一轮），
  /// 用于在 Agent 漏掉关键步骤时（例如已生成脚本却忘记 save_script）"轻推"一次。
  /// 返回 null 则正常结束循环。
  ///
  /// 防重复注入由场景内部负责（例如设置 `_injected` 标志，最多注入一次）。
  ///
  /// [messages] 当前完整对话历史（已包含本轮 assistant 消息）
  Future<String?> onNoToolCalls(List<ChatMessage> messages) async {
    return null;
  }

  /// 获取当前场景的所有经验记忆
  ///
  /// 默认实现从 AgentMemoryRepository 读取，子类可覆盖。
  /// 返回的列表会拼接到 system prompt 末尾。
  Future<List<String>> getMemories() async => const [];

  /// 场景结束时的资源清理钩子。
  ///
  /// 由 [NovelAgentService] 在 Agent 循环结束后（finally 中）调用。
  /// 默认实现见 [AgentScenarioCleanupMixin]；webview_extract 场景在 Headless
  /// 模式下由 [AgentScenarioFactory] 通过 [setCleanupTask] 注入释放
  /// HeadlessWebViewPool 使用权的逻辑。
  Future<void> cleanup();

  /// 设置清理钩子（供 [AgentScenarioFactory] 注入 pool.release 等）。
  void setCleanupTask(Future<void> Function()? task);

  /// patch 记忆（增/改/删），由 patch_memory 工具调用
  ///
  /// 用编号定位（1-based，来自 system prompt「## 经验记忆」段的 [N] 标记），
  /// 不依赖全文匹配，避免 LLM 难以逐字复现记忆原文。
  ///
  /// 行为：
  /// - index 为空/≤0 + newText 非空 → 新增（内容已存在则跳过，幂等返回成功）
  /// - index 给定 + newText 为空 → 删除第 index 条
  /// - index 给定 + newText 非空 → 替换第 index 条（与其它记忆重复则拒绝）
  /// - index 越界 → 返回错误 + 当前所有记忆的编号列表（供 AI 修正）
  ///
  /// 默认实现不可用，子类应通过 [AgentMemoryPatchMixin] 获得统一实现。
  Future<MemoryPatchResult> patchMemory(
    int? index,
    String newText,
  ) async {
    return MemoryPatchResult.error(
      'patch_memory 在当前场景不可用',
      const [],
    );
  }
}

/// Agent 场景清理钩子的默认实现 mixin。
///
/// 场景类通过 `with AgentScenarioCleanupMixin implements AgentScenario`
/// 即可获得 [cleanup] / [setCleanupTask] 的默认实现，无需各自重复字段逻辑。
mixin AgentScenarioCleanupMixin implements AgentScenario {
  Future<void> Function()? _cleanupTask;

  @override
  void setCleanupTask(Future<void> Function()? task) {
    _cleanupTask = task;
  }

  @override
  Future<void> cleanup() async {
    final task = _cleanupTask;
    _cleanupTask = null;
    if (task != null) {
      await task();
    }
  }
}

/// patch_memory 的统一实现 mixin
///
/// 提供 `_cachedMemories` 缓存与编号定位的 patch 逻辑，供所有 AgentScenario 复用，
/// 消除各场景的重复实现。子类通过 `with AgentMemoryPatchMixin`（配合
/// `implements AgentScenario`）获得能力，只需在 `getMemories`/`patchMemory`
/// 中注入 [AgentMemoryRepository] 调用 [loadMemories]/[patchMemoryImpl] 即可。
///
/// 编号稳定性：`getAllByScenario` 与 `getAllWithId` 均按 `created_at ASC` 排序，
/// system prompt 的 `[N]` 编号 = patchMemoryImpl 内 `all` 列表顺序，天然对齐。
mixin AgentMemoryPatchMixin on AgentScenario {
  /// 记忆缓存：getMemories 预填，patchMemory 成功后重建，buildSystemPrompt 复用。
  List<String> _cachedMemories = const [];

  /// 当前缓存（供 buildSystemPrompt 直接读取，零 IO）
  List<String> get cachedMemories => _cachedMemories;

  /// 从 DB 加载当前场景全部记忆并写入缓存
  Future<List<String>> loadMemories(AgentMemoryRepository repo) async {
    _cachedMemories = await repo.getAllByScenario(id);
    return _cachedMemories;
  }

  /// 编号定位 + 去重的 patch 实现
  ///
  /// [repo] 由子类注入；[index] 为 1-based 编号，null/≤0 视为新增；
  /// [newText] 为空时表示删除（此时 index 必填）。
  Future<MemoryPatchResult> patchMemoryImpl(
    AgentMemoryRepository repo,
    int? index,
    String newText,
  ) async {
    final all = await repo.getAllWithId(id);
    final allContents = all.map((r) => r['content'] as String).toList();

    // —— 新增（index 省略/≤0）——
    final isNew = index == null || index <= 0;
    if (isNew) {
      if (newText.isEmpty) {
        return MemoryPatchResult.error(
          '新增记忆时 newText 不能为空',
          allContents,
        );
      }
      // 去重：内容已存在则幂等跳过（不算错误，避免 AI 误判重试）
      if (allContents.contains(newText)) {
        return MemoryPatchResult.ok('记忆已存在，跳过新增');
      }
      await repo.addMemory(id, newText);
      await loadMemories(repo); // 重建缓存，保证编号正确
      return MemoryPatchResult.ok('新记忆已添加（编号 ${_cachedMemories.length}）');
    }

    // —— index 定位校验 ——
    final idx = index - 1; // 转 0-based
    if (idx < 0 || idx >= all.length) {
      return MemoryPatchResult.error(
        '编号 $index 超出范围（当前共 ${all.length} 条记忆，有效范围 1~${all.length}）',
        allContents,
      );
    }
    final row = all[idx];
    final rowId = row['id'] as int;

    // —— 删除（newText 为空）——
    if (newText.isEmpty) {
      await repo.deleteMemory(rowId);
      await loadMemories(repo);
      return MemoryPatchResult.ok('第 $index 条记忆已删除');
    }

    // —— 替换 ——
    // 去重：若 newText 与其它已有记忆（非自身）相同，拒绝以避免重复
    final conflict = allContents
        .asMap()
        .entries
        .any((e) => e.key != idx && e.value == newText);
    if (conflict) {
      return MemoryPatchResult.error(
        '新内容与其它已有记忆重复',
        allContents,
      );
    }
    await repo.updateMemory(rowId, newText);
    await loadMemories(repo);
    return MemoryPatchResult.ok('第 $index 条记忆已更新');
  }
}

/// patch_memory 工具的执行结果
class MemoryPatchResult {
  final bool success;
  final String message;
  final List<String> allMemories; // 报错时返回所有记忆，供 AI 修正

  const MemoryPatchResult._({
    required this.success,
    required this.message,
    required this.allMemories,
  });

  factory MemoryPatchResult.ok(String message) =>
      MemoryPatchResult._(success: true, message: message, allMemories: const []);

  factory MemoryPatchResult.error(String message, List<String> allMemories) =>
      MemoryPatchResult._(success: false, message: message, allMemories: allMemories);
}

/// patch_memory 工具定义（OpenAI Function Calling schema）
///
/// 说明：这是 Agent 进化的核心机制。
/// - 遇到坑、用户帮你解决的、研究好几轮才解决的记忆，用 patch_memory 记录下来
/// - 遇到和记忆不符的，先 patch_memory 修改记忆
/// - patch_memory(index=N, newText="...")：用编号定位（不依赖全文匹配）
///   - index 省略/0 + newText 非空 → 新增（内容已存在则跳过）
///   - index 给定 + newText 为空 → 删除第 index 条
///   - index 给定 + newText 非空 → 替换第 index 条
///   - index 越界 → 报错并返回所有记忆的编号列表
const Map<String, dynamic> patchMemoryToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'patch_memory',
    'description':
        '修改/添加/删除当前场景的经验记忆。\n'
        '记忆会持久化到本地数据库，并在下次对话的 system prompt 中以编号列表出现。\n'
        '记忆列表见 system prompt 末尾的「## 经验记忆」段，每条形如 `[1] 内容`。\n'
        '使用场景：\n'
        '- 遇到坑、用户帮你解决、或者研究了好几轮才解决的记忆 → 记录下来\n'
        '- 遇到和当前记忆不符的情况 → 修改记忆\n'
        '- 旧的记忆不再适用 → 删除\n'
        '⚠️ 记忆范围约束：\n'
        '- 仅记录**通用知识**（任何网站/小说都适用的经验、规律、坑点）\n'
        '- ❌ 不要记录：特定网站的选择器、URL、域名（如 `.listmain a`、`biquge.com`）\n'
        '- ❌ 不要记录：特定小说的情节、人物、设定、世界观\n'
        '- ✅ 推荐记录：通用 JS 提取技巧、反爬策略、跨场景原理、用户偏好、工具调用规范\n'
        '- 专属信息应存到对应数据库表（如 site_scripts / chapter_versions），而非记忆\n'
        '参数说明（操作模式由 index / newText 组合决定）：\n'
        '- index 省略或 0 + newText 非空 → 新增（若内容已存在则跳过）\n'
        '- index 给定 + newText 为空或省略 → 删除第 index 条记忆\n'
        '- index 给定 + newText 非空 → 替换第 index 条记忆\n'
        '- index 越界 → 报错并返回当前所有记忆的编号列表（[N] 格式，供修正）',
    'parameters': {
      'type': 'object',
      'properties': {
        'index': {
          'type': 'integer',
          'description':
              '要替换/删除的记忆编号（1-based，来自 system prompt「## 经验记忆」段的 [N] 标记）。'
              '省略或传 0 表示新增。',
        },
        'newText': {
          'type': 'string',
          'description':
              '新记忆内容。为空或省略表示删除（此时 index 必填）。',
        },
      },
      'required': <String>[],
    },
  },
};

/// 已注册的场景 ID 常量
abstract final class ScenarioIds {
  static const writing = 'writing';
  static const webviewExtract = 'webview_extract';
}

/// 场景快速输入提示词
///
/// 在对话输入区上方展示为一行 chip，点击后追加到输入框，
/// 让用户快速发起典型任务，避免重复打字。
class ScenarioQuickPrompt {
  /// chip 上显示的简短标签
  final String label;

  /// 追加到输入框的完整提示词
  final String text;

  const ScenarioQuickPrompt({
    required this.label,
    required this.text,
  });
}

/// 各场景的快速输入提示词集合
///
/// 与场景的工具集 / system prompt 工作流同源维护，
/// UI 通过 [forScenario] 按场景 ID 取数。未配置的场景返回空列表（不渲染 chip 行）。
abstract final class ScenarioQuickPrompts {
  static const _webviewExtract = <ScenarioQuickPrompt>[];

  /// 获取指定场景的快速输入提示词
  ///
  /// 未配置的场景返回空列表。
  static List<ScenarioQuickPrompt> forScenario(String scenarioId) {
    switch (scenarioId) {
      case ScenarioIds.webviewExtract:
        return _webviewExtract;
      default:
        return const <ScenarioQuickPrompt>[];
    }
  }
}

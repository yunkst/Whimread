/// ask_user 工具的挂起提问注册表
///
/// 阻塞式向用户提问的核心机制：WritingScenario 的 ask_user 分支
/// [AskUserRegistry.register] 一个带 `Completer` 的挂起项并 await 它，
/// AgentLoop 因此在工具执行点暂停；聊天 UI 渲染问题卡片，用户点选/输入后
/// 经 ScenarioSession.answerAskUser 调 [AskUserRegistry.answer] 完成该
/// Completer，答案以 JSON 形式作为 tool result 回灌 LLM。
///
/// 生命周期兜底（防止协程永久挂起）：
/// - 用户取消 / 会话销毁 → NovelAgentService.cancelFor 取消 run 的
///   CancellationToken，executor 注册的回调把挂起项 complete 为 cancelled；
/// - 兜底 abort 用 [AskUserRegistry.abortForScenario]；
/// - executor 侧另有超时（见 WritingScenario），超时后按 timeout 语义放行。
library;

import 'dart:async';

import 'package:novel_app/services/logger_service.dart';

/// 用户对一次 ask_user 提问的应答
class AskUserAnswer {
  /// 应答状态
  final AskUserAnswerStatus status;

  /// 多选/单选选中的候选文本（用户未点选候选时为空列表）
  final List<String> selected;

  /// 用户自由输入的文本（未输入为 null）
  final String? freeText;

  const AskUserAnswer({
    required this.status,
    this.selected = const [],
    this.freeText,
  });

  const AskUserAnswer.cancelled()
      : this(status: AskUserAnswerStatus.cancelled);

  const AskUserAnswer.timeout() : this(status: AskUserAnswerStatus.timeout);

  bool get isAnswered => status == AskUserAnswerStatus.answered;
}

enum AskUserAnswerStatus { answered, cancelled, timeout }

/// 归一化 ask_user 的单个 option 项 → (label, description) 记录
///
/// LLM 实测（MiniMax-M3 等）常无视 schema 的 `items: string` 声明，把选项
/// 传成 `{title: ..., description: ...}` 对象——这是合理诉求（候选短语 +
/// 补充说明），故正式兼容两种形式：
/// - 字符串 → 纯短语，无说明
/// - 对象 → 按 label/title/name/text/value 取短语，按
///   description/hint/detail/desc/subtitle 取说明；无可识别字段时把
///   键值对拍平成一句话，保证内容不丢
({String label, String? description}) normalizeAskUserOption(Object item) {
  if (item is String) {
    final trimmed = item.trim();
    return (label: trimmed, description: null);
  }
  if (item is Map) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final v = item[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final label = pick(const ['label', 'title', 'name', 'text', 'value']);
    final description =
        pick(const ['description', 'hint', 'detail', 'desc', 'subtitle']);
    if (label != null) return (label: label, description: description);
    final flattened = item.entries
        .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
        .map((e) => '${e.key}: ${e.value.toString().trim()}')
        .join('，');
    return (label: flattened, description: null);
  }
  return (label: item.toString().trim(), description: null);
}

/// 一次挂起的提问（executor 持有 await 其 [future]）
class PendingAskUser {
  final String scenarioId;
  final String toolCallId;
  final String question;
  final List<String> options;
  final bool multiSelect;
  final bool allowFreeText;

  final Completer<AskUserAnswer> _completer = Completer<AskUserAnswer>();

  PendingAskUser({
    required this.scenarioId,
    required this.toolCallId,
    required this.question,
    required this.options,
    required this.multiSelect,
    required this.allowFreeText,
  });

  Future<AskUserAnswer> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  /// 完成挂起项；已完成（重复作答 / 已被取消）返回 false
  bool complete(AskUserAnswer answer) {
    if (_completer.isCompleted) return false;
    _completer.complete(answer);
    return true;
  }
}

/// 挂起提问的注册表（应用级单例，经 askUserRegistryProvider 提供）
///
/// 同一场景的多个并发 ask_user（LLM 单轮可发多个调用）按 toolCallId 键控；
/// 场景级批量终止（如会话 dispose 兜底）按 scenarioId 过滤。
class AskUserRegistry {
  /// 键：'$scenarioId::$toolCallId'
  final Map<String, PendingAskUser> _pending = {};

  static String _key(String scenarioId, String toolCallId) =>
      '$scenarioId::$toolCallId';

  /// 注册一次挂起提问。toolCallId 冲突（同场景同 id 残留）时先移除旧项。
  PendingAskUser register({
    required String scenarioId,
    required String toolCallId,
    required String question,
    required List<String> options,
    required bool multiSelect,
    required bool allowFreeText,
  }) {
    final key = _key(scenarioId, toolCallId);
    final entry = PendingAskUser(
      scenarioId: scenarioId,
      toolCallId: toolCallId,
      question: question,
      options: List.unmodifiable(options),
      multiSelect: multiSelect,
      allowFreeText: allowFreeText,
    );
    final old = _pending[key];
    if (old != null && !old.isCompleted) {
      LoggerService.instance.w(
        'AskUserRegistry 覆盖未完成的挂起提问 (scenario=$scenarioId, '
        'toolCallId=$toolCallId)',
        category: LogCategory.ai,
        tags: ['agent', 'ask_user', 'register', 'overwrite', scenarioId],
      );
      old.complete(const AskUserAnswer.cancelled());
    }
    _pending[key] = entry;
    return entry;
  }

  /// 用户作答入口（UI 经 ScenarioSession.answerAskUser 调用）。
  /// 无匹配挂起项（已答/已取消/会话重建）返回 false。
  bool answer({
    required String scenarioId,
    required String toolCallId,
    List<String>? selected,
    String? freeText,
  }) {
    final entry = _pending[_key(scenarioId, toolCallId)];
    if (entry == null) return false;
    final ok = entry.complete(AskUserAnswer(
      status: AskUserAnswerStatus.answered,
      selected: List.unmodifiable(selected ?? const []),
      freeText: (freeText != null && freeText.trim().isNotEmpty)
          ? freeText.trim()
          : null,
    ));
    if (ok) _pending.remove(_key(scenarioId, toolCallId));
    return ok;
  }

  /// 将某场景的全部挂起提问按 [status] 放行（取消/销毁兜底），
  /// 返回放行数量。
  int abortForScenario(
    String scenarioId, {
    AskUserAnswerStatus status = AskUserAnswerStatus.cancelled,
  }) {
    final answer = status == AskUserAnswerStatus.timeout
        ? const AskUserAnswer.timeout()
        : const AskUserAnswer.cancelled();
    final keys = _pending.keys
        .where((k) => _pending[k]!.scenarioId == scenarioId)
        .toList();
    var count = 0;
    for (final key in keys) {
      if (_pending[key]!.complete(answer)) count++;
      _pending.remove(key);
    }
    return count;
  }

  /// 移除某个挂起项（executor finally 清理用）
  void remove(String scenarioId, String toolCallId) {
    _pending.remove(_key(scenarioId, toolCallId));
  }

  /// 当前挂起数量（测试/诊断用）
  int get pendingCount => _pending.length;
}

/// ask_user 工具的问答卡片
///
/// 当 [AgentMessageBubble] 渲染 [ToolCallSegment] 且 `call.name == 'ask_user'`
/// 时，用本卡片替代普通 [AgentToolCallCard]：
/// - 待答态（running 且本轮仍在进行）：单选点击即答；多选勾选后确认；
///   allow_free_text 时可自由输入——作答经 [onAnswer] 投回
///   ScenarioSession.answerAskUser，完成挂起的 Completer。
/// - 已答态（completed）：解析 result JSON 渲染问题与答案，供历史回看。
/// - 失效态（running 但本轮已结束——取消后 partial 落库 / 会话重建）：
///   显示"未回答"，不可交互。
///
/// 数据来源沿用 present_choices 的"参数即问题"模式：问题与候选项读自
/// `call.arguments`（ToolCallStartEvent 时的完整参数），答案读自
/// `call.result`，两者都随 segments 通用 JSON 持久化自动落库/还原。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/novel_agent/agent_event.dart';

/// ask_user 参数（call.arguments 解析结果）
class AskUserArgs {
  final String question;
  final List<String> options;
  final bool multiSelect;
  final bool allowFreeText;

  const AskUserArgs({
    required this.question,
    required this.options,
    required this.multiSelect,
    required this.allowFreeText,
  });

  static AskUserArgs parse(Map<String, dynamic> arguments) {
    final rawOptions = arguments['options'];
    final options = rawOptions is List
        ? rawOptions.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
        : const <String>[];
    return AskUserArgs(
      question: (arguments['question'] as String?)?.trim() ?? '',
      options: options,
      multiSelect: arguments['multi_select'] == true,
      // 与 executor 侧默认一致：未传即允许自由输入
      allowFreeText: arguments['allow_free_text'] != false,
    );
  }
}

/// ask_user 结果（call.result 解析结果）
class AskUserResult {
  final List<String> selected;
  final String? freeText;

  /// cancelled / timeout（未获作答的收尾态）；正常作答为 null
  final String? status;

  /// JSON 解析失败时为原始串，UI 降级展示
  final String? raw;

  const AskUserResult({
    required this.selected,
    this.freeText,
    this.status,
    this.raw,
  });

  static AskUserResult parse(String resultStr) {
    try {
      final json = jsonDecode(resultStr);
      if (json is! Map<String, dynamic>) {
        return AskUserResult(selected: const [], raw: resultStr);
      }
      final rawSelected = json['selected'];
      return AskUserResult(
        selected: rawSelected is List
            ? rawSelected.map((e) => e.toString()).toList()
            : const <String>[],
        freeText: (json['free_text'] as String?)?.trim(),
        status: json['status'] as String?,
      );
    } catch (_) {
      return AskUserResult(selected: const [], raw: resultStr);
    }
  }
}

class AskUserCard extends StatefulWidget {
  final AgentToolCall call;

  /// 本轮是否仍在进行（气泡处于流式尾部）。running 状态但为 false 时
  /// 说明 run 已结束而问题未答（取消落库 / 会话重建），渲染为失效态。
  final bool awaitingAnswer;

  /// 作答回调：(选中的候选, 自由输入文本)，二者至少一个非空。
  /// 由 bubble 注入，转投 ScenarioSession.answerAskUser。
  final void Function(List<String>? selected, String? freeText) onAnswer;

  const AskUserCard({
    super.key,
    required this.call,
    required this.awaitingAnswer,
    required this.onAnswer,
  });

  @override
  State<AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<AskUserCard> {
  final Set<String> _picked = {};
  final TextEditingController _freeTextController = TextEditingController();
  final FocusNode _freeTextFocus = FocusNode();

  /// 本地已作答标记：点击后立即置位禁用控件，兜住 ToolCallEndEvent
  /// 回流前的窗口（重复作答会被注册表拒绝，这里主要保 UX）。
  bool _submitted = false;

  @override
  void dispose() {
    _freeTextController.dispose();
    _freeTextFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = AskUserArgs.parse(widget.call.arguments);

    // completed 且结果是收尾态（cancelled/timeout）时，标题按实际结果区分，
    // 避免把"用户没答"错标成"已回答"
    AskUserResult? completedResult;
    if (widget.call.status == AgentToolStatus.completed &&
        widget.call.result != null) {
      completedResult = AskUserResult.parse(widget.call.result!);
    }
    final closedStatus = completedResult?.status;

    final (headerIcon, headerColor, headerText) = switch (widget.call.status) {
      AgentToolStatus.running => widget.awaitingAnswer
          ? (Icons.help_outline, theme.colorScheme.primary, '等待你的回答')
          : (Icons.help_outline, theme.colorScheme.outline, '未回答（本轮已中断）'),
      AgentToolStatus.completed => switch (closedStatus) {
          'cancelled' => (
              Icons.cancel,
              theme.colorScheme.outline,
              '已取消',
            ),
          'timeout' => (
              Icons.schedule,
              theme.colorScheme.outline,
              '已超时',
            ),
          _ => (
              Icons.check_circle,
              theme.colorScheme.tertiary,
              '已回答',
            ),
        },
      AgentToolStatus.error => (
          Icons.error,
          theme.colorScheme.error,
          '提问失败',
        ),
      AgentToolStatus.rejected => (
          Icons.cancel,
          theme.colorScheme.outline,
          '已取消',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: headerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：状态 + 标识
          Row(
            children: [
              Icon(headerIcon, size: 14, color: headerColor),
              const SizedBox(width: 6),
              Text(
                '问用户 · $headerText',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: headerColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (args.question.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              args.question,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ..._buildBody(context, args),
        ],
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, AskUserArgs args) {
    switch (widget.call.status) {
      case AgentToolStatus.running:
        return _submitted
            ? _buildSubmittedPending(context)
            : widget.awaitingAnswer
                ? _buildAnswerInputs(context, args)
                : _buildStaleNote(context);
      case AgentToolStatus.completed:
        return _buildAnsweredSummary(context, args);
      case AgentToolStatus.error:
      case AgentToolStatus.rejected:
        return _buildClosedNote(context);
    }
  }

  // ===== 待答态 =====

  List<Widget> _buildAnswerInputs(BuildContext context, AskUserArgs args) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    if (args.options.isNotEmpty) {
      widgets.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in args.options)
            args.multiSelect
                ? FilterChip(
                    label: Text(option),
                    selected: _picked.contains(option),
                    onSelected: (selected) => setState(() {
                      selected ? _picked.add(option) : _picked.remove(option);
                    }),
                  )
                : ChoiceChip(
                    label: Text(option),
                    selected: false,
                    onSelected: (_) => _answer(
                      selected: [option],
                      freeText: null,
                    ),
                  ),
        ],
      ));
    }

    final hasFreeText = args.allowFreeText || args.options.isEmpty;
    if (hasFreeText) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(TextField(
        controller: _freeTextController,
        focusNode: _freeTextFocus,
        style: theme.textTheme.bodyMedium,
        minLines: 1,
        maxLines: 4,
        textInputAction: args.multiSelect ? TextInputAction.newline : TextInputAction.send,
        onSubmitted: args.multiSelect
            ? null
            : (_) => _answerFromFreeText(args),
        decoration: InputDecoration(
          isDense: true,
          hintText: args.options.isEmpty
              ? '输入你的回答…'
              : args.multiSelect
                  ? '也可自行输入补充内容'
                  : '或输入自定义内容…',
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          suffixIcon: args.multiSelect ? null : _buildSendButton(args),
        ),
      ));
    }

    if (args.multiSelect) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(Align(
        alignment: Alignment.centerRight,
        child: _buildConfirmButton(args),
      ));
    }
    return widgets;
  }

  Widget _buildSendButton(AskUserArgs args) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.send, size: 18),
      tooltip: '提交回答',
      onPressed: () => _answerFromFreeText(args),
    );
  }

  Widget _buildConfirmButton(AskUserArgs args) {
    final freeText = _freeTextController.text.trim();
    final enabled = _picked.isNotEmpty || freeText.isNotEmpty;
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: enabled
          ? () => _answer(
                selected: _picked.toList(),
                freeText: freeText.isEmpty ? null : freeText,
              )
          : null,
      child: Text(
        _picked.isEmpty ? '确认（未选择）' : '确认（已选 ${_picked.length} 项）',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  void _answerFromFreeText(AskUserArgs args) {
    final text = _freeTextController.text.trim();
    if (text.isEmpty) return;
    _answer(
      selected: null,
      freeText: text,
    );
  }

  void _answer({List<String>? selected, String? freeText}) {
    if (_submitted) return;
    setState(() => _submitted = true);
    _freeTextFocus.unfocus();
    widget.onAnswer(selected, freeText);
  }

  List<Widget> _buildSubmittedPending(BuildContext context) {
    return [
      Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text(
            '已回答，等待继续…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ];
  }

  // ===== 失效 / 收尾态 =====

  List<Widget> _buildStaleNote(BuildContext context) {
    return [
      Text(
        '本轮已被中断，该问题未回答。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    ];
  }

  List<Widget> _buildClosedNote(BuildContext context) {
    final result = widget.call.result == null
        ? null
        : AskUserResult.parse(widget.call.result!);
    final text = switch (result?.status) {
      'cancelled' => '本轮已被取消，问题未回答。',
      'timeout' => '超时未回答，Agent 已自行继续。',
      _ => '工具执行出错，问题未送达。',
    };
    return [
      Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    ];
  }

  // ===== 已答态 =====

  List<Widget> _buildAnsweredSummary(BuildContext context, AskUserArgs args) {
    final theme = Theme.of(context);
    if (widget.call.result == null) {
      return _buildClosedNote(context);
    }
    final result = AskUserResult.parse(widget.call.result!);

    // 非作答收尾（cancelled / timeout）走结果态文案
    if (result.status != null) {
      return result.status == 'timeout'
          ? [
              Text('超时未回答，Agent 已自行继续。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ))
            ]
          : _buildClosedNote(context);
    }

    if (result.raw != null) {
      return [
        Text(
          result.raw!,
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ];
    }

    final widgets = <Widget>[];
    final selected = result.selected;
    if (selected.isNotEmpty) {
      widgets.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in selected)
            Chip(
              label: Text(option),
              avatar: Icon(
                args.multiSelect ? Icons.check_box : Icons.check_circle,
                size: 16,
                color: theme.colorScheme.tertiary,
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ));
    }
    if (result.freeText != null) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 6));
      widgets.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          result.freeText!,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
      ));
    }
    if (widgets.isEmpty) {
      widgets.add(Text(
        '（用户未作答）',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ));
    }
    return widgets;
  }
}

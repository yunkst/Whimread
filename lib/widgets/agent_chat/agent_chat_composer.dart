import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/novel_agent/agent_scenario.dart';
import '../../widgets/media/media_view.dart';
import 'agent_icons.dart';

class AgentChatComposer extends ConsumerStatefulWidget {
  final void Function(String text, String? mediaId)? onSend;
  final VoidCallback? onAttachMedia;
  final String? attachedMediaId;
  final void Function(String? mediaId)? onClearAttachment;

  /// 外部可选注入：dialog 共享 controller/focusNode，用于 rollback 回填与
  /// Composer/Messages 状态一致。null 时退回自管理（Task 7 行为，向后兼容）。
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// 外部可选注入：当前是否在选图+上传中（dialog 锁定 + 按钮转圈）。
  final bool isPickingImage;

  const AgentChatComposer({
    super.key,
    this.onSend,
    this.onAttachMedia,
    this.attachedMediaId,
    this.onClearAttachment,
    this.controller,
    this.focusNode,
    this.isPickingImage = false,
  });

  @override
  ConsumerState<AgentChatComposer> createState() => _AgentChatComposerState();
}

class _AgentChatComposerState extends ConsumerState<AgentChatComposer> {
  // 内部自管理 fallback（向后兼容 Task 7：不传 controller 时自己持有）
  late final TextEditingController _internalController = TextEditingController();
  late final FocusNode _internalFocus = FocusNode();

  TextEditingController get _controller => widget.controller ?? _internalController;
  FocusNode get _focus => widget.focusNode ?? _internalFocus;

  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _onTextChanged(); // 初始同步
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) {
      _internalController.dispose();
      _internalFocus.dispose();
    }
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && widget.attachedMediaId == null) return;
    widget.onSend?.call(text, widget.attachedMediaId);
    // 单一所有者原则：Composer 自己清输入框与附件预览，
    // dialog 通过 onClearAttachment 回调更新自己的 _attachedMediaId state。
    _controller.clear();
    widget.onClearAttachment?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(currentChatStateProvider);
    final colors = context.appColors;
    final prompts = ScenarioQuickPrompts.forScenario(chatState.scenarioId);
    final isSupp = chatState.isLoading && chatState.supplementaryCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: colors.paper,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prompts.isNotEmpty && !chatState.isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in prompts)
                    ActionChip(
                      avatar: Icon(AgentIcons.wand, size: 14),
                      label: Text(p.label, style: const TextStyle(fontSize: 11)),
                      backgroundColor: colors.chatInputBackground,
                      side: BorderSide(color: colors.divider),
                      onPressed: () {
                        _controller.text = p.text;
                        _controller.selection = TextSelection(
                            baseOffset: p.text.length, extentOffset: p.text.length);
                        if (_focus.canRequestFocus) _focus.requestFocus();
                      },
                    ),
                ],
              ),
            ),
          if (widget.attachedMediaId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Stack(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80, maxHeight: 80),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: MediaView(
                          mediaId: widget.attachedMediaId!,
                          boxFit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0, right: 0,
                      child: GestureDetector(
                        onTap: () => widget.onClearAttachment?.call(null),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: colors.inkSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(AgentIcons.close, size: 16, color: colors.agentOnBrand),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.chatInputBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      maxLines: 5,
                      minLines: 1,
                      style: TextStyle(fontSize: 13, color: colors.ink),
                      decoration: InputDecoration(
                        hintText: '和写作助手说点什么…',
                        hintStyle: TextStyle(color: colors.chatHintText),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      textInputAction: TextInputAction.newline,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '添加图片',
                  icon: Icon(AgentIcons.plus, size: 19),
                  color: colors.inkSoft,
                  onPressed: widget.isPickingImage ? null : widget.onAttachMedia,
                ),
                const SizedBox(width: 2),
                _SendButton(
                  enabled: _hasText || widget.attachedMediaId != null,
                  isSupplementary: isSupp,
                  onPressed: _send,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool isSupplementary;
  final VoidCallback onPressed;
  const _SendButton(
      {required this.enabled, required this.isSupplementary, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bg = enabled
        ? (isSupplementary
            ? colors.chatButtonPrimary.withValues(alpha: 0.5)
            : colors.chatButtonPrimary)
        : colors.divider;
    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        boxShadow: enabled && !isSupplementary
            ? [
                BoxShadow(
                  color: colors.chatButtonPrimary.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: IconButton(
        tooltip: '发送',
        icon: Icon(AgentIcons.send, size: 17),
        color: colors.agentOnBrand,
        padding: EdgeInsets.zero,
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}

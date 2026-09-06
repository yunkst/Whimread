import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:novel_app/core/providers/agent_events_provider.dart';
import 'package:novel_app/core/providers/agent_scenario_provider.dart';
import 'package:novel_app/core/providers/scenario_sessions_provider.dart';
import 'package:novel_app/core/providers/scenario_session.dart';
import 'package:novel_app/models/agent_chat_message.dart';
import 'package:novel_app/services/dsl_engine/retry_signals.dart';
import 'package:novel_app/services/image_picker_service.dart';
import 'package:novel_app/services/media/media_proxy.dart';
import 'package:novel_app/services/media/media_types.dart';
import 'package:novel_app/services/novel_agent/agent_event.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_composer.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_header.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_messages.dart';
import 'package:novel_app/widgets/agent_chat/agent_scenario_config_dialog.dart';
import 'package:novel_app/widgets/agent_chat/agent_status_strip.dart';
import 'package:novel_app/widgets/agent_chat/chat_history_sheet.dart';

/// Agent 聊天对话框（shell）。
///
/// 组件化后职责 = Dialog 容器 + fullscreen + 组装：
///   - Header  (Task 5): 标题 + 上下文行 + 场景菜单 + 历史/关闭
///   - StatusStrip (Task 4): error/retry/supplement 状态条（含 retry 倒计时）
///   - Messages (Task 6): 消息流 + 气泡 + 空状态 + 滚动 + 跳转底部
///   - Composer (Task 7): 输入栏 + 附件预览 + 发送
///
/// 状态所有权：inputController / focusNode / attachedMediaId / isPickingImage
/// 由 dialog 持有，注入 Composer（Task 7 向后兼容：不传则自管理）。
/// Messages 的滚动 + 跳转底部完全自管（dialog 已不再持有 _scrollController）。
class AgentChatDialog extends ConsumerStatefulWidget {
  /// 预填草稿（draftOnly 模式下由启动器注入；autoSend 模式不传）
  final String? initialDraft;

  /// 选图服务注入入口（默认走真实实现，测试可注入 fake）。
  final ImagePickerService? imagePickerService;

  const AgentChatDialog({
    super.key,
    this.initialDraft,
    this.imagePickerService,
  });

  @override
  ConsumerState<AgentChatDialog> createState() => _AgentChatDialogState();
}

class _AgentChatDialogState extends ConsumerState<AgentChatDialog> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFullscreen = false;

  // 待发送的已上传图片 mediaId（单选单图，null 表示无）。
  String? _attachedMediaId;
  // 选图+上传进行中（控制 + 按钮转圈与禁用）。
  bool _isPickingImage = false;

  // ImagePickerService 钩子（默认走真实实现，测试可通过构造参数注入）。
  ImagePickerService get _imagePicker =>
      widget.imagePickerService ?? ImagePickerService();

  @override
  void initState() {
    super.initState();
    if (widget.initialDraft != null) {
      _inputController.text = widget.initialDraft!;
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.read(currentSessionProvider);

    // 监听 agent 全局事件流：CompactionEvent 弹一次性 SnackBar 提示。
    // ref.listen 只在事件从无到有 / 数据变化时触发；用 maybeOf 防御 dialog 关闭
    // 后 ScaffoldMessenger 不可达的场景。
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (prev, next) {
      next.whenData((event) {
        if (event is! CompactionEvent) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text('🗂 ${event.description}'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    });

    return Dialog(
      insetPadding: _isFullscreen
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_isFullscreen ? 0 : 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _isFullscreen
                ? double.infinity
                : MediaQuery.of(context).size.width * 0.92,
            maxHeight: _isFullscreen
                ? double.infinity
                : MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AgentChatHeader(
                onHistory: () => _showHistorySheet(),
                onNewSession: () => _startNewSession(),
                onConfig: () => _showScenarioConfigDialog(),
                onToggleFullscreen: () => setState(() => _isFullscreen = !_isFullscreen),
                isFullscreen: _isFullscreen,
                onClose: () => Navigator.of(context).maybePop(),
              ),
              // StatusStrip retry 订阅兜底（Task 4 修复：外层 ValueListenableBuilder
              // 监听 RetrySignals，触发时 rebuild 并传给 AgentStatusStrip 读最新值）。
              ValueListenableBuilder<RetryState?>(
                valueListenable: RetrySignals.instance.notifier,
                builder: (context, _, child) =>
                    AgentStatusStrip(onStop: _stopGeneration),
              ),
              Expanded(
                child: AgentChatMessages(onRollback: _handleRollback),
              ),
              AgentChatComposer(
                controller: _inputController,
                focusNode: _focusNode,
                attachedMediaId: _attachedMediaId,
                isPickingImage: _isPickingImage,
                onSend: (text, mediaId) => _sendMessage(session, text, mediaId),
                onAttachMedia: _onAttachTap,
                onClearAttachment: (_) => setState(() => _attachedMediaId = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 停止当前 agent 生成 — 委托给当前场景的 [ScenarioSession.cancel]
  /// （含子 Agent 级联取消 + 当前轮 partial 落库 + token cancel）。
  void _stopGeneration() {
    ref.read(currentSessionProvider)?.cancel();
  }

  /// 弹出会话历史底部抽屉（当前 scenario 下的会话列表）
  Future<void> _showHistorySheet() async {
    final scenarioId = ref.read(currentAgentScenarioProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ChatHistorySheet(scenarioId: scenarioId),
    );
  }

  /// 新建一条空白会话并切换过去（旧会话保留在历史列表）。
  ///
  /// 与「会话历史 → 新建会话」共用 ScenarioSessionsNotifier.startNewSession，
  /// 运行中新建会话时由 adoptSession 内部 cancel 老 agent 兜底，避免流式 segment
  /// 污染新 session。
  Future<void> _startNewSession() async {
    final scenarioId = ref.read(currentAgentScenarioProvider);
    await ref.read(scenarioSessionsProvider.notifier).startNewSession(scenarioId);
  }

  /// 弹出场景级 LLM 配置对话框
  ///
  /// 让用户为当前场景单独配置 LLM 后端（覆盖全局默认）。
  /// 配置写入 SharedPreferences，下次 sendMessage 自动生效。
  Future<void> _showScenarioConfigDialog() async {
    final chatState = ref.read(currentChatStateProvider);
    await showDialog<bool>(
      context: context,
      builder: (_) => AgentScenarioConfigDialog(
        scenarioId: chatState.scenarioId,
      ),
    );
  }

  /// 点击 + 触发选图 -> 上传 -> 预览。
  /// 单选单图：已有附件时拒绝；上传中禁用按钮；失败弹 SnackBar。
  Future<void> _onAttachTap() async {
    if (!mounted) return;
    // 单选单图：已有附件时拒绝
    if (_attachedMediaId != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('一次只支持一张图片，发送或删除后再选')),
        );
      }
      return;
    }
    setState(() => _isPickingImage = true);
    try {
      final Uint8List? bytes = await _imagePicker.pickAndCrop();
      if (bytes == null) return; // 用户取消
      // 注册为 local_ mediaId（复用 MediaProxy.upload）
      final mediaId =
          await ref.read(mediaProxyProvider).upload(bytes, MediaKind.image);
      if (!mounted) return;
      setState(() => _attachedMediaId = mediaId);
    } on ImageTooLargeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _sendMessage(
      ScenarioSession? session, String text, String? mediaId) async {
    if (text.isEmpty && mediaId == null) return;
    final imageIds = mediaId != null ? [mediaId] : const <String>[];
    await session?.sendMessage(content: text, imageMediaIds: imageIds);
    if (mounted && _focusNode.canRequestFocus) _focusNode.requestFocus();
  }

  /// 回滚到指定 user 消息 — 弹确认框,通过后删除该消息及之后所有记录,
  /// 并把该消息文本回填到输入框(等待用户编辑后重新发送)。
  ///
  /// 签名变化：(int messageIndex) -> (AgentChatMessage message)，
  /// 由 Messages 传 message 对象（不再依赖 snapshot 索引，避免消息流变化导致越界）。
  Future<void> _handleRollback(AgentChatMessage message) async {
    final chatState = ref.read(currentChatStateProvider);
    final messages = chatState.messages;
    final messageIndex = messages.indexOf(message);
    if (messageIndex < 0) return;
    if (message.role != AgentChatRole.user) return;

    final willRemove = messages.length - messageIndex;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('回滚对话'),
        content: Text(
          '将删除此消息之后的 $willRemove 条记录(含此消息),\n'
          '并把此消息内容放回输入框,是否继续?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认回滚'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final session = ref.read(currentSessionProvider);
    await session?.rollbackToMessage(
      messageIndex,
      contentCallback: (text) {
        if (!mounted) return;
        _inputController.text = text;
        _inputController.selection = TextSelection.collapsed(
          offset: text.length,
        );
        // Composer 监听同一 controller,自动更新 _hasText / 发送按钮状态
        if (_focusNode.canRequestFocus) _focusNode.requestFocus();
      },
    );
  }
}

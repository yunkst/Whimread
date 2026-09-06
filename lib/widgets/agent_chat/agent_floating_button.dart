import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/widgets/agent_chat/agent_chat_launcher_entry.dart';
import '../../core/theme/app_colors.dart';

/// Agent 全局悬浮按钮
///
/// 使用 Stack + Positioned 实现可拖动悬浮按钮，
/// 点击展开聊天对话框。
class AgentFloatingButton extends ConsumerStatefulWidget {
  /// 打开对话时强制使用的场景 ID。
  ///
  /// 挂载在固定场景页面（阅读页/章节列表 = writing）时显式传入，
  /// 不依赖全局 provider 的残留值（如浏览器 Tab 留下的 webview_extract）。
  /// null（默认）= 不干预，沿用全局当前值——供跨 Tab 共享的 Shell
  /// （main.dart 包含书架/浏览器/设置）使用，其场景由 Tab 切换逻辑维护。
  final String? scenarioId;

  const AgentFloatingButton({
    super.key,
    this.scenarioId,
  });

  @override
  ConsumerState<AgentFloatingButton> createState() => _AgentFloatingButtonState();
}

class _AgentFloatingButtonState extends ConsumerState<AgentFloatingButton> {
  double _x = 16.0;
  double _y = 100.0;
  bool _isDragging = false;
  Offset _dragStart = Offset.zero;
  double _startX = 0;
  double _startY = 0;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final appColors = context.appColors;

    return Stack(
      children: [
        Positioned(
          left: _x,
          bottom: _y,
          child: GestureDetector(
            onPanStart: (details) {
              _isDragging = true;
              _dragStart = details.globalPosition;
              _startX = _x;
              _startY = _y;
            },
            onPanUpdate: (details) {
              if (!_isDragging) return;
              final dx = details.globalPosition.dx - _dragStart.dx;
              final dy = details.globalPosition.dy - _dragStart.dy;

              setState(() {
                _x = (_startX + dx).clamp(0.0, screenSize.width - 56);
                _y = (_startY - dy).clamp(0.0, screenSize.height - 56);
              });
            },
            onPanEnd: (details) {
              final dx = (_x - _startX).abs();
              final dy = (_y - _startY).abs();

              if (dx < 5 && dy < 5) {
                _showChatDialog();
              }

              _isDragging = false;

              setState(() {
                if (_x < screenSize.width / 2) {
                  _x = 16.0;
                } else {
                  _x = screenSize.width - 56;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    appColors.agentAccent,
                    appColors.chatButtonPrimary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: appColors.agentAccent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Icon(
                  Icons.auto_awesome,
                  color: appColors.agentOnBrand,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showChatDialog() {
    AgentChatLauncherEntry.open(context, scenarioId: widget.scenarioId);
  }
}

/// Agent 悬浮外壳
///
/// 包裹在应用外层，在所有页面之上渲染悬浮按钮。
class AgentFloatingShell extends StatelessWidget {
  final Widget child;

  /// 透传给 [AgentFloatingButton] 的场景 ID（null = 沿用全局当前值）。
  final String? scenarioId;

  const AgentFloatingShell({
    super.key,
    required this.child,
    this.scenarioId,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        AgentFloatingButton(scenarioId: scenarioId),
      ],
    );
  }
}

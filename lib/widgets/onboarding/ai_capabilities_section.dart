import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// AI 引擎能力说明卡片
///
/// 在 OnboardingScreen 的 AI 配置步骤中展示：配置一个 LLM 即可解锁的
/// 所有 AI 功能清单。每个能力条目包含图标、名称和一句说明。
///
/// 用于两类场景：
/// - **Onboarding**：引导用户了解"配一个 LLM 能做什么"
/// - **设置页**：未来可复用作为 AI 功能介绍面板
class AiCapabilitiesSection extends StatelessWidget {
  const AiCapabilitiesSection({super.key});

  /// 引擎名称
  ///
  /// 这些能力主体由 AI Agent 驱动（角色对话、文生图、章节改写等），
  /// 底层统一走 OpenAI 兼容的 LLM 调用。对用户统一称为「AI 引擎」，
  /// 避免暴露内部 DSL Engine / AI Agent 的技术划分。
  static const String _engineName = 'AI 引擎';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final aiColor = context.appColors.agentAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: aiColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aiColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: aiColor),
              const SizedBox(width: 8),
              Text(
                '配置后解锁的能力',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: aiColor,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: aiColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _engineName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: aiColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 能力列表
          _buildCapabilityRow(
            context,
            icon: Icons.brush,
            label: 'AI 特写',
            detail: '为情节生成沉浸式扩写或续写',
          ),
          _buildCapabilityRow(
            context,
            icon: Icons.edit_note,
            label: '段落改写',
            detail: '一键优化文笔、调整风格',
          ),
          _buildCapabilityRow(
            context,
            icon: Icons.summarize,
            label: '章节摘要 & 背景总结',
            detail: '快速回顾前情提要或世界观',
          ),
          _buildCapabilityRow(
            context,
            icon: Icons.person_search,
            label: '角色提取',
            detail: '智能识别章节中的角色和关系',
          ),
          _buildCapabilityRow(
            context,
            icon: Icons.image_search,
            label: '场景插图提示词生成',
            detail: '为插图生成精准提示词（需 ComfyUI 后端）',
          ),
          _buildCapabilityRow(
            context,
            icon: Icons.chat,
            label: '角色对话（AI Agent）',
            detail: '和书中角色直接对话，支持多角色群聊',
            isLast: true,
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          // 如何获取 Key
          Text(
            '💡 推荐已测试的 LLM 服务',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'DeepSeek  https://api.deepseek.com  · deepseek-v4-pro\n'
            'OpenAI  https://api.openai.com/v1  · gpt-4o-mini\n'
            '本地服务  http://localhost:11434/v1  · Ollama/vLLM',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String detail,
    bool isLast = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label  ',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: detail,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

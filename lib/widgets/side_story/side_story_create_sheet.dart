/// 创建番外弹层 — 需求表单 + AI 创作启动
///
/// 交互（见 design/side-story-ui-design.html 画面 4/5）：
/// 1. 挂载章节只读展示（从哪个入口进来就挂在哪章）
/// 2. 需求描述多行输入（唯一必填项）
/// 3. 期望章节数快选 chip（AI 决定 / 3 / 5 / 8，默认 AI 决定）
/// 4. 提交 → 打开 Agent 对话窗（side_story 场景）→ startSideStoryCreation
///    自动发送，逐章生成进度在对话窗内实时可见，可随时关闭浮窗
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/scenario_sessions_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/chapter.dart';
import '../../models/novel.dart';
import '../../services/logger_service.dart';
import '../../services/novel_agent/agent_scenario.dart';
import '../../utils/error_helper.dart';
import '../../widgets/agent_chat/agent_chat_launcher_entry.dart';

/// 期望章节数快选项（value 为 null 表示 AI 决定）
const List<(String, int?)> _kChapterCountOptions = [
  ('AI 决定', null),
  ('3 章', 3),
  ('5 章', 5),
  ('8 章', 8),
];

/// 创建番外底部弹层
class SideStoryCreateSheet extends ConsumerStatefulWidget {
  /// 宿主小说（主线或父番外——父番外即「番外套番外」）
  final Novel anchorNovel;

  /// 锚点章节（番外挂载点）
  final Chapter anchorChapter;

  const SideStoryCreateSheet({
    super.key,
    required this.anchorNovel,
    required this.anchorChapter,
  });

  /// 弹出创建番外表单
  static Future<void> show(
    BuildContext context, {
    required Novel anchorNovel,
    required Chapter anchorChapter,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SideStoryCreateSheet(
          anchorNovel: anchorNovel,
          anchorChapter: anchorChapter,
        ),
      ),
    );
  }

  @override
  ConsumerState<SideStoryCreateSheet> createState() =>
      _SideStoryCreateSheetState();
}

class _SideStoryCreateSheetState extends ConsumerState<SideStoryCreateSheet> {
  final _requirementController = TextEditingController();
  int? _desiredChapterCount;
  bool _submitting = false;

  @override
  void dispose() {
    _requirementController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final requirement = _requirementController.text.trim();
    if (requirement.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先描述番外需求（想看什么故事）')),
      );
      return;
    }
    setState(() => _submitting = true);

    LoggerService.instance.i(
      '提交番外创作: anchor=${widget.anchorChapter.title}, '
      'requirement长度=${requirement.length}, 期望章节数=$_desiredChapterCount',
      category: LogCategory.ai,
      tags: ['side-story', 'create', 'start'],
    );

    // 打开对话窗（切到 side_story 场景），让用户实时看到逐章生成过程；
    // 关闭浮窗不影响后台继续生成（会话在全局 scenarioSessionsProvider 中）。
    if (mounted) {
      AgentChatLauncherEntry.open(context, scenarioId: ScenarioIds.sideStory);
    }
    try {
      final session = ref
          .read(scenarioSessionsProvider.notifier)
          .get(ScenarioIds.sideStory);
      await session.startSideStoryCreation(
        anchorNovelUrl: widget.anchorNovel.url,
        anchorNovelTitle: widget.anchorNovel.title,
        anchorChapterUrl: widget.anchorChapter.url,
        anchorChapterTitle: widget.anchorChapter.title,
        requirement: requirement,
        desiredChapterCount: _desiredChapterCount,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ErrorHelper.showErrorWithLog(
        context,
        '启动番外创作失败',
        error: e,
        stackTrace: st,
        category: LogCategory.ai,
        tags: ['side-story', 'create', 'failed'],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽指示条
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 20, color: context.appColors.agentAccent),
                const SizedBox(width: 8),
                Text(
                  '创建番外',
                  style: AppTypography.novelTitle.copyWith(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 挂载章节（只读）
            _FieldLabel('挂载章节（自动带入）'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.menu_book,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.anchorChapter.title,
                      style: AppTypography.chapterTitle
                          .copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 需求描述（唯一必填）
            _FieldLabel('番外需求（必填）'),
            const SizedBox(height: 6),
            TextField(
              controller: _requirementController,
              maxLines: 4,
              minLines: 3,
              autofocus: true,
              style: const TextStyle(fontSize: 14, height: 1.6),
              decoration: const InputDecoration(
                hintText: '例如：写女主和闺蜜入山门之前的故事——两人因一场误会结怨，又在瘟疫中互相扶持成为闺蜜。风格温暖。',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            // 期望章节数快选
            _FieldLabel('期望章节数（可选）'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final (label, value) in _kChapterCountOptions)
                  ChoiceChip(
                    label: Text(label),
                    selected: _desiredChapterCount == value,
                    onSelected: (_) =>
                        setState(() => _desiredChapterCount = value),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'AI 将通读本章正文、人物卡与你的写作技巧，自动拟定番外标题并逐章生成；过程中可随时关闭浮窗，生成在后台继续。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_submitting ? '正在启动…' : '开始创作'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表单字段小标签
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).hintColor,
          ),
    );
  }
}

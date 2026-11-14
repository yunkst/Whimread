/// 番外创作结果跳转入口卡片
///
/// 在 Agent 聊天窗口中，当 `create_side_story` 工具成功完成时渲染此卡片。
/// 用户点击后加载番外的章节列表，进入番外目录页开始阅读。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../screens/chapter_list_screen_riverpod.dart';
import '../../services/logger_service.dart';
import '../../utils/toast_utils.dart';

/// 解析 create_side_story 工具结果 JSON，成功时返回入口数据，否则返回 null。
SideStoryEntryData? parseSideStoryEntry(String? toolResultJson) {
  if (toolResultJson == null) return null;
  try {
    final json = jsonDecode(toolResultJson) as Map<String, dynamic>;
    if (json['success'] != true) return null;
    final sideStoryUrl = json['sideStoryUrl'] as String?;
    final title = json['sideStoryTitle'] as String?;
    if (sideStoryUrl == null || title == null) return null;
    return SideStoryEntryData(
      sideStoryUrl: sideStoryUrl,
      sideStoryTitle: title,
      anchorChapter: json['anchorChapter'] as String? ?? '',
    );
  } catch (_) {
    return null;
  }
}

class SideStoryEntryData {
  /// 番外的 novelUrl（custom://sidestory/ 时间戳，章节列表页按它加载）
  final String sideStoryUrl;
  final String sideStoryTitle;

  /// 锚点章标题（展示挂载点）
  final String anchorChapter;

  const SideStoryEntryData({
    required this.sideStoryUrl,
    required this.sideStoryTitle,
    required this.anchorChapter,
  });
}

class SideStoryEntryCard extends ConsumerStatefulWidget {
  final SideStoryEntryData data;

  const SideStoryEntryCard({super.key, required this.data});

  @override
  ConsumerState<SideStoryEntryCard> createState() =>
      _SideStoryEntryCardState();
}

class _SideStoryEntryCardState extends ConsumerState<SideStoryEntryCard> {
  bool _opening = false;

  Future<void> _openSideStory() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final novel = await ref
          .read(novelRepositoryProvider)
          .getNovelByUrl(widget.data.sideStoryUrl);
      if (!mounted) return;
      if (novel == null) {
        ToastUtils.showError('找不到该番外，可能已被删除');
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChapterListScreenRiverpod(novel: novel),
        ),
      );
    } catch (e, st) {
      LoggerService.instance.e(
        '打开番外失败: ${widget.data.sideStoryUrl} - $e',
        stackTrace: st.toString(),
        category: LogCategory.ui,
        tags: ['side-story', 'entry-card', 'failed'],
      );
      if (mounted) {
        ToastUtils.showError('打开番外失败');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.agentAccent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: _openSideStory,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: context.appColors.agentAccent.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_stories,
                  size: 22, color: context.appColors.agentAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '番外《${widget.data.sideStoryTitle}》已建立',
                      style: AppTypography.novelTitle.copyWith(fontSize: 13.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.data.anchorChapter.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '挂载于「${widget.data.anchorChapter}」· 章节生成中或已完成，点击进入番外目录',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.appColors.inkSoft),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  color: context.appColors.agentAccent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _opening ? '打开中…' : '去阅读',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

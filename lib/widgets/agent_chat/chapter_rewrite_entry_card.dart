/// 章节重写结果跳转入口卡片
///
/// 在 Agent 聊天窗口中，当 `update_chapter_content` 工具成功完成（AI 重写章节）
/// 时渲染此卡片。用户点击后，从数据库加载小说和章节列表，跳转到阅读器查看改后正文。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart';
import '../../screens/reader_screen.dart';
import '../../services/logger_service.dart';
import '../../utils/toast_utils.dart';

/// 解析工具结果 JSON，成功重写时返回入口数据，否则返回 null。
ChapterRewriteEntryData? parseRewriteEntry(String? toolResultJson) {
  if (toolResultJson == null) return null;
  try {
    final json = jsonDecode(toolResultJson) as Map<String, dynamic>;
    if (json['success'] != true) return null;
    final novelUrl = json['novelUrl'] as String?;
    final chapterUrl = json['chapterUrl'] as String?;
    if (novelUrl == null || chapterUrl == null) return null;
    return ChapterRewriteEntryData(
      novelUrl: novelUrl,
      chapterUrl: chapterUrl,
      chapterTitle: json['chapterTitle'] as String? ?? '章节',
      charCount: json['charCount'] as int?,
    );
  } catch (_) {
    return null;
  }
}

class ChapterRewriteEntryData {
  final String novelUrl;
  final String chapterUrl;
  final String chapterTitle;
  final int? charCount;

  const ChapterRewriteEntryData({
    required this.novelUrl,
    required this.chapterUrl,
    required this.chapterTitle,
    this.charCount,
  });
}

class ChapterRewriteEntryCard extends ConsumerStatefulWidget {
  final ChapterRewriteEntryData data;
  /// 入口卡片的主文案（默认"查看章节"）。由调用方按场景传入，
  /// 如 update_chapter_content 传"查看重写后的章节"，create_chapter 传"查看新创建的章节"。
  final String titleText;

  const ChapterRewriteEntryCard({
    super.key,
    required this.data,
    this.titleText = '查看章节',
  });

  @override
  ConsumerState<ChapterRewriteEntryCard> createState() =>
      _ChapterRewriteEntryCardState();
}

class _ChapterRewriteEntryCardState
    extends ConsumerState<ChapterRewriteEntryCard> {
  bool _opening = false;

  Future<void> _openInReader() async {
    if (_opening) return;
    setState(() => _opening = true);

    try {
      final novelRepo = ref.read(novelRepositoryProvider);
      final chapterRepo = ref.read(chapterRepositoryProvider);

      final novel = await novelRepo.getNovelByUrl(widget.data.novelUrl);
      if (novel == null) {
        if (mounted) {
          ToastUtils.showError('找不到该小说，可能已被移出书架');
        }
        return;
      }

      final chapters = await chapterRepo.getCachedNovelChapters(widget.data.novelUrl);
      if (chapters.isEmpty) {
        if (mounted) {
          ToastUtils.showError('找不到章节列表');
        }
        return;
      }

      // 定位到被重写的章节
      final chapter = chapters.firstWhere(
        (c) => c.url == widget.data.chapterUrl,
        orElse: () => chapters.first,
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ReaderScreen(
            novel: novel,
            chapter: chapter,
            chapters: chapters,
          ),
        ),
      );
    } catch (e, stack) {
      LoggerService.instance.e(
        '打开重写章节失败: $e',
        stackTrace: stack.toString(),
        category: LogCategory.ai,
        tags: ['agent_chat', 'rewrite_entry', 'open_failed'],
      );
      if (mounted) {
        ToastUtils.showError('打开失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _opening ? null : _openInReader,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              _opening
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : Icon(Icons.menu_book_outlined,
                      size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.titleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.data.charCount != null
                          ? '${widget.data.chapterTitle} · ${widget.data.charCount} 字'
                          : widget.data.chapterTitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 12, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

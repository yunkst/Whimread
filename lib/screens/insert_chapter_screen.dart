import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../utils/toast_utils.dart';

/// 插入章节页面
///
/// 纯手动模式：用户输入章节标题和正文，确认后直接插入到小说中。
class InsertChapterScreen extends ConsumerStatefulWidget {
  final Novel novel;
  final int afterIndex;
  final List<Chapter> chapters;
  final String? prefillTitle;
  final String? prefillContent;

  const InsertChapterScreen({
    required this.novel,
    required this.afterIndex,
    required this.chapters,
    this.prefillTitle,
    this.prefillContent,
    super.key,
  });

  @override
  ConsumerState<InsertChapterScreen> createState() =>
      _InsertChapterScreenState();
}

class _InsertChapterScreenState extends ConsumerState<InsertChapterScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.prefillTitle ?? '');
    _contentController =
        TextEditingController(text: widget.prefillContent ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _handleConfirm() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      ToastUtils.showWarning('请输入章节标题');
      return;
    }
    if (content.isEmpty) {
      ToastUtils.showWarning('请输入章节内容');
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, {
      'title': title,
      'content': content,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.chapters.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.add_circle, color: context.appColors.info),
            const SizedBox(width: 8),
            Text(
              isEmpty ? '创建新章节' : '插入新章节',
              style: AppTypography.chapterTitle.copyWith(fontSize: 18),
            ),
          ],
        ),
      ),
      body: _buildBody(isEmpty),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody(bool isEmpty) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 提示信息
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: context.appColors.onInfoContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEmpty
                        ? '将为小说"${widget.novel.title}"创建第一章'
                        : '将在第${widget.afterIndex + 1}章"${widget.chapters[widget.afterIndex].title}"后插入新章节',
                    style: AppTypography.bodyProse.copyWith(
                      fontSize: 14,
                      height: 1.5,
                      color: context.appColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 章节标题输入
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '章节标题',
                hintText: isEmpty
                    ? '例如：第一章 故事的开始'
                    : '例如：第十五章 意外的相遇',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 章节内容输入
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '章节内容',
                hintText: '输入章节正文内容...',
                border: OutlineInputBorder(),
              ),
              maxLines: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _handleConfirm,
            child: const Text('插入'),
          ),
        ],
      ),
    );
  }
}

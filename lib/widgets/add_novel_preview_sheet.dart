/// 「添加小说」预览底部弹窗
///
/// 显示脚本提取的小说标题和章节列表，供用户确认后添加到书架。
///
/// 布局：
///   - 拖拽手柄
///   - "预览小说信息" 标题
///   - 可编辑的小说标题（TextField）
///   - 来源 URL（灰色小字）
///   - "共 N 章" 副标题
///   - 前 10 章列表
///   - "...还有 X 章未显示"（超过 10 章时）
///   - [取消] [添加到书架] 按钮
library;

import 'package:flutter/material.dart';
import 'common/bottom_sheet_header.dart';

class AddNovelPreviewSheet extends StatefulWidget {
  /// 提取到的小说标题
  final String title;

  /// 提取到的章节列表 [{title, url}, ...]
  final List<Map<String, String>> chapters;

  /// 来源页面 URL
  final String sourceUrl;

  const AddNovelPreviewSheet({
    super.key,
    required this.title,
    required this.chapters,
    required this.sourceUrl,
  });

  @override
  State<AddNovelPreviewSheet> createState() => _AddNovelPreviewSheetState();
}

class _AddNovelPreviewSheetState extends State<AddNovelPreviewSheet> {
  late TextEditingController _titleController;
  static const int _maxPreviewChapters = 10;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalChapters = widget.chapters.length;
    final previewChapters = widget.chapters.take(_maxPreviewChapters).toList();
    final remainingCount = totalChapters - _maxPreviewChapters;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(
            icon: Icons.menu_book,
            title: '预览小说信息',
            titleStyle: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
            trailing: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '共 $totalChapters 章',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // 小说标题（可编辑）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '小说标题',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.title, size: 18),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),

          // 来源 URL（次要小字）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.link,
                    size: 12, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.sourceUrl,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 章节列表
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: previewChapters.length + (remainingCount > 0 ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                // "还有 X 章" 提示
                if (index == previewChapters.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        '...还有 $remainingCount 章未显示',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }

                final chapter = previewChapters[index];
                final chapterIndex = index + 1;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      // 章节序号
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$chapterIndex',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 章节标题
                      Expanded(
                        child: Text(
                          chapter['title'] ?? '',
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // 操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final editedTitle = _titleController.text.trim();
                    // 返回确认结果 + 编辑后的标题
                    Navigator.of(context).pop({
                      'confirmed': true,
                      'title': editedTitle.isEmpty ? widget.title : editedTitle,
                    });
                  },
                  icon: const Icon(Icons.library_add, size: 16),
                  label: const Text('添加到书架'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/novel.dart';

import '../empty_states/empty_state_view.dart';

/// 小说选择对话框
///
/// 列出书架中的所有小说供用户选择。
/// 调用方：AgentChatDialog 的"切换"按钮。
class AgentNovelPickerDialog extends ConsumerStatefulWidget {
  const AgentNovelPickerDialog({super.key});

  @override
  ConsumerState<AgentNovelPickerDialog> createState() =>
      _AgentNovelPickerDialogState();
}

class _AgentNovelPickerDialogState
    extends ConsumerState<AgentNovelPickerDialog> {
  late Future<List<Novel>> _novelsFuture;

  @override
  void initState() {
    super.initState();
    _novelsFuture = _loadNovels();
  }

  Future<List<Novel>> _loadNovels() async {
    final repo = ref.read(novelRepositoryProvider);
    return repo.getNovels();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 480,
          maxHeight: 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.menu_book, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '选择小说',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<Novel>>(
                future: _novelsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('加载失败：${snapshot.error}',
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    );
                  }
                  final novels = snapshot.data ?? const [];
                  if (novels.isEmpty) {
                    return const EmptyStateView(
                      icon: Icons.library_books_outlined,
                      title: '书架为空',
                      subtitle: '请先在浏览器中添加小说到书架',
                      padding: EdgeInsets.symmetric(horizontal: 16),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: novels.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = novels[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              theme.colorScheme.primaryContainer,
                          child: Text(
                            n.title.isNotEmpty ? n.title[0] : '?',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        title: Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          n.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, n.id),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

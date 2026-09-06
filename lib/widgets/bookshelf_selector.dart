import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bookshelf.dart';
import '../services/logger_service.dart';
import '../utils/error_helper.dart';
import '../utils/toast_utils.dart';
import '../core/providers/database_providers.dart';

/// 书架选择器组件
///
/// 显示在BookshelfScreen顶部，用于切换和创建书架
class BookshelfSelector extends ConsumerStatefulWidget {
  /// 当前选中的书架ID
  final int currentBookshelfId;

  /// 书架切换回调
  final ValueChanged<int> onBookshelfChanged;

  const BookshelfSelector({
    super.key,
    required this.currentBookshelfId,
    required this.onBookshelfChanged,
  });

  @override
  ConsumerState<BookshelfSelector> createState() => _BookshelfSelectorState();
}

class _BookshelfSelectorState extends ConsumerState<BookshelfSelector> {
  List<Bookshelf> _bookshelves = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookshelves();
  }

  Future<void> _loadBookshelves() async {
    final bookshelfRepository = ref.read(bookshelfRepositoryProvider);
    setState(() {
      _isLoading = true;
    });

    try {
      final bookshelves = await bookshelfRepository.getBookshelves();
      if (mounted) {
        setState(() {
          _bookshelves = bookshelves;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '加载书架列表失败',
        stackTrace: stackTrace.toString(),
        category: LogCategory.database,
        tags: ['bookshelf', 'list', 'load', 'failed'],
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateBookshelfDialog() async {
    final bookshelfRepository = ref.read(bookshelfRepositoryProvider);
    final nameController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.create_new_folder,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('新建书架'),
          ],
        ),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '书架名称',
            hintText: '请输入书架名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                LoggerService.instance.w(
                  '书架名称为空',
                  category: LogCategory.ui,
                  tags: ['bookshelf', 'validation', 'empty-name'],
                );
                ToastUtils.showError('请输入书架名称');
                return;
              }
              Navigator.pop(context, name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await bookshelfRepository.createBookshelf(result);
        if (mounted) {
          LoggerService.instance.i(
            '书架创建成功',
            category: LogCategory.database,
            tags: ['bookshelf', 'create', 'success'],
          );
          ToastUtils.showSuccess('书架创建成功', context: context);
          _loadBookshelves(); // 重新加载书架列表
        }
      } catch (e, stackTrace) {
        if (!mounted) return;
        ErrorHelper.showErrorWithLog(
          context,
          '创建失败',
          stackTrace: stackTrace,
          category: LogCategory.database,
          tags: ['bookshelf', 'create', 'failed'],
        );
      }
    }
  }

  void _showBookshelfMenu(Bookshelf bookshelf) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.folder_open,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(bookshelf.name),
              subtitle: Text(bookshelf.isSystem ? '系统书架' : '自定义书架'),
            ),
            const Divider(),
            if (!bookshelf.isSystem) ...[
              ListTile(
                leading: Icon(Icons.delete,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('删除书架'),
                onTap: () async {
                  Navigator.pop(context);

                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('确认删除'),
                      content: Text(
                        '确定要删除书架"${bookshelf.name}"吗？\n'
                        '书架内的小说不会被删除。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    final bookshelfRepository =
                        ref.read(bookshelfRepositoryProvider);
                    final success =
                        await bookshelfRepository.deleteBookshelf(
                      bookshelf.id,
                    );
                    if (!mounted) return;

                    if (success) {
                      // 如果删除的是当前书架，切换到"全部小说"
                      if (widget.currentBookshelfId == bookshelf.id) {
                        widget.onBookshelfChanged(1);
                      }
                      _loadBookshelves();
                      ToastUtils.showSuccess('书架已删除');
                    } else {
                      ToastUtils.showError('删除失败');
                    }
                  }
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('关闭'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // 如果书架列表为空，显示提示信息
    if (_bookshelves.isEmpty) {
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder_off,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '暂无书架',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建书架',
              onPressed: _showCreateBookshelfDialog,
            ),
          ],
        ),
      );
    }

    final currentBookshelf = _bookshelves.firstWhere(
      (b) => b.id == widget.currentBookshelfId,
      orElse: () => _bookshelves.first,
    );

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            currentBookshelf.isSystem ? Icons.folder_shared : Icons.folder,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _showBookshelfSelectionDialog(),
              child: Row(
                children: [
                  Text(
                    currentBookshelf.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建书架',
            onPressed: _showCreateBookshelfDialog,
          ),
        ],
      ),
    );
  }

  void _showBookshelfSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择书架'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _bookshelves.length,
            itemBuilder: (context, index) {
              final bookshelf = _bookshelves[index];
              final isSelected = bookshelf.id == widget.currentBookshelfId;

              return ListTile(
                leading: Icon(
                  bookshelf.isSystem ? Icons.folder_shared : Icons.folder,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                ),
                title: Text(
                  bookshelf.name,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {
                          Navigator.pop(context);
                          _showBookshelfMenu(bookshelf);
                        },
                      ),
                onTap: () {
                  Navigator.pop(context);
                  if (bookshelf.id != widget.currentBookshelfId) {
                    widget.onBookshelfChanged(bookshelf.id);
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

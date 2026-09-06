import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/webview_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/bookmark_service.dart';

/// 收藏夹弹出面板
///
/// 功能：
/// - 按分组折叠展示收藏
/// - 「未分组」始终作为最后一个分组展示
/// - 点击收藏项跳转到对应 URL
/// - 长按收藏项 → 重命名 / 移动分组 / 删除
/// - 顶部新增「管理分组」入口
class BookmarkPanel extends ConsumerStatefulWidget {
  /// 点击收藏项时的回调（跳转 URL）
  final void Function(String url) onNavigate;

  const BookmarkPanel({super.key, required this.onNavigate});

  @override
  ConsumerState<BookmarkPanel> createState() => _BookmarkPanelState();
}

/// 「未分组」的虚拟分组 ID（在分组列表里用于唯一标识）
const String _kUngroupedGroupId = '__ungrouped__';

/// 「未分组」在移动对话框返回值中的 sentinel（与 null 区分开，
/// null 表示用户取消，sentinel 表示用户主动选了「未分组」）
const String _kUngroupedSentinel = '__move_to_ungrouped__';

class _BookmarkPanelState extends ConsumerState<BookmarkPanel> {
  /// 当前展开的分组 ID 集合（null = 无）。
  /// 全部 null 时表示首次进入，后续默认全部展开。
  Set<String>? _expandedGroupIds;

  @override
  Widget build(BuildContext context) {
    final bookmarksAsync = ref.watch(bookmarkListProvider);
    final groupsAsync = ref.watch(bookmarkGroupListProvider);
    final currentUrl = ref.watch(webviewCurrentUrlProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部把手
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.bookmark, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '收藏夹',
                  style: AppTypography.novelTitle.copyWith(
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // 管理分组按钮
                IconButton(
                  icon: Icon(
                    Icons.folder_open,
                    size: 22,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  tooltip: '管理分组',
                  onPressed: () => _showGroupManagement(context),
                ),
                // 添加当前页面
                _AddBookmarkButton(currentUrl: currentUrl),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // 收藏列表
          Flexible(
            child: _buildBookmarkList(
                bookmarksAsync, groupsAsync, colorScheme),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 收藏列表（按分组）
  // ============================================================

  Widget _buildBookmarkList(
    AsyncValue<List<Bookmark>> bookmarksAsync,
    AsyncValue<List<BookmarkGroup>> groupsAsync,
    ColorScheme colorScheme,
  ) {
    if (bookmarksAsync is AsyncLoading || groupsAsync is AsyncLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (bookmarksAsync is AsyncError) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('加载失败',
              style: TextStyle(color: colorScheme.error)),
        ),
      );
    }
    final bookmarks = bookmarksAsync.value ?? const <Bookmark>[];
    final groups = groupsAsync.value ?? const <BookmarkGroup>[];

    if (bookmarks.isEmpty && groups.isEmpty) {
      return _EmptyState(colorScheme: colorScheme);
    }

    // 把收藏按 groupId 分桶；null 桶归入「未分组」
    final byGroupId = <String, List<Bookmark>>{};
    final ungrouped = <Bookmark>[];
    for (final b in bookmarks) {
      if (b.groupId == null) {
        ungrouped.add(b);
      } else {
        byGroupId.putIfAbsent(b.groupId!, () => []).add(b);
      }
    }

    // 默认全展开；用户折叠后记忆
    _expandedGroupIds ??= {
      ...groups.map((g) => g.id),
      _kUngroupedGroupId,
    };

    // 分组渲染顺序：先用户分组（按 createdAt 升序），最后「未分组」
    final sections = <_BookmarkSection>[];
    for (final g in groups) {
      sections.add(_BookmarkSection(
        id: g.id,
        name: g.name,
        bookmarks: byGroupId[g.id] ?? const [],
      ));
    }
    sections.add(_BookmarkSection(
      id: _kUngroupedGroupId,
      name: '未分组',
      bookmarks: ungrouped,
    ));

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return _GroupSectionTile(
          section: section,
          isExpanded: _expandedGroupIds!.contains(section.id),
          onTapHeader: () => _toggleSection(section.id),
          onTapBookmark: (bookmark) {
            widget.onNavigate(bookmark.url);
            Navigator.of(context).pop();
          },
          onDeleteBookmark: (id) {
            ref.read(bookmarkListProvider.notifier).removeBookmark(id);
          },
          onRenameBookmark: (id, title) {
            ref
                .read(bookmarkListProvider.notifier)
                .renameBookmark(id, title);
          },
          onMoveBookmark: (id, groupId) {
            ref
                .read(bookmarkListProvider.notifier)
                .moveBookmark(id, groupId);
          },
          onRenameGroup: (id, name) {
            ref.read(bookmarkGroupListProvider.notifier).renameGroup(id, name);
          },
          onDeleteGroup: (id) {
            ref.read(bookmarkGroupListProvider.notifier).deleteGroup(id);
          },
          allGroups: groups,
          ungroupedSectionId: _kUngroupedGroupId,
        );
      },
    );
  }

  void _toggleSection(String id) {
    final next = Set<String>.from(_expandedGroupIds!);
    if (!next.add(id)) next.remove(id);
    setState(() => _expandedGroupIds = next);
  }

  // ============================================================
  // 分组管理面板
  // ============================================================

  Future<void> _showGroupManagement(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _GroupManagementSheet(),
    );
  }
}

// ============================================================
// 收藏列表分组区块
// ============================================================

class _BookmarkSection {
  final String id;
  final String name;
  final List<Bookmark> bookmarks;

  const _BookmarkSection({
    required this.id,
    required this.name,
    required this.bookmarks,
  });
}

class _GroupSectionTile extends StatelessWidget {
  final _BookmarkSection section;
  final bool isExpanded;
  final VoidCallback onTapHeader;
  final void Function(Bookmark) onTapBookmark;
  final void Function(String id) onDeleteBookmark;
  final void Function(String id, String title) onRenameBookmark;
  final void Function(String id, String? groupId) onMoveBookmark;
  final void Function(String id, String name) onRenameGroup;
  final void Function(String id) onDeleteGroup;
  final List<BookmarkGroup> allGroups;
  final String ungroupedSectionId;

  const _GroupSectionTile({
    required this.section,
    required this.isExpanded,
    required this.onTapHeader,
    required this.onTapBookmark,
    required this.onDeleteBookmark,
    required this.onRenameBookmark,
    required this.onMoveBookmark,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.allGroups,
    required this.ungroupedSectionId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUngrouped = section.id == ungroupedSectionId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTapHeader,
          onLongPress: isUngrouped
              ? null
              : () => _showGroupHeaderMenu(context),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isUngrouped
                      ? Icons.inbox_outlined
                      : (isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right),
                  size: 18,
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                if (!isUngrouped)
                  Icon(Icons.folder_outlined,
                      size: 16, color: colorScheme.primary),
                if (!isUngrouped) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    section.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (section.bookmarks.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${section.bookmarks.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded) _buildChildren(colorScheme),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildChildren(ColorScheme colorScheme) {
    if (section.bookmarks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(48, 0, 16, 10),
        child: Text(
          '暂无收藏',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    return Column(
      children: section.bookmarks
          .map((b) => _BookmarkTile(
                bookmark: b,
                onTap: () => onTapBookmark(b),
                onDelete: () => onDeleteBookmark(b.id),
                onRename: (title) => onRenameBookmark(b.id, title),
                onMove: (groupId) => onMoveBookmark(b.id, groupId),
                allGroups: allGroups,
                ungroupedSectionId: ungroupedSectionId,
              ))
          .toList(),
    );
  }

  void _showGroupHeaderMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('重命名「${section.name}」'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final newName =
                      await _showRenameGroupDialog(context, section.name);
                  if (newName != null && newName.isNotEmpty) {
                    onRenameGroup(section.id, newName);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text('删除「${section.name}」'),
                subtitle: const Text('组内收藏将归入「未分组」'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final confirmed = await _confirmDeleteGroup(
                      context, section.name, section.bookmarks.length);
                  if (confirmed == true) {
                    onDeleteGroup(section.id);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _showRenameGroupDialog(
      BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分组名',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDeleteGroup(
      BuildContext context, String name, int count) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text(
          count == 0
              ? '确定删除「$name」吗？'
              : '确定删除「$name」吗？\n组内 $count 条收藏将归入「未分组」。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 单个收藏项
// ============================================================

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(String title) onRename;
  final void Function(String? groupId) onMove;
  final List<BookmarkGroup> allGroups;
  final String ungroupedSectionId;

  const _BookmarkTile({
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
    required this.onMove,
    required this.allGroups,
    required this.ungroupedSectionId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colorScheme.error,
        child: Icon(Icons.delete_outline, color: colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除收藏'),
            content: Text('确定删除「${bookmark.title}」吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        dense: true,
        leading:
            Icon(Icons.language, size: 20, color: colorScheme.primary),
        title: Text(
          bookmark.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.novelTitle.copyWith(
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          bookmark.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.metaItalic.copyWith(
            fontSize: 11,
            color: context.appColors.inkSoft,
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.close,
              size: 18,
              color: colorScheme.onSurface.withValues(alpha: 0.4)),
          tooltip: '删除',
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除收藏'),
                content: Text('确定删除「${bookmark.title}」吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            if (confirmed == true) onDelete();
          },
        ),
        onTap: onTap,
        onLongPress: () => _showBookmarkMenu(context),
      ),
    );
  }

  void _showBookmarkMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    bookmark.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(sheetCtx).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('重命名'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final newTitle =
                      await _showRenameDialog(context, bookmark.title);
                  if (newTitle != null && newTitle.isNotEmpty) {
                    onRename(newTitle);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('移动到分组'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final targetGroupId =
                      await _showMoveDialog(context);
                  // null = 用户取消；'__ungrouped__' sentinel 转回 null = 未分组
                  if (targetGroupId == null) return;
                  onMove(targetGroupId == _kUngroupedSentinel
                      ? null
                      : targetGroupId);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('删除'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除收藏'),
                      content: Text('确定删除「${bookmark.title}」吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 重命名对话框。返回 null 表示取消；非空字符串为新标题。
  Future<String?> _showRenameDialog(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名收藏'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标题',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 选择目标分组。
  /// - 返回 `null`：用户取消（关闭面板未选择）
  /// - 返回 [_kUngroupedSentinel]：用户选择了「未分组」
  /// - 返回真实 groupId：用户选择了某个分组
  Future<String?> _showMoveDialog(BuildContext context) async {
    return showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final colorScheme = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '移动到分组',
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 16,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.inbox_outlined),
                title: const Text('未分组'),
                trailing: bookmark.groupId == null
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                selected: bookmark.groupId == null,
                onTap: () => Navigator.pop(sheetCtx, _kUngroupedSentinel),
              ),
              ...allGroups.map(
                (g) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(g.name),
                  trailing: bookmark.groupId == g.id
                      ? Icon(Icons.check, color: colorScheme.primary)
                      : null,
                  selected: bookmark.groupId == g.id,
                  onTap: () => Navigator.pop(sheetCtx, g.id),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// 添加收藏按钮
// ============================================================

class _AddBookmarkButton extends ConsumerWidget {
  final String currentUrl;

  const _AddBookmarkButton({required this.currentUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarkListProvider);
    final isBookmarked =
        bookmarksAsync.value?.any((b) => b.url == currentUrl) ?? false;
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(
        isBookmarked ? Icons.bookmark : Icons.bookmark_add_outlined,
        size: 22,
        color: isBookmarked
            ? colorScheme.primary
            : colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      tooltip: isBookmarked ? '已收藏' : '收藏当前页面',
      onPressed: isBookmarked
          ? null
          : () async {
              final uri = Uri.tryParse(currentUrl);
              final defaultTitle = uri?.host ?? currentUrl;

              final result = await showDialog<({String title, String? groupId})>(
                context: context,
                builder: (ctx) => _AddBookmarkDialog(
                  defaultTitle: defaultTitle,
                  url: currentUrl,
                ),
              );

              if (result != null && result.title.isNotEmpty) {
                ref.read(bookmarkListProvider.notifier).addBookmark(
                      title: result.title,
                      url: currentUrl,
                      groupId: result.groupId,
                    );
              }
            },
    );
  }
}

/// 添加收藏对话框（支持选分组）
class _AddBookmarkDialog extends ConsumerStatefulWidget {
  final String defaultTitle;
  final String url;

  const _AddBookmarkDialog({
    required this.defaultTitle,
    required this.url,
  });

  @override
  ConsumerState<_AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends ConsumerState<_AddBookmarkDialog> {
  late final TextEditingController _titleController;
  String? _selectedGroupId; // null = 未分组
  static const String _newGroupSentinel = '__new_group__';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.defaultTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(bookmarkGroupListProvider);
    final groups = groupsAsync.value ?? const <BookmarkGroup>[];

    return AlertDialog(
      title: const Text('添加收藏'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '标题',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _selectedGroupId,
            isDense: true,
            decoration: const InputDecoration(
              labelText: '分组（可选）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('未分组'),
              ),
              ...groups.map((g) => DropdownMenuItem<String?>(
                    value: g.id,
                    child: Text(g.name, overflow: TextOverflow.ellipsis),
                  )),
              const DropdownMenuItem<String?>(
                value: _newGroupSentinel,
                child: Text('➕ 新建分组…'),
              ),
            ],
            onChanged: (value) async {
              if (value == _newGroupSentinel) {
                final name = await _showCreateGroupInline(context);
                if (name != null && name.isNotEmpty) {
                  final created = await ref
                      .read(bookmarkGroupListProvider.notifier)
                      .addGroup(name);
                  if (created != null && mounted) {
                    setState(() => _selectedGroupId = created.id);
                  }
                }
              } else {
                setState(() => _selectedGroupId = value);
              }
            },
          ),
          const SizedBox(height: 12),
          Text(
            widget.url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isNotEmpty) {
              Navigator.of(context).pop(
                  (title: title, groupId: _selectedGroupId));
            }
          },
          child: const Text('添加'),
        ),
      ],
    );
  }

  Future<String?> _showCreateGroupInline(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分组名',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 分组管理面板
// ============================================================

class _GroupManagementSheet extends ConsumerWidget {
  const _GroupManagementSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(bookmarkGroupListProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部把手
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.folder_open,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '管理分组',
                  style: AppTypography.novelTitle.copyWith(
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () async {
                    final name = await _showInlineCreate(context);
                    if (name != null && name.isNotEmpty) {
                      await ref
                          .read(bookmarkGroupListProvider.notifier)
                          .addGroup(name);
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Flexible(
            child: groupsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('加载失败',
                      style: TextStyle(color: colorScheme.error)),
                ),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_off_outlined,
                              size: 48,
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text(
                            '暂无分组',
                            style: TextStyle(
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '点击右上角「新建」',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1, indent: 56),
                  itemBuilder: (context, index) {
                    final g = groups[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.folder_outlined,
                          color: colorScheme.primary),
                      title: Text(g.name),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: '重命名',
                            onPressed: () async {
                              final name =
                                  await _showInlineRename(context, g.name);
                              if (name != null && name.isNotEmpty) {
                                await ref
                                    .read(bookmarkGroupListProvider.notifier)
                                    .renameGroup(g.id, name);
                              }
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 18,
                                color: colorScheme.error),
                            tooltip: '删除',
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('删除分组'),
                                  content: Text(
                                      '确定删除「${g.name}」吗？\n组内收藏将归入「未分组」。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await ref
                                    .read(bookmarkGroupListProvider.notifier)
                                    .deleteGroup(g.id);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<String?> _showInlineCreate(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分组名',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showInlineRename(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分组名',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 空状态
// ============================================================

class _EmptyState extends StatelessWidget {
  final ColorScheme colorScheme;

  const _EmptyState({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border,
                size: 48,
                color: colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              '暂无收藏',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点击右上角添加当前页面',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

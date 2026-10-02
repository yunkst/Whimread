/// 角色卡版本历史页
///
/// 展示 character_revisions 的快照版本（新→旧）：每条记录修改时间/来源
/// （手动编辑/写作助手/文字游戏/版本回滚）/来源定位/修改原因。点开一条
/// 可看该版本整卡快照，并支持一键回滚到该版本（回滚本身也会追加一条
/// rollback 版本，历史保持 append-only 线性）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart'
    show characterRepositoryProvider;
import '../../models/character.dart';
import '../../models/character_revision.dart';
import '../../utils/toast_utils.dart';

class CharacterRevisionHistoryScreen extends ConsumerStatefulWidget {
  final int characterId;

  const CharacterRevisionHistoryScreen({super.key, required this.characterId});

  @override
  ConsumerState<CharacterRevisionHistoryScreen> createState() =>
      _CharacterRevisionHistoryScreenState();
}

class _CharacterRevisionHistoryScreenState
    extends ConsumerState<CharacterRevisionHistoryScreen> {
  String _name = '';
  bool _loading = true;
  List<CharacterRevision> _revisions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(characterRepositoryProvider);
    final card = await repo.getCharacter(widget.characterId);
    final revisions = await repo.getRevisions(widget.characterId);
    if (!mounted) return;
    setState(() {
      _name = card?.name ?? '（角色已删除）';
      _revisions = revisions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('「$_name」版本历史')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _revisions.isEmpty
              ? Center(
                  child: Text('暂无版本记录',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _revisions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _tile(context, _revisions[i]),
                ),
    );
  }

  Widget _tile(BuildContext context, CharacterRevision r) {
    final theme = Theme.of(context);
    final created =
        '${r.createdAt.year}-${r.createdAt.month.toString().padLeft(2, '0')}-'
        '${r.createdAt.day.toString().padLeft(2, '0')} '
        '${r.createdAt.hour.toString().padLeft(2, '0')}:'
        '${r.createdAt.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        title: Row(
          children: [
            _sourceBadge(context, r.source),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                r.reason?.isNotEmpty == true ? r.reason! : '（未记录原因）',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '$created'
            '${r.sourceRef?.isNotEmpty == true ? " · ${r.sourceRef}" : ""}'
            '${r.id != null ? " · #${r.id}" : ""}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showSnapshot(context, r),
      ),
    );
  }

  Widget _sourceBadge(BuildContext context, String source) {
    final theme = Theme.of(context);
    final color = switch (source) {
      CharacterRevisionSource.manual => theme.colorScheme.primary,
      CharacterRevisionSource.writingAgent => Colors.deepPurple,
      CharacterRevisionSource.textGame => Colors.teal,
      CharacterRevisionSource.rollback => theme.colorScheme.outline,
      _ => theme.colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        CharacterRevisionSource.label(source),
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  /// 版本快照详情 + 回滚
  Future<void> _showSnapshot(BuildContext context, CharacterRevision r) async {
    final snapshot = r.parseSnapshot();
    if (snapshot == null) {
      ToastUtils.showError('该版本快照已损坏，无法查看/回滚');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('版本 #${r.id} · ${CharacterRevisionSource.label(r.source)}',
                  style: Theme.of(context).textTheme.titleLarge),
              if (r.reason?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('原因：${r.reason}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 14),
              ..._snapshotLines(snapshot).map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: sheetContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('回滚到该版本'),
                        content: Text(
                            '将把「${snapshot.name}」恢复到此版本的内容，'
                            '当前内容以一条新版本保留（可再次回滚撤销）。'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, true),
                            child: const Text('回滚'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !sheetContext.mounted) return;
                    Navigator.pop(sheetContext); // 先关快照 sheet
                    final ok = await ref
                        .read(characterRepositoryProvider)
                        .rollbackToRevision(r.id!);
                    if (!mounted) return;
                    if (ok) {
                      ToastUtils.showSuccess('已回滚到版本 #${r.id}',
                          context: context);
                      await _load();
                    } else {
                      ToastUtils.showError('回滚失败（角色可能已删除）',
                          context: context);
                    }
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('回滚到该版本'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _snapshotLines(Character c) {
    String? v(String? text) =>
        (text == null || text.trim().isEmpty) ? null : text.trim();
    return [
      '名字：${c.name}',
      if (v(c.gender) != null) '性别：${c.gender}',
      if (c.age != null) '年龄：${c.age}',
      if (v(c.occupation) != null) '职业/身份：${c.occupation}',
      if (v(c.personality) != null) '性格：${c.personality}',
      if (v(c.appearanceFeatures) != null) '外貌：${c.appearanceFeatures}',
      if (v(c.bodyType) != null) '体型：${c.bodyType}',
      if (v(c.clothingStyle) != null) '穿衣风格：${c.clothingStyle}',
      if (v(c.backgroundStory) != null) '背景：${c.backgroundStory}',
      if (v(c.speechStyle) != null) '说话风格：${c.speechStyle}',
      if (v(c.currentState) != null) '近况/当前状态：${c.currentState}',
      if (v(c.facePrompts) != null) '面部提示词：${c.facePrompts}',
      if (v(c.bodyPrompts) != null) '身材提示词：${c.bodyPrompts}',
      if (c.aliases?.isNotEmpty == true) '别名：${c.aliases!.join('、')}',
      if (c.avatarMediaId != null) '头像：已设置（${c.avatarMediaId}）',
    ];
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/character_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/gender_palette.dart';
import '../models/character.dart';
import '../models/novel.dart';
import '../widgets/character/avatar_media.dart';
import '../widgets/character/empty_characters_view.dart';
import 'character_detail_screen.dart';
import 'character_edit_screen.dart';
import 'relationship_graph_screen.dart';

/// 人物卡列表页（2 列网格）
///
/// 展示某本小说下的全部角色，支持性别筛选与姓名搜索。
/// 入口在章节列表页 PopupMenu「人物卡」。
/// 增 / 改 / 删 返回后调用 `ref.invalidate(characterListProvider)` 刷新。
class CharacterListScreen extends ConsumerStatefulWidget {
  final Novel novel;

  const CharacterListScreen({required this.novel, super.key});

  @override
  ConsumerState<CharacterListScreen> createState() =>
      _CharacterListScreenState();
}

class _CharacterListScreenState extends ConsumerState<CharacterListScreen> {
  String _searchQuery = '';
  String? _genderFilter; // null = 全部
  bool _showSearch = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(characterListProvider(widget.novel.url));

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索角色名 / 别名',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              )
            : Text(
                '${widget.novel.title} · 人物卡',
                style: AppTypography.chapterTitle.copyWith(fontSize: 18),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: '人物关系图',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RelationshipGraphScreen(
                  novelUrl: widget.novel.url,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            tooltip: '搜索',
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
        ],
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => _buildErrorView(e, st),
        data: (characters) {
          if (characters.isEmpty) {
            return EmptyCharactersView(onCreateCharacter: _onCreate);
          }
          final filtered = _applyFilter(characters);
          return Column(
            children: [
              _buildFilterBar(),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的角色',
                          style: AppTypography.bodyProse.copyWith(
                            fontSize: 15,
                            color: context.appColors.inkSoft,
                          ),
                        ),
                      )
                    : _buildGrid(filtered),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onCreate,
        tooltip: '新建人物卡',
        child: const Icon(Icons.person_add_alt_outlined),
      ),
    );
  }

  // ─── 筛选与搜索 ─────────────────────────────────────────────

  List<Character> _applyFilter(List<Character> all) {
    var result = all;
    if (_genderFilter != null) {
      result = result
          .where((c) => c.gender == _genderFilter)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((c) {
        if (c.name.toLowerCase().contains(q)) return true;
        return c.aliases?.any((a) => a.toLowerCase().contains(q)) ?? false;
      }).toList();
    }
    return result;
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        children: [
          _filterChip('全部', null),
          _filterChip('男', '男'),
          _filterChip('女', '女'),
          _filterChip('其他', '其他'),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _genderFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _genderFilter = selected ? null : value),
    );
  }

  // ─── 网格 ───────────────────────────────────────────────────

  Widget _buildGrid(List<Character> characters) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: characters.length,
      itemBuilder: (context, index) =>
          _CharacterCard(character: characters[index], onTap: () => _onOpen(characters[index])),
    );
  }

  // ─── 错误态 ─────────────────────────────────────────────────

  Widget _buildErrorView(Object e, StackTrace st) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '加载失败',
            style: AppTypography.bodyProse.copyWith(
              fontSize: 15,
              color: context.appColors.error,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref
                .invalidate(characterListProvider(widget.novel.url)),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // ─── 路由动作 ───────────────────────────────────────────────

  Future<void> _onCreate() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(novel: widget.novel),
      ),
    );
    if (changed == true) {
      ref.invalidate(characterListProvider(widget.novel.url));
    }
  }

  Future<void> _onOpen(Character character) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterDetailScreen(
          character: character,
          novel: widget.novel,
        ),
      ),
    );
    if (changed == true) {
      ref.invalidate(characterListProvider(widget.novel.url));
    }
  }
}

/// 单个人物卡（列表项）
class _CharacterCard extends StatelessWidget {
  final Character character;
  final VoidCallback onTap;

  const _CharacterCard({required this.character, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final genderColor = GenderPalette.of(character.gender);

    final subtitleParts = <String>[
      if (character.gender != null && character.gender!.isNotEmpty)
        character.gender!,
      if (character.age != null) '${character.age}岁',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头像区
            Expanded(
              child: Container(
                color: genderColor.withValues(alpha: 0.18),
                child: AvatarMedia(
                  mediaId: character.avatarMediaId,
                  name: character.name,
                  genderColor: genderColor,
                  borderRadius: 14,
                  fontSize: 48,
                ),
              ),
            ),
            // 信息区
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 15,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      ...subtitleParts,
                      if (character.occupation != null &&
                          character.occupation!.isNotEmpty)
                        character.occupation!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.metaItalic.copyWith(
                      color: colors.inkSoft,
                    ),
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

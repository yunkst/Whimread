/// 游戏设定手动编辑页（游玩页/管理页的查看设定 sheet 进入）
///
/// 可改：标题 / 世界观 / 开场 / 规则 / 参战名单（勾选该小说下的角色卡）/
/// 玩家角色（在参战名单中指定）。**角色卡内容**（性格/近况/说话风格/头像）
/// 属共享角色卡，在角色卡详情/编辑页维护（本页提供入口）。
/// 保存 = repo.update 整行更新 + invalidate 列表；游戏中编辑下一轮生效
/// （场景每次运行从数据库重载角色卡）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart'
    show characterRepositoryProvider, novelRepositoryProvider, textGameRepositoryProvider;
import '../../core/providers/text_game_providers.dart'
    show textGamesProvider;
import '../../models/character.dart';
import '../../models/novel.dart';
import '../../models/text_game.dart';
import '../character_detail_screen.dart';
import '../character_revision_history_screen.dart';
import '../../utils/toast_utils.dart';

class TextGameSettingsEditScreen extends ConsumerStatefulWidget {
  final int gameId;

  const TextGameSettingsEditScreen({super.key, required this.gameId});

  @override
  ConsumerState<TextGameSettingsEditScreen> createState() =>
      _TextGameSettingsEditScreenState();
}

class _TextGameSettingsEditScreenState
    extends ConsumerState<TextGameSettingsEditScreen> {
  final _title = TextEditingController();
  final _worldview = TextEditingController();
  final _opening = TextEditingController();
  final _narrativeStyle = TextEditingController();
  final _contentBoundary = TextEditingController();
  final _worldNotes = TextEditingController();

  int _choicesCount = 3;
  GameImagePolicy _imagePolicy = GameImagePolicy.auto;
  Set<int> _castIds = {};
  int? _playerId;

  Novel? _novel;
  List<Character> _allCharacters = const [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final game =
        await ref.read(textGameRepositoryProvider).getById(widget.gameId);
    if (!mounted) return;
    if (game == null) {
      setState(() {
        _loading = false;
        _error = '游戏不存在或已被删除';
      });
      return;
    }
    final s = game.settings;
    _title.text = game.title;
    _worldview.text = s.worldview;
    _opening.text = s.opening;
    _narrativeStyle.text = s.rules.narrativeStyle;
    _contentBoundary.text = s.rules.contentBoundary;
    _worldNotes.text = s.worldNotes.join('\n');
    _choicesCount = s.rules.choicesCount.clamp(2, 4);
    _imagePolicy = s.rules.imagePolicy;
    _castIds = s.characterIds.toSet();
    _playerId = s.playerCharacterId;

    if (game.sourceNovelId != null) {
      _novel = await ref
          .read(novelRepositoryProvider)
          .getNovelById(game.sourceNovelId!);
    }
    if (!mounted) return;
    if (_novel != null) {
      _allCharacters =
          await ref.read(characterRepositoryProvider).getCharacters(_novel!.url);
      if (!mounted) return;
      // 名单里有但卡已不存在的 id 清理掉；玩家卡缺失时回退第一个参战角色
      _castIds.removeWhere((id) => _allCharacters.every((c) => c.id != id));
      if (_playerId != null && _castIds.contains(_playerId) == false) {
        _playerId = null;
      }
    } else {
      _castIds.clear();
      _playerId = null;
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _title.dispose();
    _worldview.dispose();
    _opening.dispose();
    _narrativeStyle.dispose();
    _contentBoundary.dispose();
    _worldNotes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ToastUtils.showError('游戏标题不能为空');
      return;
    }
    if (_playerId == null) {
      ToastUtils.showError('请指定玩家角色');
      return;
    }

    final game = await ref.read(textGameRepositoryProvider).getById(widget.gameId);
    if (game == null) {
      ToastUtils.showError('游戏已不存在');
      return;
    }

    // 玩家角色必须总在参战名单中
    final castIds = {..._castIds, _playerId!};
    await ref.read(textGameRepositoryProvider).update(game.copyWith(
          title: title,
          settings: game.settings.copyWith(
            worldview: _worldview.text.trim(),
            opening: _opening.text.trim(),
            worldNotes: _worldNotes.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
            characterIds: castIds.toList(),
            playerCharacterId: _playerId,
            rules: GameRules(
              narrativeStyle: _narrativeStyle.text.trim(),
              contentBoundary: _contentBoundary.text.trim(),
              choicesCount: _choicesCount,
              imagePolicy: _imagePolicy,
            ),
          ),
        ));
    if (!mounted) return;
    ref.invalidate(textGamesProvider);
    ToastUtils.showSuccess('设定已保存，游戏中下一轮生效');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑设定'),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(context, '基本信息'),
                      _field(_title, label: '游戏标题'),
                      _field(_worldview,
                          label: '世界观背景（留空 = 用绑定小说的背景设定）',
                          maxLines: 5),
                      _field(_opening, label: '开场情境', maxLines: 3),
                      const SizedBox(height: 20),
                      _sectionLabel(context, '游戏规则'),
                      _field(_narrativeStyle, label: '叙事风格', maxLines: 2),
                      _field(_contentBoundary, label: '内容边界', maxLines: 2),
                      Row(
                        children: [
                          Text('每回合选项数', style: theme.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 2, label: Text('2')),
                              ButtonSegment(value: 3, label: Text('3')),
                              ButtonSegment(value: 4, label: Text('4')),
                            ],
                            selected: {_choicesCount},
                            onSelectionChanged: (v) =>
                                setState(() => _choicesCount = v.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text('场景插图', style: theme.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                          SegmentedButton<GameImagePolicy>(
                            segments: const [
                              ButtonSegment(
                                  value: GameImagePolicy.auto,
                                  label: Text('自动配图')),
                              ButtonSegment(
                                  value: GameImagePolicy.manual,
                                  label: Text('手动生成')),
                            ],
                            selected: {_imagePolicy},
                            onSelectionChanged: (v) =>
                                setState(() => _imagePolicy = v.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel(context, '世界与剧情线'),
                      _field(_worldNotes,
                          label: '任务/势力动向/未解悬念（每行一条，游戏内 AI 也会更新）',
                          maxLines: 4),
                      const SizedBox(height: 20),
                      _sectionLabel(context,
                          '参战角色（角色卡内容在角色卡页维护，点行进详情）'),
                      if (_novel == null)
                        Text('绑定的小说已不存在，无法管理参战名单',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error)),
                      ..._allCharacters.map(_castTile),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _castTile(Character c) {
    final theme = Theme.of(context);
    final id = c.id;
    if (id == null) return const SizedBox.shrink();
    final inCast = _castIds.contains(id);
    final isPlayer = _playerId == id;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Checkbox(
        value: inCast,
        onChanged: (v) => setState(() {
          if (v == true) {
            _castIds.add(id);
          } else {
            _castIds.remove(id);
            if (_playerId == id) _playerId = null;
          }
        }),
      ),
      title: Text(
        '${c.name}${isPlayer ? ' · 玩家' : ''}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isPlayer ? FontWeight.w600 : null,
        ),
      ),
      subtitle: (c.personality?.isNotEmpty == true)
          ? Text(c.personality!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 玩家角色指定：仅在参战名单内可选
          if (inCast)
            TextButton(
              onPressed: () => setState(() => _playerId = id),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor:
                    isPlayer ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
              child: Text(isPlayer ? '玩家' : '设为玩家'),
            ),
          IconButton(
            tooltip: '版本历史',
            icon: const Icon(Icons.history, size: 18),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CharacterRevisionHistoryScreen(characterId: id),
            )),
          ),
        ],
      ),
      onTap: () {
        final novel = _novel;
        if (novel == null) return;
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => CharacterDetailScreen(character: c, novel: novel),
            ))
            .then((_) => _load()); // 角色卡内容可能已改，回来刷新
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

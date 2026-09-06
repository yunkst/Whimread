import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/character_providers.dart';
import '../core/providers/database_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/gender_palette.dart';
import '../models/character.dart';
import '../models/novel.dart';
import '../services/logger_service.dart';
import '../utils/error_helper.dart';
import '../utils/toast_utils.dart';
import '../widgets/character/avatar_media.dart';
import '../widgets/common/confirm_dialog.dart';
import '../widgets/media/media_view.dart';
import 'character_edit_screen.dart';

/// 人物卡详情页
///
/// 展示单个角色的全部字段（分区卡片），支持 AppBar 编辑 / 删除。
/// 编辑返回后会重新读取最新角色数据；删除成功后返回列表。
class CharacterDetailScreen extends ConsumerStatefulWidget {
  final Character character;
  final Novel novel;

  const CharacterDetailScreen({
    required this.character,
    required this.novel,
    super.key,
  });

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState
    extends ConsumerState<CharacterDetailScreen> {
  late Character _character;

  @override
  void initState() {
    super.initState();
    _character = widget.character;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _character.name,
          style: AppTypography.chapterTitle.copyWith(fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: _onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.error),
            tooltip: '删除',
            onPressed: _onDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(colors),
            const SizedBox(height: 16),
            _buildTitleBlock(),
            const SizedBox(height: 20),
            _buildInfoCard('性格', Icons.psychology_outlined,
                _character.personality),
            const SizedBox(height: 12),
            _buildAppearanceCard(),
            const SizedBox(height: 12),
            _buildInfoCard('背景', Icons.history_edu_outlined,
                _character.backgroundStory),
            const SizedBox(height: 12),
            _buildAiPromptsCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── 头部 ───────────────────────────────────────────────────

  Widget _buildHero(AppColors colors) {
    final mediaId = _character.avatarMediaId;
    final genderColor = GenderPalette.of(_character.gender);
    final hasMedia = mediaId != null && mediaId.isNotEmpty;
    return Center(
      child: Container(
        width: 180,
        height: 240,
        decoration: BoxDecoration(
          color: genderColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: genderColor.withValues(alpha: 0.5), width: 2),
        ),
        child: AvatarMedia(
          mediaId: mediaId,
          name: _character.name,
          genderColor: genderColor,
          borderRadius: 14,
          fontSize: 72,
          onTap: hasMedia ? () => _showFullScreenAvatar(mediaId) : null,
        ),
      ),
    );
  }

  Widget _buildTitleBlock() {
    final c = _character;
    final subtitleParts = <String>[
      if (c.gender != null && c.gender!.isNotEmpty) c.gender!,
      if (c.age != null) '${c.age}岁',
      if (c.occupation != null && c.occupation!.isNotEmpty) c.occupation!,
    ];

    return Column(
      children: [
        Text(
          c.name,
          textAlign: TextAlign.center,
          style: AppTypography.chapterTitle.copyWith(
            fontSize: 22,
            color: context.appColors.ink,
          ),
        ),
        if (subtitleParts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitleParts.join(' · '),
            style: AppTypography.metaItalic.copyWith(
              color: context.appColors.inkSoft,
            ),
          ),
        ],
        if (c.aliases != null && c.aliases!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: c.aliases!
                .map((a) => Chip(
                      label: Text(a),
                      padding: EdgeInsets.zero,
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  // ─── 分区卡片 ───────────────────────────────────────────────

  Widget _buildInfoCard(String title, IconData icon, String? content) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: context.appColors.agentAccent),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: AppTypography.novelTitle.copyWith(
                    fontSize: 15,
                    color: context.appColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              (content == null || content.isEmpty)
                  ? '—'
                  : content,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 14, height: 1.6, color: context.appColors.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard() {
    final c = _character;
    final rows = <_AppearanceRow>[
      _AppearanceRow('外貌特征', c.appearanceFeatures),
      _AppearanceRow('身材体型', c.bodyType),
      _AppearanceRow('穿衣风格', c.clothingStyle),
    ];
    final hasAny = rows.any((r) => r.value != null && r.value!.isNotEmpty);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.face_retouching_natural_outlined,
                    size: 18, color: context.appColors.agentAccent),
                const SizedBox(width: 6),
                Text(
                  '外貌',
                  style: AppTypography.novelTitle.copyWith(
                    fontSize: 15,
                    color: context.appColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!hasAny)
              Text('—', style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 14, height: 1.6, color: context.appColors.ink))
            else
              ...rows.map((r) => _appearanceRow(r)),
          ],
        ),
      ),
    );
  }

  Widget _appearanceRow(_AppearanceRow r) {
    final empty = r.value == null || r.value!.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              r.label,
              style: AppTypography.metaItalic.copyWith(
                    color: context.appColors.inkSoft,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              empty ? '—' : r.value!,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 14, height: 1.6, color: context.appColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiPromptsCard() {
    final c = _character;
    final hasFace = c.facePrompts != null && c.facePrompts!.isNotEmpty;
    final hasBody = c.bodyPrompts != null && c.bodyPrompts!.isNotEmpty;
    if (!hasFace && !hasBody) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 18, color: context.appColors.info),
                const SizedBox(width: 6),
                Text('AI 生图提示词',
                    style: AppTypography.novelTitle.copyWith(
                      fontSize: 15,
                      color: context.appColors.ink,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            if (hasFace)
              _promptLine('面部', c.facePrompts),
            if (hasFace && hasBody) const SizedBox(height: 6),
            if (hasBody) _promptLine('身材', c.bodyPrompts),
          ],
        ),
      ),
    );
  }

  Widget _promptLine(String label, String? value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(label,
              style: AppTypography.metaItalic.copyWith(
                    color: context.appColors.inkSoft,
                  )),
        ),
        Expanded(
          child: Text(value ?? '',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 14, height: 1.6, color: context.appColors.ink)),
        ),
      ],
    );
  }

  // ─── 辅助 ───────────────────────────────────────────────────

  void _showFullScreenAvatar(String mediaId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullScreenAvatar(mediaId: mediaId),
      ),
    );
  }

  // ─── 编辑 / 删除 ────────────────────────────────────────────

  Future<void> _onEdit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(
          novel: widget.novel,
          existing: _character,
        ),
      ),
    );
    if (changed == true) {
      // 重新读取最新数据
      try {
        final repo = ref.read(characterRepositoryProvider);
        final latest =
            _character.id == null ? null : await repo.getCharacter(_character.id!);
        if (latest != null && mounted) {
          setState(() => _character = latest);
        } else if (mounted) {
          // 角色已被删除（在编辑页里删了？不会发生），回退
          Navigator.pop(context, true);
        }
      } catch (_) {
        // 静默：列表刷新由返回值触发
      }
    }
  }

  Future<void> _onDelete() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除人物卡',
      message: '确定要删除「${_character.name}」吗？此操作不可撤销。',
      confirmText: '删除',
      isDangerous: true,
    );
    if (confirmed != true) return;

    final id = _character.id;
    if (id == null) {
      ToastUtils.showError('角色尚未保存，无法删除', context: context);
      return;
    }
    try {
      final repo = ref.read(characterRepositoryProvider);
      await repo.deleteCharacter(id);
      ref.invalidate(characterListProvider(widget.novel.url));
      if (!mounted) return;
      ToastUtils.showSuccess('已删除', context: context);
      Navigator.pop(context, true);
    } catch (e, stackTrace) {
      if (!mounted) return;
      ErrorHelper.showErrorWithLog(
        context,
        '删除人物卡失败',
        error: e,
        stackTrace: stackTrace,
        category: LogCategory.character,
        tags: ['character', 'delete', 'failed'],
      );
    }
  }
}

class _AppearanceRow {
  final String label;
  final String? value;
  const _AppearanceRow(this.label, this.value);
}

/// 全屏查看头像媒体（图片缩放 / 视频循环播放，点击关闭）
class _FullScreenAvatar extends StatelessWidget {
  final String mediaId;
  const _FullScreenAvatar({required this.mediaId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: MediaView(mediaId: mediaId, fullscreen: true),
        ),
      ),
    );
  }
}

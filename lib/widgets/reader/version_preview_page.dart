import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/chapter_mutation_provider.dart';
import '../../core/providers/reader_settings_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/chapter_version.dart';
import '../../utils/toast_utils.dart';

/// 历史版本内容全屏预览页
///
/// 取代原本嵌在 BottomSheet 上的 AlertDialog，让章节历史内容拥有与
/// 阅读器正文一致的排版（衬线 / 字号 / 行高 / 字间距 / 段落间距），
/// 并提供全文滚动、可选中复制、底部还原入口。
///
/// 还原成功后通过 [onRestored] 回调通知调用方（VersionHistorySheet），
/// 由调用方负责关闭面板并刷新阅读器。
class VersionPreviewPage extends ConsumerStatefulWidget {
  final ChapterVersion version;
  final String chapterUrl;
  final String novelUrl;
  final VoidCallback onRestored;

  const VersionPreviewPage({
    super.key,
    required this.version,
    required this.chapterUrl,
    required this.novelUrl,
    required this.onRestored,
  });

  /// 全屏推入预览页（iOS 风格 fullscreenDialog）
  static Future<void> push(
    BuildContext context, {
    required ChapterVersion version,
    required String chapterUrl,
    required String novelUrl,
    required VoidCallback onRestored,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VersionPreviewPage(
          version: version,
          chapterUrl: chapterUrl,
          novelUrl: novelUrl,
          onRestored: onRestored,
        ),
      ),
    );
  }

  @override
  ConsumerState<VersionPreviewPage> createState() =>
      _VersionPreviewPageState();
}

class _VersionPreviewPageState extends ConsumerState<VersionPreviewPage> {
  /// 渲染前按 `\n` 拆段，与阅读器正文 [ReaderContentView] / [ParagraphWidget]
  /// 保持完全一致的拆分策略。
  List<String> get _paragraphs {
    return widget.version.content
        .split('\n')
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // 跟随阅读器设置：字号 / 亮度。未加载完成时使用阅读器默认 18 / 1.0。
    final settingsAsync = ref.watch(readerSettingsStateNotifierProvider);
    final fontSize = settingsAsync.value?.fontSize ?? 18.0;
    final textBrightness = settingsAsync.value?.textBrightness ?? 1.0;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sourceColor = _sourceColor(context, widget.version.source);
    final paragraphs = _paragraphs;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.version.sourceIcon, size: 18, color: sourceColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${widget.version.sourceLabel} · ${widget.version.formattedTime}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: paragraphs.isEmpty
          ? Center(
              child: Text(
                '（该版本内容为空）',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: paragraphs.length,
              itemBuilder: (context, index) {
                return _buildParagraph(
                  paragraphs[index],
                  fontSize: fontSize,
                  textBrightness: textBrightness,
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${widget.version.contentLength} 字 · 全文可滚动',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('还原此版本'),
                onPressed: _restoreVersion,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 与阅读器 [ParagraphWidget._buildReadableText] 完全一致的段落排版
  /// （垂直 padding 6 / 水平 padding 8；bodyProse 衬线 + 行高 2.0 +
  /// letterSpacing 0.2）。仅将 `Text.rich` 替换为 `SelectableText.rich` 以
  /// 支持长按选中复制（视觉无差异）。
  Widget _buildParagraph(String text,
      {required double fontSize, required double textBrightness}) {
    final theme = Theme.of(context);
    final baseColor =
        theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
    final effectiveColor = baseColor.withValues(alpha: textBrightness);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      child: SelectableText.rich(
        TextSpan(
          text: text.trim(),
          style: AppTypography.bodyProse.copyWith(
            fontSize: fontSize,
            color: effectiveColor,
          ),
        ),
      ),
    );
  }

  Color? _sourceColor(BuildContext context, String source) {
    final appColors = context.appColors;
    switch (source) {
      case 'edit':
        return appColors.info;
      case 'ai_rewrite':
        return appColors.agentAccent;
      case 'manual_snapshot':
        return appColors.success;
      case 'restore':
        return appColors.warning;
      default:
        return Theme.of(context).colorScheme.outlineVariant;
    }
  }

  /// 还原到当前预览的版本。
  ///
  /// 时序：确认框 → 写库 → toast → 关闭预览页 → 回调 onRestored 由调用方
  /// （VersionHistorySheet）关闭面板并通知阅读器刷新。本页只负责自身的
  /// 出栈，跨页的状态收口交给调用方处理。
  Future<void> _restoreVersion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.restore, color: ctx.appColors.warning),
          const SizedBox(width: 8),
          const Text('还原到历史版本'),
        ]),
        content: Text(
          '将当前内容替换为「${widget.version.sourceLabel}」'
          '（${widget.version.formattedTime}，'
          '${widget.version.formattedLength}）的版本？\n\n'
          '当前内容将自动保存为历史版本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('还原'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(chapterMutationProvider.notifier).updateChapterContent(
            widget.chapterUrl,
            widget.version.content,
            source: 'restore',
            novelUrl: widget.novelUrl,
          );
      if (mounted) {
        ToastUtils.showSuccess('已还原到历史版本', context: context);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('还原失败: $e', context: context);
      }
      return;
    }

    // 写库成功：出栈预览页并通知调用方收尾（关面板 + 刷新阅读器）。
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    widget.onRestored();
  }
}

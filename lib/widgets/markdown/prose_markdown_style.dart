import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 散文式 Markdown 预览样式
///
/// 统一大纲 / 背景设定两页的 `MarkdownStyleSheet`。正文走衬线书卷气
/// ([AppTypography.bodyProse])，颜色走阅读墨色（[AppColors.ink] / [AppColors.inkSoft]）。
///
/// 注意：[AgentMessageBubble] 的样式与此不同（h1 20px、code 用 primary 色），
/// 不在此统一，各自维护。
MarkdownStyleSheet buildProseMarkdownStyle(BuildContext context) {
  final theme = Theme.of(context);
  final colors = context.appColors;
  return MarkdownStyleSheet(
    p: AppTypography.bodyProse.copyWith(
      fontSize: 15,
      color: colors.ink,
    ),
    h1: AppTypography.chapterTitle.copyWith(
      fontSize: 22,
      color: colors.ink,
    ),
    h2: AppTypography.chapterTitle.copyWith(
      fontSize: 19,
      color: colors.ink,
    ),
    h3: AppTypography.novelTitle.copyWith(
      fontSize: 17,
      color: colors.ink,
    ),
    h4: AppTypography.novelTitle.copyWith(
      fontSize: 15,
      color: colors.ink,
    ),
    strong: AppTypography.bodyProse.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.bold,
      color: colors.ink,
    ),
    em: AppTypography.bodyProse.copyWith(
      fontSize: 15,
      fontStyle: FontStyle.italic,
      color: colors.ink,
    ),
    listBullet: AppTypography.bodyProse.copyWith(
      fontSize: 15,
      color: colors.inkSoft,
    ),
    code: AppTypography.bodyProse.copyWith(
      fontSize: 13,
      fontFamily: 'monospace',
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquote: AppTypography.bodyProse.copyWith(
      fontSize: 15,
      fontStyle: FontStyle.italic,
      color: colors.inkSoft,
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: theme.colorScheme.primary,
          width: 4,
        ),
      ),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: colors.divider,
          width: 1,
        ),
      ),
    ),
  );
}

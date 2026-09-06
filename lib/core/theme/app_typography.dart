/// 书馆美学 · 字体令牌
///
/// 项目内嵌 Noto Serif SC / Noto Sans SC（已子集化打包于 assets/fonts/），
/// 跨平台衬线/无衬线质感稳定，与 GitHub Pages 介绍页同源。
/// - 标题/书名/章名用 Noto Serif SC（书卷气）
/// - UI 正文用 Noto Sans SC
/// fallback 链保留，兜底极少数子集未覆盖的生僻字（人名/古字等）。
library;

import 'package:flutter/material.dart';

/// 字体族常量
class AppTypography {
  AppTypography._();

  /// 衬线 · Noto Serif SC · 用于书名/章名/书架标题（书卷气）
  static const String serif = 'NotoSerifSC';

  /// 衬线 fallback 链（跨平台系统宋体）
  static const List<String> serifFallback = [
    'Songti SC', // macOS / iOS
    'STSong',
    'SimSun', // Windows
    'Noto Serif CJK SC', // Android / Linux
    'Noto Serif SC',
    'Source Han Serif SC',
  ];

  /// 无衬线 · Noto Sans SC · UI 正文默认
  static const String sans = 'NotoSansSC';

  /// 无衬线 fallback 链
  static const List<String> sansFallback = [
    'PingFang SC', // macOS / iOS
    'Microsoft YaHei', // Windows
    'Noto Sans CJK SC', // Android / Linux
    'Noto Sans SC',
    'Source Han Sans SC',
  ];

  // ─── 预设 TextStyle（供书架等重写页面直接复用）──────────────────

  /// 书架顶部标题「我的书架」
  static const TextStyle shelfTitle = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  /// 品牌英文副标题（斜体装饰）
  static const TextStyle brandSubtitle = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontStyle: FontStyle.italic,
    fontSize: 11,
    letterSpacing: 0.3,
  );

  /// 书名（封面下方 / 卡片标题）
  static const TextStyle novelTitle = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// 章节名（阅读器内）
  static const TextStyle chapterTitle = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  /// 计数 / 元信息斜体（如「共 6 本」）
  static const TextStyle metaItalic = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontStyle: FontStyle.italic,
    fontSize: 12,
  );

  /// 阅读正文（阅读器段落）
  static const TextStyle bodyProse = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: 17,
    height: 2.0,
    letterSpacing: 0.2,
  );

  /// 引导页大标题 · 衬线醒目款
  /// 用于 onboarding 各步骤的主标题，比 shelfTitle 更大、更有仪式感。
  static const TextStyle onboardingTitle = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.3,
  );
}

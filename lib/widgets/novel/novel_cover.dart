/// 程序化小说封面
///
/// 把 [Novel] 渲染成一张「书脊风」封面：
/// - 优先用 [Novel.coverUrl] 真实封面图（Image.network，加载失败/为空回退程序化）
/// - 否则由书名哈希选 8 套色板之一，首字/竖排程序化生成
/// - 确定性：同一本书每次生成结果一致（title.hashCode % 8）
///
/// 零网络依赖、零字体依赖，纯 Flutter 绘制。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../models/novel.dart';
import '../media/media_view.dart';

/// 小说封面
///
/// [novel] 小说数据；[size] 封面尺寸；[isReading] 是否显示「在读」标记；
/// [isOriginal] 是否显示「原」印章（默认按 url.startsWith('custom://') 判定）。
class NovelCover extends StatefulWidget {
  const NovelCover({
    super.key,
    required this.novel,
    this.width = 120,
    this.isReading = false,
    bool? isOriginal,
  }) : isOriginal = isOriginal ?? false;

  final Novel novel;
  final double width;
  final bool isReading;

  /// 是否原创小说（显示印章）。默认按 url 判定，可外部覆盖。
  final bool isOriginal;

  @override
  State<NovelCover> createState() => _NovelCoverState();
}

class _NovelCoverState extends State<NovelCover> {
  /// 真实封面是否加载失败 → 回退程序化
  bool _useFallback = false;

  bool get _hasCoverUrl {
    final url = widget.novel.coverUrl;
    return url != null && url.trim().isNotEmpty && !_useFallback;
  }

  @override
  Widget build(BuildContext context) {
    // AI 封面命中：走 MediaView 渲染（图片/视频），纯图不叠加任何程序化装饰。
    // boxFit=cover 保证保持原比例裁切，不拉伸变形（与 AvatarMedia 一致）。
    // 加载/失败/pending 由 MediaView 自带状态机承担，NovelCover 不再自管 fallback。
    final coverMediaId = widget.novel.coverMediaId;
    if (coverMediaId != null && coverMediaId.isNotEmpty) {
      final width = widget.width;
      final height = width * 4 / 3;
      return SizedBox(
        width: width,
        height: height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 14,
                offset: Offset(-2, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: MediaView(
              mediaId: coverMediaId,
              boxFit: BoxFit.cover,
            ),
          ),
        ),
      );
    }

    final width = widget.width;
    final height = width * 4 / 3;

    final content = _hasCoverUrl
        ? Image.network(
            widget.novel.coverUrl!,
            fit: BoxFit.cover,
            width: width,
            height: height,
            errorBuilder: (_, __, ___) {
              // 加载失败，下一帧切到程序化封面
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _useFallback = true);
              });
              // 本帧先画底色占位，避免空白闪烁
              return CustomPaint(
                size: Size.infinite,
                painter: _ProgrammaticCoverPainter(
                  title: widget.novel.title,
                  palette: _CoverPalette.pick(widget.novel.title),
                ),
              );
            },
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              // 加载中显示底色
              return Container(color: _CoverPalette.pick(widget.novel.title).solid);
            },
          )
        : CustomPaint(
            size: Size(width, height),
            painter: _ProgrammaticCoverPainter(
              title: widget.novel.title,
              palette: _CoverPalette.pick(widget.novel.title),
            ),
          );

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 封面主体（带圆角 + 书脊高光）
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 14,
                  offset: Offset(-2, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: content,
            ),
          ),
          // 书脊高光（左侧亮线，模拟纸张折弯反光）
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
                ),
              ),
            ),
          ),
          // 内框装饰线
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(width * 0.08),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: const Color(0x2EFFFFFF),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
          // 在读标记（左上琥珀点）
          if (widget.isReading) const _ReadingDot(),
          // 原创印章（右上）
          if (widget.isOriginal)
            const Positioned(
              top: 8,
              right: 8,
              child: _SealStamp(text: '原'),
            ),
        ],
      ),
    );
  }
}

/// 在读标记 · 琥珀光点
class _ReadingDot extends StatelessWidget {
  const _ReadingDot();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 9,
      left: 9,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFF0B870),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x33F0B870), blurRadius: 8, spreadRadius: 2),
          ],
        ),
      ),
    );
  }
}

/// 印章 · 右上角小标
class _SealStamp extends StatelessWidget {
  const _SealStamp({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x66FFFFFF), width: 0.8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xD9FFFFFF),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ─── 程序化封面绘制 ──────────────────────────────────────────────

/// 封面色板：8 套，由 title.hashCode % 8 决定。
/// 色板本身是深色渐变，亮/暗主题通用（深色封面在白底上同样成立）。
class _CoverPalette {
  const _CoverPalette(this.begin, this.end, this.solid);

  final Color begin;
  final Color end;
  final Color solid;

  /// 根据 Dart String.hashCode 选色板（确定性）
  static _CoverPalette pick(String title) {
    final idx = title.hashCode.abs() % 8;
    return _palettes[idx];
  }

  static const _palettes = <_CoverPalette>[
    _CoverPalette(Color(0xFF0E1F22), Color(0xFF2E5C4E), Color(0xFF1A2A2A)), // 青墨
    _CoverPalette(Color(0xFF0A1428), Color(0xFF244B8A), Color(0xFF142444)), // 墨蓝
    _CoverPalette(Color(0xFF1F0A0A), Color(0xFF7A2424), Color(0xFF3A1414)), // 暗红
    _CoverPalette(Color(0xFF140A1F), Color(0xFF4A2E6E), Color(0xFF2A1A3A)), // 深紫
    _CoverPalette(Color(0xFF1F160A), Color(0xFF8A6624), Color(0xFF3A2A14)), // 金棕
    _CoverPalette(Color(0xFF0F1620), Color(0xFF3E5474), Color(0xFF1F2A3A)), // 冷灰
    _CoverPalette(Color(0xFF0E1A0E), Color(0xFF2E5C3A), Color(0xFF1A2E1A)), // 苔绿
    _CoverPalette(Color(0xFF1A0E0E), Color(0xFF8A2E2E), Color(0xFF3A1818)), // 朱砂
  ];
}

/// 程序化封面画笔
class _ProgrammaticCoverPainter extends CustomPainter {
  _ProgrammaticCoverPainter({
    required this.title,
    required this.palette,
  });

  final String title;
  final _CoverPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景渐变
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [palette.begin, palette.solid, palette.end],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // 主字（首字或竖排）—— 用文字绘制
    final glyphs = _mainGlyphs(title);
    final tp = _buildTextPainter(size, glyphs);
    final offset = Offset(
      (size.width - tp.width) / 2,
      (size.height - tp.height) / 2,
    );
    tp.paint(canvas, offset);
  }

  /// 取主字：≤4 字竖排，否则首字放大
  List<String> _mainGlyphs(String t) {
    String stripPrefix(String s) =>
        s.replaceFirst(RegExp(r'^第[一二三四五六七八九十百千零\d]+章?\s*'), '');
    String stripMeta(String s) => s.replaceAll(RegExp(r'[第章卷]'), '');

    String toChars(String s) =>
        String.fromCharCodes(s.runes); // 代理对友好

    final cleaned = stripMeta(stripPrefix(t));
    final chars = toChars(cleaned).split('');
    if (chars.length <= 4 && chars.length > 1) return chars;
    return [
      chars.isNotEmpty
          ? chars.first
          : (toChars(t).isNotEmpty ? toChars(t).substring(0, 1) : '?'),
    ];
  }

  TextPainter _buildTextPainter(Size size, List<String> glyphs) {
    final isSingle = glyphs.length == 1;
    final fontSize = isSingle ? size.width * 0.36 : size.width * 0.18;
    final text = isSingle ? glyphs.first : glyphs.join('\n');

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppTypography.serif,
          fontFamilyFallback: AppTypography.serifFallback,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xF5FFFFFF),
          height: isSingle ? 1.0 : 1.25,
          letterSpacing: isSingle ? 0 : 2,
          shadows: const [
            Shadow(color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.width);
    return tp;
  }

  @override
  bool shouldRepaint(covariant _ProgrammaticCoverPainter old) =>
      old.title != title || old.palette != palette;
}

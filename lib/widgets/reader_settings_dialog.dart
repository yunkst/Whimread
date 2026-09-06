import 'package:flutter/material.dart';

/// ReaderSettingsDialog - 阅读设置对话框
///
/// 合并以下设置项：
/// - 字体大小
/// - 文字亮度
/// - 滚动速度
///
/// 设计要点：
/// - 三个 Slider 实时预览（对话框内示例文字 + 数值）
/// - 点击"确定"统一应用三项更改
/// - 点击"取消"放弃所有更改
/// - 点击"重置"将临时状态恢复为默认值（仍需点"确定"才生效）
class ReaderSettingsDialog extends StatefulWidget {
  final double initialFontSize;
  final double initialTextBrightness;
  final double initialScrollSpeed;

  /// 用户点击"确定"时回调，三个值一起返回
  final void Function({
    required double fontSize,
    required double textBrightness,
    required double scrollSpeed,
  }) onConfirm;

  const ReaderSettingsDialog({
    super.key,
    required this.initialFontSize,
    required this.initialTextBrightness,
    required this.initialScrollSpeed,
    required this.onConfirm,
  });

  @override
  State<ReaderSettingsDialog> createState() => _ReaderSettingsDialogState();
}

class _ReaderSettingsDialogState extends State<ReaderSettingsDialog> {
  late double _fontSize;
  late double _textBrightness;
  late double _scrollSpeed;

  static const double _defaultFontSize = 18.0;
  static const double _defaultTextBrightness = 1.0;
  static const double _defaultScrollSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialFontSize;
    _textBrightness = widget.initialTextBrightness;
    _scrollSpeed = widget.initialScrollSpeed;
  }

  void _resetToDefaults() {
    setState(() {
      _fontSize = _defaultFontSize;
      _textBrightness = _defaultTextBrightness;
      _scrollSpeed = _defaultScrollSpeed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).textTheme.bodyLarge?.color ??
        Theme.of(context).colorScheme.onSurface;
    final previewColor = baseColor.withValues(alpha: _textBrightness);
    final variantColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return AlertDialog(
      title: const Text('阅读设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ============ 字体大小 ============
            const _SectionLabel('字体大小'),
            const SizedBox(height: 8),
            // 实时预览（应用当前字号和亮度）
            Center(
              child: Text(
                '示例文字',
                style: TextStyle(
                  fontSize: _fontSize,
                  color: previewColor,
                ),
              ),
            ),
            Slider(
              value: _fontSize,
              min: 12,
              max: 32,
              divisions: 20,
              label: _fontSize.round().toString(),
              onChanged: (v) => setState(() => _fontSize = v),
            ),
            const Divider(height: 24),

            // ============ 文字亮度 ============
            const _SectionLabel('文字亮度'),
            const SizedBox(height: 8),
            // 实时预览（应用当前亮度和字号）
            Center(
              child: Text(
                '示例文字 - ${(_textBrightness * 100).round()}%',
                style: TextStyle(
                  fontSize: 18,
                  color: previewColor,
                ),
              ),
            ),
            Slider(
              value: _textBrightness,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              label: '${(_textBrightness * 100).round()}%',
              onChanged: (v) => setState(() => _textBrightness = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('最暗', style: TextStyle(color: variantColor, fontSize: 12)),
                Text('最亮', style: TextStyle(color: variantColor, fontSize: 12)),
              ],
            ),
            const Divider(height: 24),

            // ============ 滚动速度 ============
            const _SectionLabel('滚动速度'),
            const SizedBox(height: 8),
            Text(
              '当前速度: ${_scrollSpeed.toStringAsFixed(1)}x',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Slider(
              value: _scrollSpeed,
              min: 0.1,
              max: 5.0,
              divisions: 49,
              label: '${_scrollSpeed.toStringAsFixed(1)}x',
              onChanged: (v) => setState(() => _scrollSpeed = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('慢 (0.1x)',
                    style: TextStyle(color: variantColor, fontSize: 12)),
                Text('快 (5.0x)',
                    style: TextStyle(color: variantColor, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _resetToDefaults,
          child: const Text('重置'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfirm(
              fontSize: _fontSize,
              textBrightness: _textBrightness,
              scrollSpeed: _scrollSpeed,
            );
            Navigator.pop(context);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 内部小部件：分区标题
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

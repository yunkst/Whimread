/// GitHub Star 引导弹框。
///
/// 两按钮 + 真诚文案：
/// - 主按钮「⭐ 去 GitHub 点 Star」→ pop(true)，调用方负责 launchUrl
/// - 「关闭」→ pop(false)，调用方负责写冷却期
///
/// 仿 [CrashReportDialog] 结构（AlertDialog + icon + content + actions），
/// 但内容更轻量（无 SelectableText / 无 Scrollbar）。
library;

import 'package:flutter/material.dart';

class StarPromptDialog extends StatelessWidget {
  const StarPromptDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      icon: Icon(Icons.star_outline, color: cs.primary, size: 40),
      title: const Text('喜欢「随心阅读」？'),
      content: const Text(
        '这是一个完全开源、免费、无广告的小说阅读 App。\n\n'
        '如果它对你有帮助，能不能顺手去 GitHub 点个 ⭐ Star？\n\n'
        'Star 对独立开发者意义重大——它能让更多人发现这个项目，'
        '也是支持我继续维护和更新的最大动力。只需点一下，几秒钟就好。',
        style: TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.star, size: 18),
          label: const Text('去 GitHub 点 Star'),
        ),
      ],
    );
  }
}

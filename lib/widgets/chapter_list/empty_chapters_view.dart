import 'package:flutter/material.dart';
import '../../models/novel.dart';
import '../empty_states/empty_state_view.dart';

/// 空章节状态视图组件
/// 当章节列表为空时显示，提供创建章节或从源网站获取章节的操作。
///
/// 统一改用 [EmptyStateView] 作为主视图；非自定义小说时
/// 在主 CTA 下方追加「从源网站获取章节」次按钮。
class EmptyChaptersView extends StatelessWidget {
  final Novel novel;
  final VoidCallback onCreateChapter;
  final VoidCallback onLoadFromSource;

  const EmptyChaptersView({
    required this.novel,
    required this.onCreateChapter,
    required this.onLoadFromSource,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isCustomNovel = novel.url.startsWith('custom://');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        EmptyStateView(
          icon: Icons.menu_book,
          title: '还没有章节',
          subtitle: isCustomNovel
              ? '点击下方按钮创建第一个章节'
              : '你可以从源网站获取章节，或创建自己的章节',
          actionText: '新建章节',
          onAction: onCreateChapter,
        ),
        if (!isCustomNovel) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onLoadFromSource,
            icon: const Icon(Icons.refresh),
            label: const Text('从源网站获取章节'),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'empty_state_view.dart';

/// 书架空状态提示组件
///
/// 当书架中没有任何小说时显示空状态提示。
class EmptyBookshelfView extends StatelessWidget {
  const EmptyBookshelfView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.library_books_outlined,
      title: '书架是空的',
      subtitle: '通过浏览器添加小说到书架',
    );
  }
}

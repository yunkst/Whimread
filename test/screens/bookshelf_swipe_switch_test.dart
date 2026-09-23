import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/providers/bookshelf_providers.dart';
import 'package:novel_app/core/theme/app_colors.dart';
import 'package:novel_app/models/bookshelf.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/screens/bookshelf_screen.dart';
import 'package:novel_app/widgets/empty_states/empty_bookshelf.dart';

/// 测试用当前书架 Notifier：不走 SharedPreferences 持久化，仅持有内存状态
class _FakeCurrentBookshelf extends CurrentBookshelf {
  @override
  Bookshelf build() => Bookshelf.systemShelves.first;

  @override
  void setBookshelf(Bookshelf shelf) => state = shelf;
}

/// 站点 URL 抽干为空字符串，避免 Notifier 内部异步加载触发额外的
/// 数据库/Mock 依赖；`_loadScripts` 在测试环境失败会被自身捕获，
/// 最终 `state` 退化为 loading/error，`valueOrNull` 仍为 null，
/// 对「刷新网站书架」按钮可见性无影响（始终隐藏）。
void main() {
  const siteShelf = Bookshelf(
    kind: BookshelfKind.online,
    name: '示例站',
    domain: 'www.example.com',
  );
  // Tab 顺序：全部 / 原创 / 示例站（模拟一个有藏书的联网站点）
  final shelves = <Bookshelf>[
    Bookshelf.systemShelves[0],
    Bookshelf.systemShelves[1],
    siteShelf,
  ];

  Future<void> pumpShelf(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBookshelfProvider.overrideWith(_FakeCurrentBookshelf.new),
          bookshelfShelvesProvider.overrideWith((ref) async => shelves),
          // 书架内容按书架分桶的 family provider（keepAlive，无 family 级
          // overrideWith）—— 卡片式滑动切换时相邻书架卡片直接从这些
          // provider 取数据，因此逐书架覆盖为空数据
          for (final shelf in shelves)
            shelfNovelsProvider(shelf).overrideWith(
              (ref) async => const <Novel>[],
            ),
          for (final shelf in shelves)
            shelfCacheStatsProvider(shelf).overrideWith(
              (ref) async => const <String, CacheStats>{},
            ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFB8843A),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            extensions: <ThemeExtension<dynamic>>[AppColors.dark],
          ),
          home: const BookshelfScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Bookshelf currentShelfOf(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookshelfScreen)),
    );
    return container.read(currentBookshelfProvider);
  }

  group('书架左右滑动切换', () {
    testWidgets('向左滑依次进入下一个书架，向右滑回上一个', (tester) async {
      await pumpShelf(tester);
      expect(find.byType(EmptyBookshelfView), findsOneWidget);
      expect(currentShelfOf(tester), Bookshelf.systemShelves[0]); // 全部

      // 向左滑：全部 -> 原创
      await tester.drag(find.byType(BookshelfScreen), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(currentShelfOf(tester), Bookshelf.systemShelves[1]);

      // 向左滑：原创 -> 示例站
      await tester.drag(find.byType(BookshelfScreen), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(currentShelfOf(tester), siteShelf);

      // 向右滑：示例站 -> 原创
      await tester.drag(find.byType(BookshelfScreen), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(currentShelfOf(tester), Bookshelf.systemShelves[1]);
    });

    testWidgets('边界书架滑动不越界', (tester) async {
      await pumpShelf(tester);

      // 第一个书架再向右滑，保持「全部」
      await tester.drag(find.byType(BookshelfScreen), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(currentShelfOf(tester), Bookshelf.systemShelves[0]);

      // 连续向左滑到最后一个书架后再滑，保持「示例站」
      await tester.drag(find.byType(BookshelfScreen), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(BookshelfScreen), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(currentShelfOf(tester), siteShelf);

      await tester.drag(find.byType(BookshelfScreen), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(currentShelfOf(tester), siteShelf);
    });
  });
}

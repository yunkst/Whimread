/// 继续阅读入口回归测试
///
/// 回归背景：
/// 1. `NovelRepository.getLastReadChapter` 曾在「无阅读记录」时返回 0，而
///    `bookshelf_screen._continueReading` 用 `< 0` 判定无记录，提示永不触发，
///    用户被静默带到第 1 章。修复：仓储层无记录/列为空统一返回 -1（0 是合法
///    的第一章索引，不能与「无记录」混用）。
/// 2. 卡片「继续阅读」按钮的可见性由**缓存**的 Novel.lastReadChapterIndex
///    决定，点击后才实时查库。因此「缓存说有记录、库里没有」的脏数据状态
///    也必须给出正确提示而不是跳转。
///
/// 测试分层（两层合起来锁住本次修复，缺一不可）：
/// - 第一组：getLastReadChapter 契约跑**真实内存 SQLite**（普通 test，可驱动
///   sqflite_ffi 真实 I/O），验证「无记录 → -1 / 第一章 → 0」。
/// - 第二组：屏幕交互跑**真实 BookshelfScreen**，仓储以桩注入。testWidgets 的
///   FakeAsync 区无法驱动 sqflite_ffi 的真实 I/O（会挂起超时），且本组关注
///   的是屏幕对仓储返回值的决策（< 0 提示 vs 跳转），不是仓储实现本身。
///
/// 本文件取代已删除的 bookshelf_continue_reading_cache_test /
/// bookshelf_continue_reading_fix_verification_test（旧文件为占位断言，
/// 未触达任何生产代码）。

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/providers/bookshelf_providers.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/theme/app_colors.dart';
import 'package:novel_app/models/bookshelf.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/novel_repository.dart';
import 'package:novel_app/screens/bookshelf_screen.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/in_memory_db.dart';

/// 记录 Navigator push 的观察者，用于断言「未发生跳转」
class _RouteSpy extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

/// 测试用当前书架 Notifier：不走 SharedPreferences 持久化，仅持有内存状态
class _FakeCurrentBookshelf extends CurrentBookshelf {
  @override
  Bookshelf build() => Bookshelf.systemShelves.first;
}

/// 屏幕交互测试用的仓储桩：只回答 getLastReadChapter（同步完成的 Future，
/// FakeAsync 区可正常推进），其余方法一律抛错——一旦生产代码走到未预期的
/// 仓储方法会立即炸响，而不是静默返回默认值。
class _StubNovelRepository implements INovelRepository {
  _StubNovelRepository(this.lastReadChapter);

  final int lastReadChapter;

  @override
  Future<int> getLastReadChapter(String novelUrl) async => lastReadChapter;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '本测试桩未实现 ${invocation.memberName}');
}

/// 插入一条书架行，[lastReadChapter] 传 null 表示显式写空值。
Future<void> _insertBookshelfRow(
  Database db, {
  required String url,
  int? lastReadChapter,
  bool includeLastReadColumn = true,
}) async {
  final row = <String, dynamic>{
    'title': '测试书',
    'author': '作者',
    'url': url,
    'addedAt': DateTime.now().millisecondsSinceEpoch,
  };
  if (includeLastReadColumn) {
    row['lastReadChapter'] = lastReadChapter;
  }
  await db.insert('bookshelf', row);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUp(() async {
    db = await setupInMemoryDb();
  });

  tearDown(() async {
    await db.close();
    await DatabaseConnection.resetInstance();
  });

  group('getLastReadChapter 契约（真实 SQLite）', () {
    test('不在书架 → -1（无阅读记录）', () async {
      final repo = NovelRepository(
        dbConnection: DatabaseConnection.forTesting(db),
      );
      expect(await repo.getLastReadChapter('https://example.com/none'), -1);
    });

    test('lastReadChapter 为 null → -1（无阅读记录）', () async {
      const url = 'https://example.com/null-progress';
      await _insertBookshelfRow(db, url: url, lastReadChapter: null);
      final repo = NovelRepository(
        dbConnection: DatabaseConnection.forTesting(db),
      );
      expect(await repo.getLastReadChapter(url), -1);
    });

    test('lastReadChapter = 0 → 0（第一章是合法进度，不与无记录混淆）', () async {
      const url = 'https://example.com/first-chapter';
      await _insertBookshelfRow(db, url: url, lastReadChapter: 0);
      final repo = NovelRepository(
        dbConnection: DatabaseConnection.forTesting(db),
      );
      expect(await repo.getLastReadChapter(url), 0);
    });

    test('lastReadChapter = 3 → 3', () async {
      const url = 'https://example.com/mid-book';
      await _insertBookshelfRow(db, url: url, lastReadChapter: 3);
      final repo = NovelRepository(
        dbConnection: DatabaseConnection.forTesting(db),
      );
      expect(await repo.getLastReadChapter(url), 3);
    });

    test('未写 lastReadChapter 列时走表默认值 0', () async {
      const url = 'https://example.com/default-column';
      await _insertBookshelfRow(db, url: url, includeLastReadColumn: false);
      final repo = NovelRepository(
        dbConnection: DatabaseConnection.forTesting(db),
      );
      expect(await repo.getLastReadChapter(url), 0);
    });
  });

  group('继续阅读按钮交互（真实 BookshelfScreen）', () {
    late List<String> toastMessages;
    late _RouteSpy routeSpy;

    setUp(() {
      toastMessages = <String>[];
      routeSpy = _RouteSpy();
      // Fluttertoast 是平台通道：toast 渲染在原生层，widget 树里找不到，
      // 只能通过 channel mock 捕获消息内容做断言。
      // 通道名以 fluttertoast 8.2.x 实现为准（'PonnamKarthik/fluttertoast'）。
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('PonnamKarthik/fluttertoast'),
        (call) async {
          if (call.method == 'showToast') {
            final args = call.arguments;
            if (args is Map) {
              toastMessages.add(args['msg'] as String? ?? '');
            }
          }
          return true;
        },
      );
    });

    tearDown(() {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('PonnamKarthik/fluttertoast'), null);
    });

    Future<void> pumpShelf(
      WidgetTester tester,
      List<Novel> novels, {
      required int repositoryReturns,
    }) async {
      // 卡片高宽比 0.58，默认 800×600 表面下「继续阅读」按钮被裁到可点区域
      // 之外（tap 会 warnIfMissed）。加高表面保证按钮可点；physicalSize 随
      // WidgetTester 生命周期自动重置，不污染其它测试。
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      final shelves = <Bookshelf>[Bookshelf.systemShelves[0]];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // 屏幕决策测试用桩仓储：FakeAsync 区驱动不了 sqflite_ffi 真实 I/O
            novelRepositoryProvider
                .overrideWithValue(_StubNovelRepository(repositoryReturns)),
            currentBookshelfProvider.overrideWith(_FakeCurrentBookshelf.new),
            bookshelfShelvesProvider.overrideWith((ref) async => shelves),
            for (final shelf in shelves)
              shelfNovelsProvider(shelf).overrideWith((ref) async => novels),
            for (final shelf in shelves)
              shelfCacheStatsProvider(shelf)
                  .overrideWith((ref) async => const <String, CacheStats>{}),
          ],
          child: MaterialApp(
            navigatorObservers: [routeSpy],
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
      // 初始 "/" 路由是 pumpWidget 本身推入的，不算「跳转」，清空后只统计
      // 用户点击触发的导航
      routeSpy.pushed.clear();
    }

    Novel novelWithCachedProgress(String url, int? cachedIndex) => Novel(
          title: '测试书',
          author: '作者',
          url: url,
          isInBookshelf: true,
          lastReadChapterIndex: cachedIndex,
        );

    testWidgets('缓存有进度但库里无记录（仓储返回 -1）→ 提示「暂无阅读记录」且不跳转',
        (tester) async {
      const url = 'https://example.com/stale-cache';
      // 缓存的 Novel 声称读到第 6 章，按钮因此可见；实时查库得到 -1（无记录）
      await pumpShelf(
        tester,
        [novelWithCachedProgress(url, 5)],
        repositoryReturns: -1,
      );

      expect(find.text('继续阅读'), findsOneWidget);
      await tester.tap(find.text('继续阅读'));
      // _continueReading 是 async：等仓储 Future 微任务与 toast 回调完成
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(toastMessages, contains('暂无阅读记录'));
      expect(routeSpy.pushed, isEmpty,
          reason: '无阅读记录时必须留在书架，不得静默进入阅读器');
    });

    testWidgets('缓存无进度 → 按钮不显示，也不触发任何查询后跳转', (tester) async {
      const url = 'https://example.com/no-cache';
      await pumpShelf(
        tester,
        [novelWithCachedProgress(url, null)],
        repositoryReturns: 2,
      );

      expect(find.text('继续阅读'), findsNothing);
      expect(routeSpy.pushed, isEmpty);
    });
  });
}

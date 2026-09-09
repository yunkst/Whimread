import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/core/providers/bookshelf_providers.dart';
import 'package:novel_app/models/bookshelf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  /// 等待 Provider 状态达到 [expected]，最多 [timeout] 时间。
  ///
  /// Provider 的 build() 同步返回默认值，`_loadSavedKind` 是 fire-and-forget 异步
  /// 从 SharedPreferences 读值再回写 state。固定延时在某些机器上不够，用轮询更稳。
  ///
  /// 注意：provider 是 AutoDispose 的，必须先 `listen` 保持存活，
  /// 否则 read 返回后 notifier 立即销毁，异步回写的 state 会丢失。
  Future<void> _waitForKind(
    ProviderContainer container,
    BookshelfKind expected, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final sub = container.listen(currentBookshelfKindProvider, (_, __) {});
    try {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (container.read(currentBookshelfKindProvider) == expected) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('等待 $expected 超时，当前仍为 '
          '${container.read(currentBookshelfKindProvider)}');
    } finally {
      sub.close();
    }
  }

  group('[CurrentBookshelfKind] - Provider状态管理测试', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('build 默认返回 BookshelfKind.all', () async {
      // 触发 build（fire-and-forget _loadSavedKind 不会更新 state，因为是空 store）
      final initial = container.read(currentBookshelfKindProvider);
      expect(initial, BookshelfKind.all);

      // 给异步加载一点点时间，确保不会"之后"又变了
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(currentBookshelfKindProvider), BookshelfKind.all);
    });

    test('setBookshelfKind 更新 Provider 状态', () {
      container
          .read(currentBookshelfKindProvider.notifier)
          .setBookshelfKind(BookshelfKind.original);
      expect(container.read(currentBookshelfKindProvider),
          BookshelfKind.original);
    });

    test('setBookshelfKind 持久化到 SharedPreferences（新键）', () async {
      container
          .read(currentBookshelfKindProvider.notifier)
          .setBookshelfKind(BookshelfKind.online);
      // setBookshelfKind 同步调 prefsService.setString，但 SP 写入是异步
      final prefs = await SharedPreferences.getInstance();
      // 轮询等待写入完成
      var value = prefs.getString('current_bookshelf_kind');
      for (var i = 0; i < 50 && value != 'online'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        value = prefs.getString('current_bookshelf_kind');
      }
      expect(value, 'online');
    });

    test('从新键加载已保存的 kind', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'original');

      // 用新 container 让 _loadSavedKind 真的跑一遍
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfKindProvider);
      await _waitForKind(c, BookshelfKind.original);
    });

    test('从旧键（int 书架ID）兜底加载', () async {
      // 旧键 legacy 1 -> 全部；2 -> 我的收藏 -> 全部
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_bookshelf_id', 1);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfKindProvider);
      await _waitForKind(c, BookshelfKind.all);
    });

    test('旧键为未知值（用户自定义书架已下线）兜底为全部', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_bookshelf_id', 42);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfKindProvider);
      await _waitForKind(c, BookshelfKind.all);
    });

    test('新键优先于旧键', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'online');
      await prefs.setInt('current_bookshelf_id', 1); // 旧键说 全部

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfKindProvider);
      await _waitForKind(c, BookshelfKind.online);
    });

    test('未知的新键值兜底为全部', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'some_future_kind');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfKindProvider);
      await _waitForKind(c, BookshelfKind.all);
    });
  });

  group('[Bookshelf.systemShelves] - 三档固定分类', () {
    test('返回全部/原创/联网三档固定顺序', () {
      expect(
        Bookshelf.systemShelves.map((b) => b.kind).toList(),
        [BookshelfKind.all, BookshelfKind.original, BookshelfKind.online],
      );
    });

    test('Bookshelf.fromLegacyId 旧 ID 映射', () {
      expect(Bookshelf.fromLegacyId(1).kind, BookshelfKind.all);
      expect(Bookshelf.fromLegacyId(2).kind, BookshelfKind.all);
      expect(Bookshelf.fromLegacyId(99).kind, BookshelfKind.all);
    });
  });
}

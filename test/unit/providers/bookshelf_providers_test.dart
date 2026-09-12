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
  /// Provider 的 build() 同步返回默认值，`_loadSaved` 是 fire-and-forget 异步
  /// 从 SharedPreferences 读值再回写 state。固定延时在某些机器上不够，用轮询更稳。
  ///
  /// 注意：provider 是 AutoDispose 的，必须先 `listen` 保持存活，
  /// 否则 read 返回后 notifier 立即销毁，异步回写的 state 会丢失。
  Future<void> _waitForShelf(
    ProviderContainer container,
    Bookshelf expected, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final sub = container.listen(currentBookshelfProvider, (_, __) {});
    try {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (container.read(currentBookshelfProvider) == expected) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('等待 $expected 超时，当前仍为 '
          '${container.read(currentBookshelfProvider)}');
    } finally {
      sub.close();
    }
  }

  group('[CurrentBookshelf] - Provider状态管理测试', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('build 默认返回"全部"书架', () async {
      // 触发 build（fire-and-forget _loadSaved 不会更新 state，因为是空 store）
      final initial = container.read(currentBookshelfProvider);
      expect(initial.kind, BookshelfKind.all);

      // 给异步加载一点点时间，确保不会"之后"又变了
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(currentBookshelfProvider).kind, BookshelfKind.all);
    });

    test('setBookshelf 更新 Provider 状态', () {
      const original = Bookshelf(kind: BookshelfKind.original, name: '原创');
      container.read(currentBookshelfProvider.notifier).setBookshelf(original);
      expect(container.read(currentBookshelfProvider), original);
    });

    test('setBookshelf 站点书架持久化为 online:<host>（新键）', () async {
      const site = Bookshelf(
        kind: BookshelfKind.online,
        name: 'example.com',
        domain: 'www.example.com',
      );
      container.read(currentBookshelfProvider.notifier).setBookshelf(site);
      // setBookshelf 同步调 prefsService.setString，但 SP 写入是异步
      final prefs = await SharedPreferences.getInstance();
      // 轮询等待写入完成
      var value = prefs.getString('current_bookshelf_kind');
      for (var i = 0; i < 50 && value != 'online:www.example.com'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        value = prefs.getString('current_bookshelf_kind');
      }
      expect(value, 'online:www.example.com');
    });

    test('从新键加载已保存的 kind', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'original');

      // 用新 container 让 _loadSaved 真的跑一遍
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfProvider);
      await _waitForShelf(
        c,
        const Bookshelf(kind: BookshelfKind.original, name: '原创'),
      );
    });

    test('从新键加载站点书架（online:<host>）', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'online:www.example.com');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfProvider);
      await _waitForShelf(
        c,
        const Bookshelf(
          kind: BookshelfKind.online,
          name: 'example.com',
          domain: 'www.example.com',
        ),
      );
    });

    test('裸 online（旧聚合书架已下线）兜底为全部', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'online');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfProvider);
      await _waitForShelf(
        c,
        const Bookshelf(kind: BookshelfKind.all, name: '全部'),
      );
    });

    test('从旧键（int 书架ID）兜底加载', () async {
      // 旧键 legacy 1 -> 全部；2 -> 我的收藏 -> 全部
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_bookshelf_id', 1);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfProvider);
      await _waitForShelf(
        c,
        const Bookshelf(kind: BookshelfKind.all, name: '全部'),
      );
    });

    test('旧键为未知值（用户自定义书架已下线）兜底为全部', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_bookshelf_id', 42);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfProvider);
      await _waitForShelf(
        c,
        const Bookshelf(kind: BookshelfKind.all, name: '全部'),
      );
    });

    test('新键优先于旧键', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'original');
      await prefs.setInt('current_bookshelf_id', 1); // 旧键说 全部

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfProvider);
      await _waitForShelf(
        c,
        const Bookshelf(kind: BookshelfKind.original, name: '原创'),
      );
    });

    test('未知的新键值兜底为全部', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_bookshelf_kind', 'some_future_kind');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentBookshelfProvider);
      await _waitForShelf(
        c,
        const Bookshelf(kind: BookshelfKind.all, name: '全部'),
      );
    });
  });

  group('[Bookshelf] - 模型', () {
    test('systemShelves 三档固定顺序（历史遗留列表）', () {
      expect(
        Bookshelf.systemShelves.map((b) => b.kind).toList(),
        [BookshelfKind.all, BookshelfKind.original, BookshelfKind.online],
      );
    });

    test('tabShelves 生成全部/原创 + 按站点拆分的联网书架', () {
      final shelves = Bookshelf.tabShelves([
        'www.example.com',
        'm.qidian.com',
      ]);
      expect(shelves, hasLength(4));
      expect(shelves[0].kind, BookshelfKind.all);
      expect(shelves[0].domain, isNull);
      expect(shelves[1].kind, BookshelfKind.original);
      expect(shelves[2].kind, BookshelfKind.online);
      expect(shelves[2].domain, 'www.example.com');
      expect(shelves[2].name, 'example.com'); // www. 前缀剥除
      expect(shelves[3].domain, 'm.qidian.com');
      expect(shelves[3].isSiteShelf, isTrue);
    });

    test('tabShelves 无站点时只有全部/原创', () {
      expect(Bookshelf.tabShelves([]), hasLength(2));
    });

    test('tabShelves 有登记名时优先用站点显示名，未登记回退 host', () {
      final shelves = Bookshelf.tabShelves(
        [
          'www.qidian.com',
          'm.example.com',
        ],
        displayNames: {'www.qidian.com': '起点中文网'},
      );
      expect(shelves[2].domain, 'www.qidian.com');
      expect(shelves[2].name, '起点中文网'); // 登记名优先
      expect(shelves[3].domain, 'm.example.com');
      expect(shelves[3].name, 'm.example.com'); // 未登记回退 host
    });

    test('相等性按 kind + domain 判定', () {
      const a = Bookshelf(
        kind: BookshelfKind.online,
        name: 'example.com',
        domain: 'www.example.com',
      );
      const b = Bookshelf(
        kind: BookshelfKind.online,
        name: '别的显示名',
        domain: 'www.example.com',
      );
      const c = Bookshelf(
        kind: BookshelfKind.online,
        name: 'qidian.com',
        domain: 'm.qidian.com',
      );
      expect(a, equals(b)); // 显示名不参与相等性
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('siteDisplayName 剥除 www. 前缀', () {
      expect(Bookshelf.siteDisplayName('www.qidian.com'), 'qidian.com');
      expect(Bookshelf.siteDisplayName('m.qidian.com'), 'm.qidian.com');
    });

    test('toPersistedValue / fromPersistedValue 编解码往返', () {
      const site = Bookshelf(
        kind: BookshelfKind.online,
        name: 'example.com',
        domain: 'www.example.com',
      );
      expect(site.toPersistedValue(), 'online:www.example.com');
      expect(Bookshelf.fromPersistedValue('online:www.example.com'), site);
      expect(
        Bookshelf.fromPersistedValue('all').kind,
        BookshelfKind.all,
      );
      expect(
        Bookshelf.fromPersistedValue('original').kind,
        BookshelfKind.original,
      );
      // 裸 online / 未知值兜底为全部
      expect(
        Bookshelf.fromPersistedValue('online').kind,
        BookshelfKind.all,
      );
      expect(
        Bookshelf.fromPersistedValue('online:').kind, // 空 host 视为非法
        BookshelfKind.all,
      );
      expect(
        Bookshelf.fromPersistedValue('whatever').kind,
        BookshelfKind.all,
      );
    });

    test('Bookshelf.fromLegacyId 旧 ID 映射', () {
      expect(Bookshelf.fromLegacyId(1).kind, BookshelfKind.all);
      expect(Bookshelf.fromLegacyId(2).kind, BookshelfKind.all);
      expect(Bookshelf.fromLegacyId(99).kind, BookshelfKind.all);
    });
  });
}

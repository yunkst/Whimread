/// webview_add_novel_providers 单元测试
///
/// 测试三个反应式 Provider：
///   - webviewCurrentDomainProvider：URL → host 提取
///   - webviewCurrentSiteScriptProvider：host → SiteScript 查询
///   - webviewHasAddNovelButtonProvider：派生按钮可见性
///
/// 运行：
///   flutter test test/unit/providers/webview_add_novel_providers_test.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/webview_add_novel_providers.dart';
import 'package:novel_app/core/providers/webview_providers.dart';

void main() {
  // ===================================================================
  // 基础设施
  // ===================================================================
  late ProviderContainer container;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // 创建内存数据库 + 完整迁移
    final db = await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );
    await DatabaseMigrations.createV1Tables(db);
    await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);

    final dbConnection = DatabaseConnection.forTesting(db);

    container = ProviderContainer(overrides: [
      databaseConnectionProvider.overrideWithValue(dbConnection),
    ]);
  });

  tearDown(() {
    container.dispose();
  });

  // ===================================================================
  // webviewCurrentDomainProvider
  // ===================================================================
  group('webviewCurrentDomainProvider', () {
    test('https URL → 提取 host', () {
      container
          .read(webviewCurrentUrlProvider.notifier)
          .state = 'https://www.alicesw.com/book/123';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, equals('www.alicesw.com'));
    });

    test('http URL → 提取 host', () {
      container
          .read(webviewCurrentUrlProvider.notifier)
          .state = 'http://example.com/page';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, equals('example.com'));
    });

    test('带路径和查询参数的 URL → 提取 host', () {
      container.read(webviewCurrentUrlProvider.notifier).state =
          'https://www.biquge543.com/book/123/chapter.html?page=2&sort=asc';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, equals('www.biquge543.com'));
    });

    test('about:blank → null', () {
      container
          .read(webviewCurrentUrlProvider.notifier)
          .state = 'about:blank';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, isNull);
    });

    test('空字符串 → null', () {
      container.read(webviewCurrentUrlProvider.notifier).state = '';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, isNull);
    });

    test('无效 URL → null', () {
      container.read(webviewCurrentUrlProvider.notifier).state = 'not a url';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, isNull);
    });

    test('file:// 协议 → null', () {
      container.read(webviewCurrentUrlProvider.notifier).state =
          'file:///C:/test.html';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, isNull);
    });

    test('javascript: 伪协议 → null', () {
      container
          .read(webviewCurrentUrlProvider.notifier)
          .state = 'javascript:void(0)';
      final domain = container.read(webviewCurrentDomainProvider);
      expect(domain, isNull);
    });
  });

  // ===================================================================
  // webviewCurrentSiteScriptProvider
  // ===================================================================
  group('webviewCurrentSiteScriptProvider', () {
    test('domain 为 null → 返回 null（同步，不触发 DB 查询）', () async {
      container.read(webviewCurrentUrlProvider.notifier).state = '';
      final script = await container.read(
        webviewCurrentSiteScriptProvider.future,
      );
      expect(script, isNull);
    });

    test('无匹配脚本 → 返回 null', () async {
      container.read(webviewCurrentUrlProvider.notifier).state =
          'https://unknown-site.com/book/123';
      final script = await container.read(
        webviewCurrentSiteScriptProvider.future,
      );
      expect(script, isNull);
    });

    test('有匹配脚本 → 返回 SiteScript', () async {
      // 预插入一条 site_script
      final db = container.read(databaseConnectionProvider).database;
      await db.then((d) => d.insert('site_scripts', {
            'id': 'test-script-1',
            'domain': 'www.alicesw.com',
            'url_pattern': '',
            'chapter_list_js': '(async function(){ return JSON.stringify({title:"test",chapters:[]}); })()',
            'chapter_content_js': '',
            'sample_url': 'https://www.alicesw.com/book/123',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'last_used_at': DateTime.now().millisecondsSinceEpoch,
            'use_count': 0,
            'verified': 0,
          }));

      container.read(webviewCurrentUrlProvider.notifier).state =
          'https://www.alicesw.com/book/123';
      final script = await container.read(
        webviewCurrentSiteScriptProvider.future,
      );
      expect(script, isNotNull);
      expect(script!.domain, equals('www.alicesw.com'));
      expect(script.hasChapterListJs, isTrue);
      expect(script.hasChapterContentJs, isFalse);
    });

    test('URL 变化 → 重新查询（Provider 自动失效）', () async {
      final db = container.read(databaseConnectionProvider).database;
      await db.then((d) => d.insert('site_scripts', {
            'id': 'test-script-2',
            'domain': 'www.alicesw.com',
            'url_pattern': '',
            'chapter_list_js': '...',
            'chapter_content_js': '',
            'sample_url': '',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'last_used_at': DateTime.now().millisecondsSinceEpoch,
            'use_count': 0,
            'verified': 0,
          }));

      // 初始 URL：有脚本
      container.read(webviewCurrentUrlProvider.notifier).state =
          'https://www.alicesw.com/book/123';
      var script = await container.read(
        webviewCurrentSiteScriptProvider.future,
      );
      expect(script, isNotNull);

      // 切换 URL：无脚本
      container.read(webviewCurrentUrlProvider.notifier).state =
          'https://no-script-site.com/book/456';
      script = await container.read(
        webviewCurrentSiteScriptProvider.future,
      );
      expect(script, isNull);
    });

    /// 回归保护："首次添加书架必然触发 agent" bug 的根因文档。
    ///
    /// 场景：DB 里有该 domain 的脚本缓存，但 [webviewCurrentSiteScriptProvider]
    /// 未被任何 widget watch 预热（与 _WebViewAddNovelFabState 只 watch
    /// `webviewHasAddNovelButtonProvider`、点击时 read `valueOrNull` 的当前实现
    /// 完全对应）。此时同步 `.valueOrNull` 必为 null → 误判无脚本 → agent 降级。
    ///
    /// 修复方式（webview_add_novel_button.dart）：点击处改用
    /// `await ref.read(webviewCurrentSiteScriptProvider.future)`
    /// 等待 Future 完成，再判断是否为 null。
    ///
    /// 本测试固化两点契约：
    /// 1. 同步 `.valueOrNull` 在 Future 未预热时确实返回 null（bug 存在证明）
    /// 2. `await .future` 必能拿到 DB 里的真实脚本（修复方向正确证明）
    ///
    /// 防止以后把 FAB 点击逻辑改回 `valueOrNull` 再次踩坑。
    test(
        '回归: 有脚本未预热时, 同步 valueOrNull 为 null; await future 拿到真实脚本',
        () async {
      // 预插入脚本
      final db = container.read(databaseConnectionProvider).database;
      await db.then((d) => d.insert('site_scripts', {
            'id': 'warm-fix-script',
            'domain': 'www.alicesw.com',
            'url_pattern': '',
            'chapter_list_js': '(async function(){})()',
            'chapter_content_js': '',
            'sample_url': 'https://www.alicesw.com/book/123',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'last_used_at': DateTime.now().millisecondsSinceEpoch,
            'use_count': 0,
            'verified': 0,
          }));

      // 设置 URL（domain 同步就绪，但 FutureProvider 未被任何 widget watch 预热）
      container.read(webviewCurrentUrlProvider.notifier).state =
          'https://www.alicesw.com/book/123';

      // ❌ bug 路径：同步读 .valueOrNull —— Future 此刻在 loading，valueOrNull 为 null
      //    即使 DB 里有该 domain 的脚本
      final buggyValue =
          container.read(webviewCurrentSiteScriptProvider).valueOrNull;
      expect(
        buggyValue,
        isNull,
        reason:
            'Future 未预热/未完成时同步 valueOrNull 必为 null（首次点击误判无脚本的根因）',
      );

      // ✅ 修复路径：await .future 等 Future 跑完，拿 DB 真实结果
      final fixedValue =
          await container.read(webviewCurrentSiteScriptProvider.future);
      expect(fixedValue, isNotNull);
      expect(fixedValue!.domain, equals('www.alicesw.com'));
    });
  });

  // ===================================================================
  // webviewHasAddNovelButtonProvider
  // ===================================================================
  group('webviewHasAddNovelButtonProvider', () {
    test('http(s) 页面 -> 显示 FAB（无论有无脚本）', () {
      container.read(webviewCurrentUrlProvider.notifier).state =
          'https://unknown-site.com/book/123';
      // 即使无脚本也显示（降级到 agent 生成）
      expect(container.read(webviewHasAddNovelButtonProvider), isTrue);
    });

    test('非 http(s) 页面 -> 不显示 FAB', () {
      container.read(webviewCurrentUrlProvider.notifier).state = 'about:blank';
      expect(container.read(webviewHasAddNovelButtonProvider), isFalse);
    });

    test('空 URL -> 不显示 FAB', () {
      container.read(webviewCurrentUrlProvider.notifier).state = '';
      expect(container.read(webviewHasAddNovelButtonProvider), isFalse);
    });
  });
}

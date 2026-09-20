/// CrawlRequestResolver 测试
///
/// P1 核心：URL×脚本×模式对齐唯一入口，修复爱丽丝网 no script 与跳转。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/site_script.dart';
import 'package:novel_app/repositories/site_script_repository.dart';
import 'package:novel_app/services/crawler/browser_mode.dart';
import 'package:novel_app/services/crawler/crawl_request.dart';
import 'package:novel_app/services/crawler/crawl_request_resolver.dart';
import 'package:novel_app/services/crawler/site_key.dart';
import 'package:sqflite_common/sqflite.dart';

import '../../../helpers/test_database_setup.dart';

void main() {
  late SiteScriptRepository repo;
  late Database db;
  late CrawlRequestResolver resolver;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    final connection = DatabaseConnection.forTesting(db);
    repo = SiteScriptRepository(dbConnection: connection);
    resolver = CrawlRequestResolver(
      scriptRepo: repo,
      globalModeProvider: () => BrowserMode.desktop, // 测试兜底：桌面
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertScript({
    required String id,
    required String domain,
    String chapterListJs = 'CL',
    String chapterContentJs = 'CC',
    String bookshelfJs = '',
    int preferredMode = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('site_scripts', {
      'id': id,
      'domain': domain,
      'url_pattern': '',
      'chapter_list_js': chapterListJs,
      'chapter_content_js': chapterContentJs,
      'bookshelf_js': bookshelfJs,
      'sample_url': '',
      'created_at': now,
      'last_used_at': now,
      'use_count': 0,
      'verified': 0,
      'preferred_mode': preferredMode,
    });
  }

  group('findByUrlHost 变体等价匹配', () {
    test('精确匹配（主路径）', () async {
      await insertScript(id: 's1', domain: 'www.alice.com');
      final found = await repo.findByUrlHost('www.alice.com');
      expect(found?.id, 's1');
    });

    test('m. 变体匹配已存的 www. 脚本', () async {
      await insertScript(id: 's1', domain: 'www.alice.com');
      final found = await repo.findByUrlHost('m.alice.com');
      expect(found?.id, 's1', reason: 'www./m. 变体应视为同站点');
    });

    test('wap./mobile. 变体匹配', () async {
      await insertScript(id: 's1', domain: 'alice.com');
      expect((await repo.findByUrlHost('wap.alice.com'))?.id, 's1');
      expect((await repo.findByUrlHost('mobile.alice.com'))?.id, 's1');
    });

    test('大小写不敏感', () async {
      await insertScript(id: 's1', domain: 'www.alice.com');
      final found = await repo.findByUrlHost('WWW.ALICE.COM');
      expect(found?.id, 's1');
    });

    test('不归并不同子域（novel.alice.com ≠ alice.com）', () async {
      await insertScript(id: 's1', domain: 'alice.com');
      final found = await repo.findByUrlHost('novel.alice.com');
      expect(found, isNull);
    });

    test('不同站点不互相命中', () async {
      await insertScript(id: 's1', domain: 'www.alice.com');
      final found = await repo.findByUrlHost('www.bob.com');
      expect(found, isNull);
    });

    test('空 host 返回 null', () async {
      final found = await repo.findByUrlHost('');
      expect(found, isNull);
    });
  });

  group('Resolver: 对齐成功', () {
    test('host 一致时 canonicalUrl == requestedUrl', () async {
      await insertScript(
        id: 's1',
        domain: 'www.alice.com',
        chapterListJs: 'CL',
        preferredMode: 1,
      );
      final url = Uri.parse('https://www.alice.com/book/123');
      final r = await resolver.resolve(url, ScriptSlot.chapterList);
      expect(r, isA<CrawlAligned>());
      final request = (r as CrawlAligned).request;
      expect(request.canonicalUrl, url);
      expect(request.hostRewritten, isFalse);
      expect(request.script.id, 's1');
      expect(request.mode, BrowserMode.desktop);
    });

    test('host 不一致时 canonicalUrl.host 被重写为脚本 host（修跳转）', () async {
      await insertScript(
        id: 's1',
        domain: 'm.alice.com',
        chapterContentJs: 'CC',
        preferredMode: 2, // 脚本声明手机模式
      );
      // 用户用桌面模式打开页面，URL 是 www.alice.com，但脚本是 m. 写的
      final url = Uri.parse('https://www.alice.com/book/1/ch1');
      final r = await resolver.resolve(url, ScriptSlot.chapterContent);
      expect(r, isA<CrawlAligned>());
      final request = (r as CrawlAligned).request;
      // host 被改写为脚本保存时的 host
      expect(request.canonicalUrl.host, 'm.alice.com');
      expect(request.canonicalUrl.path, '/book/1/ch1'); // path 保留
      expect(request.hostRewritten, isTrue);
      expect(request.hostRewriteLog, 'www.alice.com → m.alice.com');
      // 模式按脚本声明（无视当前全局模式）
      expect(request.mode, BrowserMode.mobile);
    });

    test('脚本未指定模式时回退到全局模式', () async {
      await insertScript(id: 's1', domain: 'alice.com', preferredMode: 0);
      final url = Uri.parse('https://alice.com/book/1');
      final r = await resolver.resolve(url, ScriptSlot.chapterList);
      expect((r as CrawlAligned).request.mode, BrowserMode.desktop);
    });

    test('变量注入 globalModeProvider 可被测出来', () async {
      final mobileResolver = CrawlRequestResolver(
        scriptRepo: repo,
        globalModeProvider: () => BrowserMode.mobile,
      );
      await insertScript(id: 's1', domain: 'alice.com', preferredMode: 0);
      final r = await mobileResolver.resolve(
        Uri.parse('https://alice.com/book/1'),
        ScriptSlot.chapterList,
      );
      expect((r as CrawlAligned).request.mode, BrowserMode.mobile);
    });
  });

  group('Resolver: CrawlNoScript 情形', () {
    test('URL 解析失败', () async {
      final r = await resolver.resolve(null, ScriptSlot.chapterList);
      expect(r, isA<CrawlNoScript>());
      expect((r as CrawlNoScript).url, isNull);
      expect(r.slot, ScriptSlot.chapterList);
    });

    test('空 host', () async {
      final r = await resolver.resolve(
        Uri.parse('https://'),
        ScriptSlot.chapterList,
      );
      expect(r, isA<CrawlNoScript>());
    });

    test('host 无脚本', () async {
      final r = await resolver.resolve(
        Uri.parse('https://www.unknown.com/book/1'),
        ScriptSlot.chapterList,
      );
      expect(r, isA<CrawlNoScript>());
      final ns = r as CrawlNoScript;
      expect(ns.siteKey, SiteKey.fromHost('www.unknown.com'));
    });

    test('host 有脚本但请求的 slot 为空（书目脚本查章节）', () async {
      await insertScript(
        id: 's1',
        domain: 'alice.com',
        chapterListJs: '', // 没目录脚本
        chapterContentJs: 'CC',
      );
      final r = await resolver.resolve(
        Uri.parse('https://alice.com/book/1'),
        ScriptSlot.chapterList,
      );
      expect(r, isA<CrawlNoScript>(),
          reason: '没有 chapter_list_js 字段，应判为 noScript');
    });

    test('变体找不到脚本时仍判 noScript（m.→www. 反向亦如此）', () async {
      // 数据库里只有 'novel.alice.com'（不同子域），不应被 www. 变体命中
      await insertScript(id: 's1', domain: 'novel.alice.com');
      final r = await resolver.resolve(
        Uri.parse('https://www.alice.com/book/1'),
        ScriptSlot.chapterList,
      );
      expect(r, isA<CrawlNoScript>());
    });
  });
}

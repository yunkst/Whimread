/// run_id 句柄机制集成测试
///
/// 使用真实的 Edge WebView2 在 Windows 桌面端测试 run_id 句柄机制。
/// **不模拟 WebView**——所有 JS 执行均为真实运行。
///
/// ## 测试覆盖
///   1. execute_js script 模式 → 返回 __meta.run_id，业务字段平铺
///   2. execute_js run_id 模式 → 重跑 RunStore 中脚本
///   3. execute_js run_id 模式 → RUN_ID_NOT_FOUND 错误
///   4. save_script run_id 模式 → 零重传保存
///   5. save_script run_id_not_found 错误
///   6. get_cached_script → 加载并返回 list_run_id/content_run_id
///   7. inspect_script → 调试查看完整脚本内容
///
/// ## 前提条件
///   - Windows 10/11，Edge WebView2 Runtime 已安装（Win11 预装）
///   - Flutter SDK 3.x
///   - SQLite 测试数据库已初始化
///
/// ## 运行
///   cd novel_app
///   flutter test integration_test/webview_extract/run_store_test.dart -d windows
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/services/novel_agent/scenarios/webview_extract_scenario.dart';
import 'package:novel_app/services/logger_service.dart';
import '../helpers/webview_test_helper.dart';

/// 通过 Provider 间接获取 Ref，构造 WebViewExtractScenario
WebViewExtractScenario createScenario(
  ProviderContainer container,
  InAppWebViewController controller, [
  String currentUrl = WebViewTestHelper.testBaseUrl,
]) {
  final provider = Provider<WebViewExtractScenario>((ref) {
    return WebViewExtractScenario(ref, controller, currentUrl);
  });
  return container.read(provider);
}

/// 执行工具调用并解码 JSON
Future<Map<String, dynamic>> callTool(
  WebViewExtractScenario scenario,
  String name,
  Map<String, dynamic> args,
) async {
  final result = await scenario.executeTool(name, args);
  return jsonDecode(result) as Map<String, dynamic>;
}

/// 目录提取脚本（含 {{URL}} 占位符，模拟 Agent 生成的格式）
const chapterListScript = '''
(function() {
  const PAGE_URL = '{{URL}}';
  const title = document.querySelector('.novel-title')?.innerText?.trim() || '';
  const chapters = [];
  document.querySelectorAll('.chapter-link').forEach(function(link) {
    chapters.push({
      title: link.innerText.trim(),
      url: new URL(link.getAttribute('href'), PAGE_URL).href
    });
  });
  return JSON.stringify({ title: title, chapters: chapters });
})()
''';

/// 内容提取脚本（含 {{URL}} 占位符）
const chapterContentScript = '''
(function() {
  const PAGE_URL = '{{URL}}';
  const title = document.querySelector('.chapter-title')?.innerText?.trim() || '';
  const paragraphs = [];
  document.querySelectorAll('.novel-paragraph').forEach(function(p) {
    paragraphs.push(p.innerText.trim());
  });
  return JSON.stringify({ title: title, content: paragraphs.join('\\n') });
})()
''';

/// 简单探测脚本（不参数化，不含 {{URL}}）
const simpleProbeScript = '''
(function() {
  return JSON.stringify({ totalLinks: document.querySelectorAll('a').length });
})()
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  DatabaseConnection? dbConnection;

  setUpAll(() async {
    LoggerService.resetForTesting();

    // 创建内存数据库（让 get_cached_script / save_script 不报错）
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(
      ':memory:',
      version: DatabaseMigrations.currentVersion,
      singleInstance: false,
    );
    await DatabaseMigrations.createV1Tables(db);
    await DatabaseMigrations.upgrade(db, 1, DatabaseMigrations.currentVersion);
    dbConnection = DatabaseConnection.forTesting(db);

    container = ProviderContainer(overrides: [
      databaseConnectionProvider.overrideWithValue(dbConnection!),
    ]);
  });

  tearDownAll(() async {
    container.dispose();
  });

  // ===========================================================================
  // 所有测试在一个 testWidgets 中运行，共享 WebView 实例
  // ===========================================================================

  testWidgets('run_id 句柄机制集成测试', (tester) async {
    final helper = WebViewTestHelper();
    final controller = await helper.createWebView(tester);
    final scenario = createScenario(container, controller);

    // ========================================================================
    // 1. execute_js script 模式 → __meta.run_id + 业务字段平铺
    // ========================================================================
    {
      final json = await callTool(scenario, 'execute_js', {
        'script': chapterListScript,
      });

      // 业务字段平铺在顶层（向后兼容）
      expect(json['title'], '星辰变');
      expect(json['chapters'], isNotEmpty);
      final chapters = json['chapters'] as List<dynamic>;
      expect(chapters.length, 3);
      expect((chapters.first as Map)['title'], '第一章 初入江湖');

      // run_id 句柄在 __meta 内
      final meta = json['__meta'] as Map<String, dynamic>?;
      expect(meta, isNotNull, reason: 'execute_js script 模式应返回 __meta');
      expect(meta!['run_id'], startsWith('exec_'),
          reason: '新脚本登记应返回 exec_n 形式 run_id');
      expect(meta['mode'], 'register');
      expect(meta['store_size'], greaterThanOrEqualTo(1));
      expect(meta['script_preview'], isNotNull,
          reason: 'register 模式应返回脚本截断预览');
    }

    // ========================================================================
    // 2. execute_js run_id 模式 → 重跑 RunStore 中脚本
    //    （用上一轮注册的 script 再跑一次内容提取脚本做对比）
    // ========================================================================
    String contentRunId = '';
    {
      final json = await callTool(scenario, 'execute_js', {
        'script': chapterContentScript,
      });

      expect(json['title'], '第一章 初入江湖');
      expect(json['content'], isNotNull);

      final meta = json['__meta'] as Map<String, dynamic>?;
      expect(meta, isNotNull);
      contentRunId = meta!['run_id'] as String;
      expect(contentRunId, startsWith('exec_'));
    }

    // 用 run_id 重跑内容脚本
    {
      final json = await callTool(scenario, 'execute_js', {
        'run_id': contentRunId,
      });

      // 业务字段仍平铺
      expect(json['title'], '第一章 初入江湖');
      expect(json['content'], isNotNull);

      final meta = json['__meta'] as Map<String, dynamic>?;
      expect(meta, isNotNull, reason: 'run_id 模式也应返回 __meta');
      expect(meta!['run_id'], contentRunId,
          reason: 'run_id 模式应返回相同的 run_id（不重新登记）');
      expect(meta['mode'], 'replay');
      // replay 模式不应包含 script_preview
      expect(meta.containsKey('script_preview'), isFalse);
    }

    // ========================================================================
    // 3. execute_js run_id 模式 → RUN_ID_NOT_FOUND
    // ========================================================================
    {
      final json = await callTool(scenario, 'execute_js', {
        'run_id': 'exec_999999',
      });

      expect(json['error'], 'RUN_ID_NOT_FOUND');
      expect(json['message'].toString(), contains('exec_999999'));
      expect(json['suggestion'], isNotNull);
    }

    // ========================================================================
    // 4. save_script run_id 模式 → 零重传保存
    //    先用 execute_js 跑两个脚本获取 run_id，再用 run_id 保存
    //    （v37 OCR 提取器：save_script 改为分次落库，参数为 run_id + script_type + test_url + ocr）
    // ========================================================================
    {
      // 注册目录脚本 run_id
      final listResult = await callTool(scenario, 'execute_js', {
        'script': chapterListScript,
      });
      final listRunId = (listResult['__meta'] as Map)['run_id'] as String;
      expect(listRunId, startsWith('exec_'));

      // 用新 schema 保存目录脚本（先验证后落库；test_url 必传）
      // 注意：save_script 走 headless WebView 真实加载 test_url 跑验证，
      // 集成测试在 headless=true 时会跑真验证。list 脚本输出的 title/chapters
      // 来自 WebViewTestHelper 的 list 页面（可正确解析），不传 ocr 走默认 false。
      final listSaveResult = await callTool(scenario, 'save_script', {
        'domain': 'example.com',
        'run_id': listRunId,
        'script_type': 'chapter_list',
        'test_url': WebViewTestHelper.testBaseUrl,
        'ocr': false,
      });
      expect(listSaveResult['success'], isTrue,
          reason: '目录脚本应验证通过：$listSaveResult');

      // 注册内容脚本 run_id
      final contentResult = await callTool(scenario, 'execute_js', {
        'script': chapterContentScript,
      });
      final contentRunId2 = (contentResult['__meta'] as Map)['run_id'] as String;

      // 用新 schema 保存内容脚本（test_url 指向 content 测试页）
      final contentSaveResult = await callTool(scenario, 'save_script', {
        'domain': 'example.com',
        'run_id': contentRunId2,
        'script_type': 'chapter_content',
        'test_url': WebViewTestHelper.testBaseUrl,
        'ocr': false,
      });
      expect(contentSaveResult['success'], isTrue,
          reason: '内容脚本应验证通过：$contentSaveResult');
    }

    // ========================================================================
    // 5. save_script run_id_not_found 错误
    //    （v37 新 schema：domain/run_id/script_type/test_url/ocr）
    // ========================================================================
    {
      final json = await callTool(scenario, 'save_script', {
        'domain': 'example.com',
        'run_id': 'exec_dead',
        'script_type': 'chapter_list',
        'test_url': WebViewTestHelper.testBaseUrl,
        'ocr': false,
      });

      expect(json['success'], false);
      expect(json['reason'], 'run_id_not_found');
      expect(json['message'].toString(), contains('exec_dead'));
      expect(json['store_size'], isNotNull);
      expect(json['suggestion'], isNotNull);
    }

    // ========================================================================
    // 6. get_cached_script → 加载并返回 list_run_id/content_run_id
    //    （步骤 4 已经保存了一条记录）
    // ========================================================================
    {
      final json = await callTool(scenario, 'get_cached_script', {
        'domain': 'example.com',
      });

      expect(json['found'], isTrue);
      expect(json['domain'], 'example.com');
      expect(json['list_run_id'], startsWith('db_'),
          reason: '数据库来源的脚本应返回 db_xxx 形式 run_id');
      expect(json['content_run_id'], startsWith('db_'));
      expect(json['id'], isNotNull);
      expect(json['use_count'], isNotNull);
      expect(json['candidates'], isNotEmpty);

      // 不应返回完整脚本内容（chapter_list_js / chapter_content_js）
      expect(json.containsKey('chapter_list_js'), isFalse,
          reason: '不应返回完整脚本内容，避免占上下文');
      expect(json.containsKey('chapter_content_js'), isFalse);

      // 应包含提示信息
      expect(json['message'].toString(), contains('execute_js'));
    }

    // ========================================================================
    // 7. get_cached_script → 取回的 run_id 可用于重跑
    // ========================================================================
    {
      final cached = await callTool(scenario, 'get_cached_script', {
        'domain': 'example.com',
      });

      final listRunId = cached['list_run_id'] as String;
      final contentRunId = cached['content_run_id'] as String;

      // 用 get_cached_script 返回的 run_id 直接重跑（零重抄）
      final listResult = await callTool(scenario, 'execute_js', {
        'run_id': listRunId,
      });
      expect(listResult['title'], '星辰变');
      expect(listResult['chapters'], isNotEmpty);

      final contentResult = await callTool(scenario, 'execute_js', {
        'run_id': contentRunId,
      });
      expect(contentResult['title'], '第一章 初入江湖');
      expect(contentResult['content'], isNotNull);
    }

    // ========================================================================
    // 8. inspect_script → 调试查看完整脚本内容
    // ========================================================================
    {
      // 先注册一个脚本拿到 run_id
      final execResult = await callTool(scenario, 'execute_js', {
        'script': chapterListScript,
      });
      final execRunId = (execResult['__meta'] as Map)['run_id'] as String;

      // 用 inspect_script 查看完整内容
      final json = await callTool(scenario, 'inspect_script', {
        'run_id': execRunId,
      });

      expect(json['run_id'], execRunId);
      expect(json['script'], chapterListScript,
          reason: '应返回完整脚本内容（调试用）');
      expect(json['source'], 'execution');
      expect(json['script_length'], chapterListScript.length);
      expect(json['success'], isTrue);
    }

    // inspect_script 对 db_xxx 来源也适用
    {
      final cached = await callTool(scenario, 'get_cached_script', {
        'domain': 'example.com',
      });
      final dbRunId = cached['list_run_id'] as String;

      final json = await callTool(scenario, 'inspect_script', {
        'run_id': dbRunId,
      });

      expect(json['run_id'], dbRunId);
      expect(json['source'], 'database');
      expect(json['domain'], 'example.com');
      expect(json['script'], isNotNull);
    }

    // inspect_script 对不存在的 run_id
    {
      final json = await callTool(scenario, 'inspect_script', {
        'run_id': 'exec_404',
      });

      expect(json['error'], 'RUN_ID_NOT_FOUND');
    }

    // inspect_script 缺少 run_id 参数
    {
      final json = await callTool(scenario, 'inspect_script', {});

      expect(json['error'], 'missing_param');
      expect(json['missing'], contains('run_id'));
    }

    // ========================================================================
    // 9. execute_js 缺参：script 和 run_id 都未传
    // ========================================================================
    {
      final json = await callTool(scenario, 'execute_js', {});

      expect(json['error'], 'missing_param');
      expect(json['suggestion'], isNotNull);
    }

    // script 参数为空字符串
    {
      final json = await callTool(scenario, 'execute_js', {
        'script': '',
      });

      expect(json['error'], 'missing_param');
      final missing = json['missing'] as List;
      expect(missing, contains('script 或 run_id'));
    }

    await helper.dispose();
  });
}

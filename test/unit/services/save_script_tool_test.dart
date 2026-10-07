/// save_script 工具的 unit 测试（方案 G：直接测静态 validateAndPersistScript，
/// 绕开 HeadlessWebViewPool / InAppWebViewController）。
///
/// _saveScript executor 涉及 WebView 平台依赖（HeadlessWebViewPool + InAppWebViewController
/// + callAsyncJavaScript），纯 Dart 测试无法构造。把核心验证逻辑抽成 static
/// `validateAndPersistScript` 后，可注入 jsResult/repo/restoreService 完成单测覆盖。
///
/// v48 起 OCR 触发为 PUA 自动检测：调用方不再传 ocr 参数；返回文本含 PUA
/// → 走 OCR 验证并落库 ocr=true，否则跳过 OCR 直接落库 ocr=false。
/// font_family 对 chapter_list / chapter_content 无条件必填（运行时还原依赖）。
///
/// 覆盖：
/// - 结构校验失败（content 太短）→ reason=content_too_short，不落库
/// - font_family 无条件必填（chapter_list / chapter_content）
/// - 含 PUA 且字体无效 → reason=font_family_invalid，不落库
/// - 含 PUA readable_ratio 不达标 → reason=readable_ratio_below_threshold
/// - 全部验证通过 → success=true，repo.updateScriptPart 调一次（参数正确）
/// - 无 PUA → 不走 OCR 验证直接落库（ocr=false），restoreService 不被调
/// - 含 PUA 但未注入 restoreService → restore_service_missing
/// - 结构校验：chapters_empty / chapter_missing_field / invalid_structure
/// - 落库：repo 返回失败 reason → 透传失败返回，不抛
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:novel_app/repositories/site_script_repository.dart';
import 'package:novel_app/services/novel_agent/scenarios/webview_extract_scenario.dart';
import 'package:novel_app/services/ocr_restore_service.dart';

import 'save_script_tool_test.mocks.dart';

@GenerateMocks([SiteScriptRepository, OcrRestoreService])
void main() {
  // ─── 工具函数 ───

  /// 72 字纯正常正文（无 PUA，远超 50 下限）。
  ///
  /// v48 起默认夹具不含 PUA：无 PUA = 不触发 OCR 验证，对应大多数站点的
  /// 主路径。OCR 路径的用例用 [puaContent] 显式构造。
  const longContent = '正常正文文字正常正文文字正常正文文字正常正文文字'
      '正常正文文字正常正文文字正常正文文字正常正文文字'
      '正常正文文字正常正文文字正常正文文字正常正文文字';

  /// [longContent] 末尾追加 1 个 PUA 码点（U+E000），用于触发自动 OCR 验证。
  const puaContent = '$longContent\u{E000}';

  /// 构造一个 chapter_content 用的合法 jsResult（含 content + font_family 必填字段）
  Map<String, dynamic> contentResult({
    String content = longContent,
    String fontFamily = 'GoodFont',
    String title = '第一章',
  }) =>
      {
        'content': content,
        'title': title,
        'font_family': fontFamily,
      };

  /// 构造一个 chapter_list 用的合法 jsResult（含 cover_url / font_family 必填字段）
  Map<String, dynamic> listResult({String title = '书名'}) => {
        'title': title,
        'cover_url': 'https://a.com/cover.jpg',
        'font_family': 'ListFont',
        'chapters': [
          {'title': '第一章 起始', 'url': 'https://a.com/c1'},
          {'title': '第二章 发展', 'url': 'https://a.com/c2'},
        ],
      };

  /// 构造一个验证通过的 OcrRestoreService mock
  ///
  /// restorePuaInText：把 `\u{E000}` 替换成 CJK 常用字「字」，
  /// 返回 `OcrRestoreResult(cleaned, cleaned.length, 1)`，
  /// 模拟 1 个 PUA 码点被 100% 成功还原。
  MockOcrRestoreService goodRestore() {
    final svc = MockOcrRestoreService();
    when(svc.verifyFontFamily(any)).thenAnswer((_) async => true);
    when(svc.restorePuaInText(any, any))
        .thenAnswer((inv) async {
      final t = inv.positionalArguments[0] as String;
      final cleaned = t.replaceAll('\u{E000}', '字');
      return OcrRestoreResult(cleaned, cleaned.length, 1);
    });
    when(svc.readableRatio(any)).thenReturn(1.0);
    return svc;
  }

  group('validateAndPersistScript - 结构校验', () {
    test('content 太短（<50 字）→ content_too_short，不落库', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: '(async function(){...})()',
        jsResult: contentResult(content: '太短啦'),
        repo: repo,
      );

      expect(result['success'], false);
      expect(result['reason'], 'content_too_short');
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('chapter_list 缺 chapters 字段 → chapters_empty', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {'title': '无章节字段'},
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'chapters_empty');
    });

    test('chapter_list 章节缺 title → chapter_missing_field', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {
          'title': '书',
          'chapters': [
            {'url': 'https://a.com/c1'}, // 缺 title
            {'title': '第二章', 'url': 'https://a.com/c2'},
          ],
        },
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'chapter_missing_field');
    });

    test('chapter_list 缺 cover_url 字段 → cover_url_missing', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {
          'title': '书',
          'chapters': [
            {'title': '第一章', 'url': 'https://a.com/c1'},
          ],
          // 故意不写 cover_url
        },
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'cover_url_missing');
      // diagnostic + suggestion 提示如何修
      expect(result['suggestion'], contains('og:image'));
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('chapter_list coverUrl(camelCase) 也通过校验（snake/camel 兜底）', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_cv', reason: null));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {
          'title': '书',
          'coverUrl': 'https://a.com/cover.jpg', // camelCase 兜底
          'font_family': 'ListFont',
          'chapters': [
            {'title': '第一章', 'url': 'https://a.com/c1'},
          ],
        },
        repo: repo,
      );
      expect(result['success'], true);
    });

    test('chapter_list cover_url 为空串（确实无封面）→ 落库通过', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_empty_cv', reason: null));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {
          'title': '书',
          'cover_url': '', // 空串：确实无封面
          'font_family': 'ListFont',
          'chapters': [
            {'title': '第一章', 'url': 'https://a.com/c1'},
          ],
        },
        repo: repo,
      );
      expect(result['success'], true);
    });

    test('bookshelf novels 非空 + 字段齐全（含 cover_url）→ 落库通过', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_bs_ok', reason: null));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'bookshelf',
        scriptJs: 'js',
        jsResult: {
          'novels': [
            {
              'title': '斗破苍穹',
              'url': 'https://a.com/book/1/',
              'cover_url': 'https://a.com/img/1.jpg',
            },
            {
              'title': '凡人修仙传',
              'url': 'https://a.com/book/2/',
              'cover_url': '', // 无封面图时允许空串
            },
          ],
        },
        repo: repo,
      );
      expect(result['success'], true);
      expect(result['domain'], 'a.com');
      expect(result['script_type'], 'bookshelf');
      expect(result['ocr'], false); // bookshelf 无运行时还原路径，恒不触发
      verify(repo.updateScriptPart(
        domain: 'a.com',
        scriptType: 'bookshelf',
        scriptJs: 'js',
        ocr: false,
      )).called(1);
    });

    test('bookshelf 某项缺 cover_url 键 → novel_cover_url_missing', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'bookshelf',
        scriptJs: 'js',
        jsResult: {
          'novels': [
            {'title': '有封面', 'url': 'https://a.com/1', 'cover_url': ''},
            {'title': '漏封面', 'url': 'https://a.com/2'}, // 没.cover_url 键
          ],
        },
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'novel_cover_url_missing');
    });

    test('bookshelf 缺 novels 字段 → novels_empty', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'bookshelf',
        scriptJs: 'js',
        jsResult: {'title': '无 novels 字段'},
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'novels_empty');
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('bookshelf novels 空数组 → novels_empty', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'bookshelf',
        scriptJs: 'js',
        jsResult: {'novels': []},
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'novels_empty');
    });

    test('bookshelf 某项缺 title 或 url → novel_missing_field', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'bookshelf',
        scriptJs: 'js',
        jsResult: {
          'novels': [
            {'title': '正常', 'url': 'https://a.com/1'},
            {'title': '缺 url'}, // 没 url 字段
          ],
        },
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'novel_missing_field');
    });

    test('jsResult 非 Map → invalid_structure', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: 'not_a_map',
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'invalid_structure');
    });

    test('chapter_content 缺 font_family → font_family_missing（v48 起无条件必填）', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: {
          'content': longContent,
          'title': '第一章',
          // 故意不写 font_family
        },
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'font_family_missing');
    });

    test('chapter_list 缺 font_family → font_family_missing（v48 起无条件必填）', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {
          'title': '书',
          'cover_url': 'https://a.com/cover.jpg',
          'chapters': [
            {'title': '第一章', 'url': 'https://a.com/c1'},
          ],
          // 故意不写 font_family
        },
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'font_family_missing');
    });
  });

  group('validateAndPersistScript - OCR 自动检测与验证', () {
    test('含 PUA 且字体无效 → font_family_invalid，不落库', () async {
      final repo = MockSiteScriptRepository();
      final svc = MockOcrRestoreService();
      when(svc.verifyFontFamily(any)).thenAnswer((_) async => false);

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: contentResult(content: puaContent),
        repo: repo,
        restoreService: svc,
      );
      expect(result['success'], false);
      expect(result['reason'], 'font_family_invalid');
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('含 PUA 且 readable_ratio<阈值(0.75) → readable_ratio_below_threshold', () async {
      final repo = MockSiteScriptRepository();
      final svc = MockOcrRestoreService();
      when(svc.verifyFontFamily(any)).thenAnswer((_) async => true);
      // restorePuaInText 返回 4 个全 □，readableRatio 返 0
      when(svc.restorePuaInText(any, any))
          .thenAnswer((_) async => OcrRestoreResult('□□□□', 0, 4));
      when(svc.readableRatio('□□□□')).thenReturn(0.0);

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: contentResult(content: puaContent),
        repo: repo,
        restoreService: svc,
      );
      expect(result['success'], false);
      expect(result['reason'], 'readable_ratio_below_threshold');
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('文本无 PUA → 不走 OCR 验证直接落库（ocr=false），restoreService 不被调', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_nopua', reason: null));
      final svc = MockOcrRestoreService();
      // 即便字体无效也不该被问到：无 PUA 就不该走 OCR 验证
      when(svc.verifyFontFamily(any)).thenAnswer((_) async => false);

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        // 72 字无 PUA 纯正常正文（>=50 下限以满足结构校验）
        jsResult: contentResult(),
        repo: repo,
        restoreService: svc,
      );

      expect(result['success'], true);
      expect(result['ocr'], false);
      expect(result.containsKey('ocr_applied'), isFalse);
      verifyNever(svc.verifyFontFamily(any));
      verify(repo.updateScriptPart(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        ocr: false,
      )).called(1);
    });

    test('含 PUA 但未注入 restoreService → restore_service_missing，不落库', () async {
      final repo = MockSiteScriptRepository();
      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: contentResult(content: puaContent),
        repo: repo,
        // restoreService 缺省为 null
      );
      expect(result['success'], false);
      expect(result['reason'], 'restore_service_missing');
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('chapter_list 标题含 1 个 PUA → 触发 OCR 验证并落库 ocr=true', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_list_pua', reason: null));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {
          'title': '书名\u{E001}',
          'cover_url': 'https://a.com/cover.jpg',
          'font_family': 'ListFont',
          'chapters': [
            {'title': '第一章 起始', 'url': 'https://a.com/c1'},
          ],
        },
        repo: repo,
        restoreService: goodRestore(),
      );

      expect(result['success'], true);
      expect(result['ocr'], true);
      expect(result['ocr_applied'], true);
    });

    // PUA-B (U+F0000-FFFFD) 也视为 PUA，自动检测不漏判。
    // 延续 F4 修复：isPua 覆盖全部 3 段 PUA 范围。
    test('chapter_list 标题含 PUA-B (U+0xF0000) → 触发 OCR 验证并落库', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_list_pua_b', reason: null));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'js',
        jsResult: {
          'title': '书名${String.fromCharCode(0xF0000)}',
          'cover_url': 'https://a.com/cover.jpg',
          'font_family': 'ListFont',
          'chapters': [
            {'title': '第一\u{D800}章', 'url': 'https://a.com/c1'},
          ],
        },
        repo: repo,
        restoreService: goodRestore(),
      );

      expect(result['success'], true);
      expect(result['ocr'], true);
    });
  });

  group('validateAndPersistScript - OCR 验证异常', () {
    test('verifyFontFamily 抛 TimeoutException → ocr_verify_timeout，不落库', () async {
      final repo = MockSiteScriptRepository();
      final svc = MockOcrRestoreService();
      // 模拟 OCR-JS 的 document.fonts.ready 在冷启动页面 30s 内未 resolve，
      // _renderPuaViaController 的 .timeout(30s) 抛 TimeoutException 冒泡到 verifyFontFamily
      when(svc.verifyFontFamily(any)).thenThrow(
        TimeoutException('callAsyncJavaScript 超时', const Duration(seconds: 30)),
      );

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: contentResult(content: puaContent),
        repo: repo,
        restoreService: svc,
      );

      expect(result['success'], false);
      expect(result['reason'], 'ocr_verify_timeout');
      expect(result['ocr_applied'], true);
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('restorePuaInText 抛 TimeoutException → 同样转 ocr_verify_timeout', () async {
      // verifyFontFamily 通过后，restorePuaInText 渲染正文大量 PUA 时单字超时冒泡
      final repo = MockSiteScriptRepository();
      final svc = MockOcrRestoreService();
      when(svc.verifyFontFamily(any)).thenAnswer((_) async => true);
      when(svc.restorePuaInText(any, any)).thenThrow(
        TimeoutException('callAsyncJavaScript 超时', const Duration(seconds: 30)),
      );

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: contentResult(content: puaContent),
        repo: repo,
        restoreService: svc,
      );

      expect(result['success'], false);
      expect(result['reason'], 'ocr_verify_timeout');
      verifyNever(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      ));
    });

    test('restorePuaInText 抛 StateError（模型未加载）→ 转 internal_error 不闪退', () async {
      // 模拟 OcrPredictor._session 为 null 时 recognizeImage 抛 StateError，
      // 在 restorePuaInText 内 catch 后 decodedCount=0 → decodedRatio=0 < 0.8
      // → decoded_ratio_below_threshold，不会冒泡到外层。
      final repo = MockSiteScriptRepository();
      final svc = MockOcrRestoreService();
      when(svc.verifyFontFamily(any)).thenAnswer((_) async => true);
      // 模拟：所有 PUA 都渲染/识别失败，返回 decodedCount=0
      when(svc.restorePuaInText(any, any))
          .thenAnswer((_) async => OcrRestoreResult('□□□□', 0, 4));
      when(svc.readableRatio('□□□□')).thenReturn(0.0);

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: contentResult(content: puaContent),
        repo: repo,
        restoreService: svc,
      );

      // 不应闪退，应优雅返回 readable_ratio_below_threshold
      expect(result['success'], false);
      expect(result['reason'], anyOf('readable_ratio_below_threshold', 'decoded_ratio_below_threshold'));
    });
  });

  group('validateAndPersistScript - 落库', () {
    test('含 PUA 全部验证通过 → 落库成功，ocr=true（保存时实测记录）', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_1', reason: null));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_content',
        scriptJs: 'script_js_content',
        jsResult: contentResult(content: puaContent),
        repo: repo,
        restoreService: goodRestore(),
      );

      expect(result['success'], true);
      expect(result['domain'], 'a.com');
      expect(result['script_type'], 'chapter_content');
      expect(result['ocr'], true);
      expect(result['ocr_applied'], true);
      final captured = verify(repo.updateScriptPart(
        domain: captureAnyNamed('domain'),
        scriptType: captureAnyNamed('scriptType'),
        scriptJs: captureAnyNamed('scriptJs'),
        ocr: captureAnyNamed('ocr'),
      )).captured;
      expect(captured[0], 'a.com');
      expect(captured[1], 'chapter_content');
      expect(captured[2], 'script_js_content');
      expect(captured[3], true);
    });

    test('无 PUA 的 chapter_list 结构通过 → 直接落库（不调 restoreService）', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async => (success: true, id: 'site_2', reason: null));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'a.com',
        scriptType: 'chapter_list',
        scriptJs: 'script_js_list',
        jsResult: listResult(),
        repo: repo,
      );

      expect(result['success'], true);
      expect(result['domain'], 'a.com');
      expect(result['script_type'], 'chapter_list');
      expect(result['ocr'], false);
      expect(result.containsKey('ocr_applied'), isFalse);

      final captured = verify(repo.updateScriptPart(
        domain: captureAnyNamed('domain'),
        scriptType: captureAnyNamed('scriptType'),
        scriptJs: captureAnyNamed('scriptJs'),
        ocr: captureAnyNamed('ocr'),
      )).captured;
      expect(captured[0], 'a.com');
      expect(captured[1], 'chapter_list');
      expect(captured[3], false);
    });

    test('repo 返回失败 reason → 透传失败，不抛', () async {
      final repo = MockSiteScriptRepository();
      when(repo.updateScriptPart(
        domain: anyNamed('domain'),
        scriptType: anyNamed('scriptType'),
        scriptJs: anyNamed('scriptJs'),
        ocr: anyNamed('ocr'),
      )).thenAnswer((_) async =>
          (success: false, id: null, reason: 'persistence_error'));

      final result = await WebViewExtractScenario.validateAndPersistScript(
        domain: 'not.exist',
        scriptType: 'chapter_content',
        scriptJs: 'js',
        jsResult: contentResult(),
        repo: repo,
      );
      expect(result['success'], false);
      expect(result['reason'], 'persistence_error');
      expect(result['domain'], 'not.exist');
      // domain_not_found 已不再返回（updateScriptPart 自动 INSERT），
      // suggestion 文案不再暗示"必须先调 chapter_list"。
      expect(result['suggestion'], isNot(contains('chapter_list')));
    });
  });
}

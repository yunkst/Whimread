/// WebView 提取场景的脚本静态校验 + 落库编排
///
/// 从 `WebViewExtractScenario` 抽出的独立职责：接收「已执行的 JS 结果」，
/// 完成结构校验 → （ocr=true 时）OCR 验证 → 落库三步，返回结构化诊断。
///
/// 核心入口 [WebViewExtractScriptValidator.validateAndPersistScript] 为纯静态
/// 函数，repo/restoreService 均注入，可脱离 WebView 平台依赖做单测
/// （见 save_script_tool_test.dart）。
library;

import 'dart:async';

import 'package:novel_app/repositories/site_script_repository.dart';
import 'package:novel_app/services/ocr_restore_service.dart';

import 'webview_extract_ocr_validator.dart';

/// 提取脚本校验 + 落库编排器（纯静态）
abstract final class WebViewExtractScriptValidator {
  /// 验证脚本结果并落库（可单测，绕开 WebView 平台依赖）。
  ///
  /// 接收"已执行的 JS 结果"（jsResult，由 executor 通过 callAsyncJavaScript
  /// 调用并 jsonDecode 后传入），完成：
  /// 1. 结构校验（[_validateScriptResult]）
  /// 2. ocr=true → OCR 验证（[WebViewExtractOcrValidator.validate]）
  /// 3. 全通过 → [SiteScriptRepository.updateScriptPart] 落库
  ///
  /// 返回值（始终为 Map，executor 再 jsonEncode）：
  /// - 失败：`{success: false, reason, diagnostic, suggestion, ...}`
  /// - 成功：`{success: true, domain, script_type, ocr, [ocr_applied], ...}`
  static Future<Map<String, dynamic>> validateAndPersistScript({
    required String domain,
    required String scriptType,
    required bool ocr,
    required String scriptJs,
    required dynamic jsResult,
    required SiteScriptRepository repo,
    OcrRestoreService? restoreService,
    String? testUrl,
    String? displayName,
    int? preferredMode,
  }) async {
    // 1. 结构校验
    final structErr = _validateScriptResult(jsResult, scriptType, ocr);
    if (structErr != null) {
      return {
        'success': false,
        ...structErr,
        'returned_sample': _sample(jsResult),
      };
    }

    // 2. OCR 验证（ocr=true 时强制走）
    if (ocr) {
      // 2.0 前置闸：ocr=true 必须见到 PUA 码点，否则直接拒绝（避免 agent 误传 true 走无谓 OCR 流程）
      final ocrTargetText = WebViewExtractOcrValidator.extractOcrTargetText(jsResult, scriptType);
      if (!WebViewExtractOcrValidator.containsPrivateUseArea(ocrTargetText)) {
        return {
          'success': false,
          'reason': 'ocr_no_pua',
          // TODO(ocr_applied 语义): 此字段在拒绝路径上返回 true 但 OCR 实际未执行（闸先于 OCR 运行）。
          // 与本文件 font_family_missing 不返回 ocr_applied 的惯例不一致；无消费方从失败路径读取，待后续统一语义。
          'ocr_applied': true,
          'diagnostic': 'ocr=true 但脚本返回文本中未检测到 PUA 码点（U+E000-F8FF），不符合字体反爬判定条件',
          'suggestion': '请重新确认该站点是否真的有字体反爬。若确认无 PUA，调用 save_script 时传 ocr=false；'
              '若应该有 PUA 但检测失败，请检查脚本是否正确返回了带 PUA 的原始文本（不要在 JS 里替换）',
        };
      }

      if (restoreService == null) {
        return {
          'success': false,
          'reason': 'restore_service_missing',
          'diagnostic': 'ocr=true 但 restoreService 未注入（实现错误）',
        };
      }
      final fontFamily = _extractFontFamily(jsResult);
      // OCR 验证内部单字渲染的 callAsyncJavaScript 带 30s 超时
      // （ocr_render_js.dart 模板首行 await document.fonts.ready 在冷启动页面
      // 上等字体下载，常 >30s）。这里单独捕获 TimeoutException 转 ocr_verify_timeout，
      // 避免冒泡到 save_script 外层 on TimeoutException 被误报成 "主脚本 120s 超时"。
      // 仅 catch TimeoutException：OCR 渲染失败抛的 Exception 仍冒泡走 internal_error。
      Map<String, dynamic>? ocrErr;
      try {
        ocrErr = await WebViewExtractOcrValidator.validate(restoreService, fontFamily, jsResult, scriptType);
      } on TimeoutException {
        return {
          'success': false,
          'reason': 'ocr_verify_timeout',
          'ocr_applied': true,
          'message': 'OCR 验证阶段单字渲染超时(>30s)，通常因 save_script 冷启动页面后 @font-face 字体未下载完',
          'diagnostic': 'document.fonts.ready 在 loadUrl(test_url) 之后未及时 resolve',
          'suggestion': '这是字体冷加载耗时导致的误报，非提取脚本缺陷。'
              '脚本本身已通过 execute_js 验证；若频繁出现，后续会在 loadUrl 后显式等 fonts.ready 再触发 OCR 验证',
        };
      }
      if (ocrErr != null) {
        return {'success': false, ...ocrErr};
      }
    }

    // 3. 落库
    final saveResult = await repo.updateScriptPart(
      domain: domain,
      scriptType: scriptType,
      scriptJs: scriptJs,
      ocr: ocr,
      testUrl: testUrl,
      displayName: displayName,
      preferredMode: preferredMode,
    );
    if (!saveResult.success) {
      // 防御性兜底：updateScriptPart 现在不再返回 domain_not_found（domain 不存在
      // 会自动 INSERT）。理论上 success 恒为 true（异常已在 save_script 外层 catch），
      // 此分支仅留作 repo 未来引入新失败 reason 时的透传。
      return {
        'success': false,
        'reason': saveResult.reason ?? 'unknown',
        'domain': domain,
        'suggestion': '脚本落库失败，请检查 domain 是否正确后重试',
      };
    }

    return {
      'success': true,
      'domain': domain,
      'script_type': scriptType,
      'ocr': ocr,
      'id': saveResult.id,
      if (ocr) 'ocr_applied': true,
    };
  }

  /// 结构校验：返回 null 表示通过，否则返回含 reason/diagnostic/suggestion 的 map。
  ///
  /// chapter_list 校验：`chapters` 必须是非空 List，每项 title/url 非空；
  /// `cover_url`（或 coverUrl）字段必须存在（String，允许空串），缺失视为
  /// 脚本未按要求提供封面图，拒绝落库（reason=cover_url_missing）。
  /// chapter_content 校验：`content` 长度 >= 50；ocr=true 时 `font_family` 非空。
  /// bookshelf 校验：`novels` 必须是非空 List，每项 title/url 非空。OCR 不适用。
  static Map<String, dynamic>? _validateScriptResult(
    dynamic data,
    String scriptType,
    bool ocr,
  ) {
    if (data is! Map) {
      return {
        'reason': 'invalid_structure',
        'diagnostic': '脚本返回非对象（期望 {title, content/chapters}）',
        'suggestion': '脚本最后应 return JSON.stringify({title:..., content:...})',
      };
    }

    if (scriptType == 'chapter_list') {
      final chapters = data['chapters'];
      if (chapters is! List || chapters.isEmpty) {
        return {
          'reason': 'chapters_empty',
          'diagnostic': 'chapters 为空或非数组',
          'suggestion': '检查目录选择器是否匹配到章节列表',
        };
      }
      for (final c in chapters) {
        if (c is! Map ||
            ((c['title'] as String?) ?? '').isEmpty ||
            ((c['url'] as String?) ?? '').isEmpty) {
          return {
            'reason': 'chapter_missing_field',
            'diagnostic': '某 chapter 缺少 title 或 url',
            'suggestion': '每个 chapter 必须有非空 title 和 url',
          };
        }
      }
      // cover_url / coverUrl（snake/camel 兜底）。缺 key 直接拒（避免脚本忘记
      // 提供封面图），空串允许（目录页确实无封面时返回 ''）。两种异常输入
      // （null/非字符串）按缺 key 处理，确保返回 JSON 结构可控。
      final coverRaw = data['cover_url'] ?? data['coverUrl'];
      if (coverRaw is! String) {
        return {
          'reason': 'cover_url_missing',
          'diagnostic': '脚本返回缺少 cover_url 字段（应返回封面图 URL 或空串）',
          'suggestion': '在脚本末尾加 cover_url 提取：'
              'const og = document.querySelector(\'meta[property="og:image"]\'); '
              'const cover = og?.content || document.querySelector(\'.book-img, #bookImg, .cover img\')?.src || \'\'; '
              'const coverUrl = cover ? new URL(cover, PAGE_URL).href : \'\'; '
              '返回 {title, cover_url: coverUrl, chapters:[...]}',
        };
      }
      return null;
    }

    if (scriptType == 'bookshelf') {
      final novels = data['novels'];
      if (novels is! List || novels.isEmpty) {
        return {
          'reason': 'novels_empty',
          'diagnostic': 'novels 为空或非数组',
          'suggestion': '确认当前页面是「我的书架/收藏」页，检查书架列表选择器是否匹配',
        };
      }
      for (final n in novels) {
        if (n is! Map ||
            ((n['title'] as String?) ?? '').isEmpty ||
            ((n['url'] as String?) ?? '').isEmpty) {
          return {
            'reason': 'novel_missing_field',
            'diagnostic': '某 novel 缺少 title 或 url',
            'suggestion': '每个 novel 必须有非空 title 和 url（小说目录页路径）',
          };
        }
      }
      // cover_url 封面槽位（可选能力、必填键）：与 chapter_list 同语义——
      // 键必须存在且为字符串（空串允许，书架页确实无封面图时返回 ''），
      // 防止脚本作者漏提取；解析/同步侧仍按可选处理，兼容旧脚本。
      for (final n in novels) {
        if (n is Map && (n['cover_url'] ?? n['coverUrl']) is! String) {
          return {
            'reason': 'novel_cover_url_missing',
            'diagnostic': '某 novel 缺少 cover_url 字段（封面槽位，可为空串）',
            'suggestion': '每本 novel 加 cover_url 提取：'
                'const img = 条目元素.querySelector(\'img\'); '
                'const coverUrl = img ? new URL(img.dataset.src || img.dataset.original || img.src, PAGE_URL).href : \'\'; '
                '返回 {title, url, cover_url: coverUrl}',
          };
        }
      }
      return null;
    }

    // chapter_content
    final content = ((data['content'] as String?) ?? '').trim();
    if (content.length < 50) {
      return {
        'reason': 'content_too_short',
        'diagnostic': 'content 长度 ${content.length} < 50，可能选择器没匹配正文',
        'suggestion': '检查正文选择器，或等待页面加载完成再提取',
      };
    }
    if (ocr) {
      final ff = _extractFontFamily(data);
      if (ff.isEmpty) {
        return {
          'reason': 'font_family_missing',
          'diagnostic': 'OCR 模式下 chapter_content 脚本必须返回 font_family',
          'suggestion': '在脚本里加 const ff = getComputedStyle(正文元素).fontFamily; '
              '返回 {title, content, font_family: ff}',
        };
      }
    }
    return null;
  }

  /// 从 jsResult 中取 font_family（snake/camel 兜底）。
  static String _extractFontFamily(dynamic data) {
    if (data is! Map) return '';
    final v = data['font_family'] ?? data['fontFamily'];
    if (v is! String) return '';
    return v.trim();
  }

  /// 截取结果摘要（最多 200 字），用于诊断返回。
  static String _sample(dynamic data) {
    final s = data.toString();
    return s.length > 200 ? '${s.substring(0, 200)}...' : s;
  }
}

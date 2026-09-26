/// WebView 提取场景的 OCR 校验
///
/// 从 `WebViewExtractScenario` 抽出的独立职责：save_script 落库前的
/// OCR（字体反爬）验证链路——PUA 码点探测、目标文本提取、
/// 字体有效性 + 还原可读率/解码率校验。
///
/// 依赖 [OcrRestoreService]（注入），本身不持有 WebView。
library;

import 'package:novel_app/services/ocr_restore_service.dart';

/// OCR（字体反爬）验证器（纯静态）
abstract final class WebViewExtractOcrValidator {
  /// OCR 还原后 CJK 占比通过阈值。
  ///
  /// readableRatio 分母含中文标点/数字/空白（只数 0x4E00-0x9FFF 基本区汉字），
  /// 正常中文小说正文标点占 15-20%，"完美还原"的天花板约 0.80-0.85。原 0.85
  /// 阈值卡在天花板上，导致番茄等标点密集站点反复卡在 save_script 校验。
  /// 0.75 既能放行正常还原（实测 0.81-0.83），又能拦住识别真差（<0.7 乱码）。
  static const readableRatioThreshold = 0.75;

  /// OCR 验证：字体有效性 + PUA 还原 + 可读率/解码率达标。
  ///
  /// 返回 null 表示通过；否则返回含 reason 的诊断 map（均带 ocr_applied=true）。
  ///
  /// 1. `verifyFontFamily` 失败 → `font_family_invalid`
  /// 2. `restorePuaInText` 后 `readableRatio < readableRatioThreshold(0.75)` → `readable_ratio_below_threshold`
  /// 3. 有 PUA 但 `decodedRatio < 0.8` → `decoded_ratio_below_threshold`
  static Future<Map<String, dynamic>?> validate(
    OcrRestoreService svc,
    String fontFamily,
    dynamic data,
    String scriptType,
  ) async {
    if (!await svc.verifyFontFamily(fontFamily)) {
      return {
        'reason': 'font_family_invalid',
        'ocr_applied': true,
        'font_family': fontFamily,
        'diagnostic': '该 font_family 渲染不同 PUA 产生相同占位框，字体族名无效或未加载',
        'suggestion': '确认 getComputedStyle 取的是正文元素且字体已加载；检查 font-family 值',
      };
    }

    // 拼接待还原文本：content 或 title+chapters[].title
    final textToRestore = scriptType == 'chapter_content'
        ? ((data['content'] as String?) ?? '')
        : '${data['title'] ?? ''} ${(data['chapters'] as List?)?.map((c) => c['title'] ?? '').join(' ')}';

    final restored = await svc.restorePuaInText(textToRestore, fontFamily);
    final ratio = svc.readableRatio(restored.text);
    if (ratio < readableRatioThreshold) {
      return {
        'reason': 'readable_ratio_below_threshold',
        'ocr_applied': true,
        'readable_ratio': ratio,
        'decoded_ratio': restored.decodedRatio,
        'diagnostic': 'OCR 还原后 CJK 占比过低，font_family 可能无效或模型解码失败',
        'suggestion': '检查 font_family 是否正确（用 getComputedStyle(正文元素).fontFamily）',
      };
    }
    if (restored.totalPuaCount > 0 && restored.decodedRatio < 0.8) {
      return {
        'reason': 'decoded_ratio_below_threshold',
        'ocr_applied': true,
        'decoded_ratio': restored.decodedRatio,
        'total_pua': restored.totalPuaCount,
        'diagnostic': 'PUA 识别成功率 < 80%',
        'suggestion': '模型对该字体解码效果差，可考虑 LLM 兜底（非本期）',
      };
    }
    return null; // 通过
  }

  /// 检查文本中是否含 PUA 私用区码点。阈值 ≥1 即视为存在字体反爬特征。
  ///
  /// 委托给 [isPua]（ocr_restore_service.dart），覆盖 PUA-A/B/C 三段，
  /// 与运行时 OCR 管道对齐。避免旧实现仅检查 PUA-A 导致 PUA-B/C 误判。
  /// 用 text.runes 逐码点比较，避免在源码字面量里嵌入 PUA 字符（OCR 测试不友好）。
  static bool containsPrivateUseArea(String text) {
    return text.runes.any(isPua);
  }

  /// 从 jsResult 提取 OCR 模式需要扫描 PUA 的目标文本。
  ///
  /// - chapter_content: 直接取 content
  /// - chapter_list: 拼接 title + 所有 chapters[].title（小说名 + 章名里也可能含 PUA）
  /// - bookshelf: 无 PUA 需求，返回空串（bookshelf 在 save_script 已强制 ocr=false，
  ///   此处仅为防御兜底：万一有人手动构造调用时返回空字符串，闸会拒落库）
  static String extractOcrTargetText(dynamic jsResult, String scriptType) {
    if (jsResult is! Map) return '';
    if (scriptType == 'chapter_content') {
      return ((jsResult['content'] as String?) ?? '');
    }
    if (scriptType == 'bookshelf') {
      return '';
    }
    final title = (jsResult['title'] as String?) ?? '';
    final chapters = jsResult['chapters'];
    final chapterTitles = chapters is List
        ? chapters
            .whereType<Map>()
            .map((c) => (c['title'] as String?) ?? '')
            .join(' ')
        : '';
    return '$title $chapterTitles';
  }
}

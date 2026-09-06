/// OCR 还原服务：对文本中出现的 PUA（私用区）码点走 PP-OCRv6 识别还原。
///
/// 设计背景：番茄小说等站点用 PUA 码点 + @font-face 自定义字体做反爬，
/// DOM innerText 是乱码。本服务对 PUA 逐字 canvas 渲染 -> 识别 -> 替换。
///
/// 本文件含纯函数 [isPua] 与 [OcrRestoreService] 类。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/ocr_providers.dart';
import 'logger_service.dart';

/// 判断码点是否落在 PUA（私用区）三段之一。
/// - U+E000-F8FF   PUA-A
/// - U+F0000-FFFFD PUA-B
/// - U+100000-10FFFD PUA-C
bool isPua(int cp) =>
    (cp >= 0xE000 && cp <= 0xF8FF) ||
    (cp >= 0xF0000 && cp <= 0xFFFFD) ||
    (cp >= 0x100000 && cp <= 0x10FFFD);

/// OCR 还原结果。
class OcrRestoreResult {
  final String text;
  final int decodedCount;
  final int totalPuaCount;
  const OcrRestoreResult(this.text, this.decodedCount, this.totalPuaCount);

  /// PUA 识别成功率（无 PUA 时记 1.0）。
  double get decodedRatio =>
      totalPuaCount == 0 ? 1.0 : decodedCount / totalPuaCount;
}

/// OCR 还原服务：对文本中 PUA 码点逐字 canvas 渲染 -> 识别 -> 替换。
///
/// `_renderPua` 是注入的"渲染单字"回调（由 WebView holder 提供），
/// 让本 service 不耦合具体 WebView 实例，运行时钩子和 save_script 验证共用。
class OcrRestoreService {
  /// 产品构造：通过 Riverpod ref 在需要时读取 [ocrPredictorProvider]。
  /// 适用于 service / scenario 等能直接拿到 [Ref] 的场景。
  OcrRestoreService(this._ref, this._renderPua) : _recognizeFn = null;

  /// 注入构造：直接注入识别函数，绕开 Riverpod [Ref]。
  ///
  /// 适用场景：
  /// - **测试**：单测里没有 ProviderContainer，直接注入 mock/fake 识别函数。
  /// - **Widget 层**：[ConsumerWidget.build] 只能拿到 [WidgetRef]（非 [Ref]），
  ///   无法用上面的产品构造。此构造让 widget 也能复用本 service 的编排逻辑。
  ///
  /// 名字保留 `forTesting` 历史兼容；行为上产品/测试皆可用。
  OcrRestoreService.forTesting({
    required Future<String> Function(int, String) renderPua,
    required Future<String> Function(String) recognizeImageFn,
  })  : _ref = null,
        _renderPua = renderPua,
        _recognizeFn = recognizeImageFn;

  final Ref? _ref;
  final Future<String> Function(int codepoint, String fontFamily) _renderPua;
  final Future<String> Function(String)? _recognizeFn;

  /// 还原 [text] 里所有 PUA 码点（通用入口，content 和 list title 都调它）。
  Future<OcrRestoreResult> restorePuaInText(
    String text,
    String? fontFamily,
  ) async {
    final puaCodepoints = <int>{};
    for (final r in text.runes) {
      if (isPua(r)) puaCodepoints.add(r);
    }
    if (puaCodepoints.isEmpty) {
      return OcrRestoreResult(text, 0, 0);
    }

    final puaToChar = <int, String>{};
    final failedCodepoints = <int>[]; // 聚合失败码点，循环后一条日志
    var loopIdx = 0;
    final totalPua = puaCodepoints.length;
    for (final cp in puaCodepoints) {
      loopIdx++;
      try {
        LoggerService.instance.i(
          'OCR restorePua 循环 [$loopIdx/$totalPua] cp=0x${cp.toRadixString(16)} 渲染开始',
          category: LogCategory.ai,
          tags: ['ocr', 'restore-pua', 'loop-render-begin'],
        );
        final imageBase64 = await _renderPua(cp, fontFamily ?? '');
        LoggerService.instance.i(
          'OCR restorePua 循环 [$loopIdx/$totalPua] cp=0x${cp.toRadixString(16)} 渲染完成 → 识别开始',
          category: LogCategory.ai,
          tags: ['ocr', 'restore-pua', 'loop-render-done'],
        );
        final decoded = await _recognizeImage(imageBase64);
        LoggerService.instance.i(
          'OCR restorePua 循环 [$loopIdx/$totalPua] cp=0x${cp.toRadixString(16)} 识别完成 → "$decoded"',
          category: LogCategory.ai,
          tags: ['ocr', 'restore-pua', 'loop-recognize-done'],
        );
        puaToChar[cp] = decoded;
} catch (e, _) {
        // 单字符失败，留 □。累积失败码点，循环结束后输出一条聚合日志
        // （避免 200+ 个 PUA 码点产生 200 条日志触发 FIFO 淘汰）。
        failedCodepoints.add(cp);
        puaToChar[cp] = ''; // 单字符失败，留 □
      }
    }
    if (failedCodepoints.isNotEmpty) {
      LoggerService.instance.w(
        'OCR 单字还原失败 ${failedCodepoints.length} 个码点: '
        '${failedCodepoints.take(10).map((c) => "0x${c.toRadixString(16)}").join(", ")}'
        '${failedCodepoints.length > 10 ? " ... 等" : ""} '
        'fontFamily=$fontFamily',
        category: LogCategory.ai,
        tags: ['ocr', 'restore-pua', 'char-failed'],
      );
    }

    final sb = StringBuffer();
    for (final r in text.runes) {
      if (isPua(r)) {
        final d = puaToChar[r] ?? '';
        if (d.isNotEmpty) {
          sb.write(d);
        } else {
          sb.write('□');
        }
      } else {
        sb.writeCharCode(r);
      }
    }
    // decodedCount 改码点维度：成功识别的不同 PUA 码点数（与 totalPuaCount 同维度），
    // 避免高频字（如"的"）多次出现导致 decodedRatio > 1.0 违反成功率语义。
    final decoded = puaToChar.values.where((v) => v.isNotEmpty).length;
    return OcrRestoreResult(sb.toString(), decoded, puaCodepoints.length);
  }

  /// 字体有效性探测：用 [fontFamily] 渲染 2 个不同 PUA，字节级差异验证。
  /// 错误字体栈会渲染出相同占位框。
  Future<bool> verifyFontFamily(String fontFamily) async {
    if (fontFamily.isEmpty) return false;
    final a = await _renderPua(0xE3E9, fontFamily);
    final b = await _renderPua(0xE3EA, fontFamily);
    return a != b;
  }

  /// CJK 字符占比（判定 OCR 还原后文本可读性）。
  double readableRatio(String text) {
    if (text.isEmpty) return 0;
    int cjk = 0, total = 0;
    for (final r in text.runes) {
      total++;
      if (r >= 0x4E00 && r <= 0x9FFF) cjk++;
    }
    return cjk / total;
  }

  /// 内部识别抽象：产品实现读 provider，测试实现走注入函数。
  Future<String> _recognizeImage(String base64Png) async {
    if (_recognizeFn != null) return _recognizeFn!(base64Png);
    final ocr = await _ref!.read(ocrPredictorProvider.future);
    return ocr.recognizeImage(base64Png);
  }
}

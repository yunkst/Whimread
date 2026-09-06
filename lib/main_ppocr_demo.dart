/// ⚠️ 本 PoC 入口已被产品化路径替代（OcrPredictor.recognizeImage + OcrRestoreService）。
/// 保留仅作历史参照，不再维护。产品路径见 lib/services/ocr_restore_service.dart。
///
/// PoC 入口：PP-OCRv6 离线识别还原番茄字体反爬正文。
///
/// 流程：
///   1. 加载反爬字体 font.ttf（自定义 family）
///   2. 实例化 OcrPredictor（assets/models/inference.onnx + ppocrv6_dict.txt）
///   3. 对 pua_list.json 里每个 PUA 码点：识别 → 构建 {pua: 真字} 映射
///   4. 读 chapter_raw_text.txt，用映射表替换 PUA → 还原正文
///   5. 输出还原正文 + 统计 + 映射表样本
///
/// 用法：flutter run -t lib/main_ppocr_demo.dart -d device
///
/// 与 fanqie-evidence/ppocr_full_decode.py 1:1 移植：
///   - canvasSize=120 / fontSize=80（与 Python 一致）
///   - CJK 判定：U+4E00..U+9FFF 基本区（与 Python `"一" <= ch <= "鿿"` 等价）
///   - mapped / multi / empty / noncjk 分类逻辑同 Python
library;

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'poc/ocr_predictor.dart';

bool isCjk(String ch) {
  if (ch.isEmpty) return false;
  final cp = ch.codeUnitAt(0);
  return cp >= 0x4E00 && cp <= 0x9FFF; // 基本 CJK 区（与 Python "一" <= ch <= "鿿" 等价）
}

/// 本地 TextPainter 渲染 PUA 码点 → base64 PNG（白底黑字，居中）。
/// 与产品路径的区别仅在于渲染位置：产品走 WebView canvas，demo 走 TextPainter。
Future<String> renderPuaToBase64Png(
  int codepoint, {
  required String family,
  required double fontSize,
  required double canvasSize,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);

  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(codepoint),
      style: TextStyle(
        fontFamily: family,
        fontSize: fontSize,
        color: Colors.black,
        decoration: TextDecoration.none,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  tp.layout();
  tp.paint(
    canvas,
    Offset((canvasSize - tp.width) / 2, (canvasSize - tp.height) / 2),
  );

  final picture = recorder.endRecording();
  final rendered =
      await picture.toImage(canvasSize.toInt(), canvasSize.toInt());
  final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
  rendered.dispose();
  picture.dispose();
  return base64Encode(byteData!.buffer.asUint8List());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('[PPOCR] start');

  final sw = Stopwatch()..start();

  // 1. 加载反爬字体 → loadFontFromList 注册自定义 family
  const family = 'FanqieAntiCrawl';
  final fontData = await rootBundle.load('tool/ocr_test_assets/font.ttf');
  await ui.loadFontFromList(fontData.buffer.asUint8List(), fontFamily: family);
  print('[PPOCR] font loaded: $family, ${fontData.lengthInBytes} bytes');

  // 2. 读 PUA 列表
  final puaListStr =
      await rootBundle.loadString('tool/ocr_test_assets/pua_list.json');
  final puaList = (jsonDecode(puaListStr) as List).cast<int>();
  print('[PPOCR] pua count: ${puaList.length}');

  // 3. 读 DOM 原文（带 PUA）
  final rawText =
      await rootBundle.loadString('tool/ocr_test_assets/chapter_raw_text.txt');
  print('[PPOCR] raw text length: ${rawText.length}');

  // 4. 实例化 + 加载 OcrPredictor
  final ocr = OcrPredictor();
  await ocr.load();
  print('[PPOCR] ocr loaded: isLoaded=${ocr.isLoaded}');

  // 5. 逐个 PUA 识别 → 构建映射表（分类与 ppocr_full_decode.py 一致）
  final map = <int, String>{};
  int mappedCount = 0;
  int multiCount = 0;
  int emptyCount = 0;
  int nonCjkCount = 0;

  for (var i = 0; i < puaList.length; i++) {
    final cp = puaList[i];
    // demo 本地渲染（canvasSize=120 / fontSize=80，与 Python 一致）后走产品
    // 推理入口 recognizeImage；OcrPredictor 自身不再承担渲染职责。
    final png = await renderPuaToBase64Png(
      cp,
      family: family,
      fontSize: 80,
      canvasSize: 120,
    );
    final text = await ocr.recognizeImage(png);

    if (text.isEmpty) {
      emptyCount++;
    } else if (text.length == 1 && isCjk(text)) {
      map[cp] = text;
      mappedCount++;
    } else if (text.runes.every((r) => isCjk(String.fromCharCode(r)))) {
      // 多字（全 CJK）—— 取第一个作为映射（与 Python 保守策略一致）
      map[cp] = text[0];
      multiCount++;
    } else {
      nonCjkCount++;
    }

    if ((i + 1) % 50 == 0) {
      print('[PPOCR] progress ${i + 1}/${puaList.length} mapped=$mappedCount');
    }
  }
  print('[PPOCR] decode done: mapped=$mappedCount multi=$multiCount '
      'empty=$emptyCount noncjk=$nonCjkCount / total=${puaList.length}');

  // 6. 还原正文（与 Python 一致：PUA 范围 0xE000..0xF8FF，未识别用 □ 占位）
  final sb = StringBuffer();
  int hit = 0, miss = 0;
  for (final r in rawText.runes) {
    if (r >= 0xE000 && r <= 0xF8FF) {
      final real = map[r];
      if (real != null) {
        sb.write(real);
        hit++;
      } else {
        sb.write('□');
        miss++;
      }
    } else {
      sb.writeCharCode(r);
    }
  }
  final restored = sb.toString();

  sw.stop();
  print('[PPOCR] elapsed_ms=${sw.elapsedMilliseconds}');
  print('[PPOCR] pua hit=$hit miss=$miss '
      '(hit rate=${(hit * 100 / (hit + miss)).toStringAsFixed(1)}%)');
  print('[PPOCR] ===RESTORED_BEGIN===');
  print(restored);
  print('[PPOCR] ===RESTORED_END===');

  // 7. 映射表样本（前 30 条便于人工核对）
  final sample = map.entries
      .take(30)
      .map((e) => 'U+${e.key.toRadixString(16).toUpperCase()}->${e.value}')
      .join(' ');
  print('[PPOCR] map_sample: $sample');

  await ocr.dispose();

  runApp(MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'PP-OCRv6 PoC done\n'
            'mapped=$mappedCount/${puaList.length} '
            '(multi=$multiCount empty=$emptyCount noncjk=$nonCjkCount)\n'
            'hit=$hit miss=$miss\n'
            'elapsed=${sw.elapsedMilliseconds}ms\n'
            'see logcat [PPOCR] for restored text',
            style: const TextStyle(color: Colors.white, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  ));
}
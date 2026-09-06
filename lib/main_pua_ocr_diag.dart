/// 诊断：用 TextPainter 渲染 PUA 单字，统计非白像素，验证字体加载 + 文字渲染。
/// 加黑方块对照，验证 canvas 本身能写入像素。
/// 用法：flutter run -t lib/main_pua_ocr_diag.dart -d emulator-5554
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('[DIAG] start');

  // 加载反爬字体
  const family = 'FanqieAntiCrawl';
  final fontData = await rootBundle.load('tool/ocr_test_assets/font.ttf');
  await ui.loadFontFromList(fontData.buffer.asUint8List(), fontFamily: family);
  print('[DIAG] font loaded: $family');

  final extDir = await getExternalStorageDirectory();
  print('[DIAG] external dir: ${extDir?.path}');

  final testChars = <String, int>{
    'PUA_E3E8': 0xE3E8,
    'BAI_白': 0x767D,
    'PUA_E41E': 0xE41E,
  };

  for (final entry in testChars.entries) {
    final name = entry.key;
    final char = String.fromCharCode(entry.value);
    final ratio = await _renderAndStat(char, family);
    print('[DIAG] $name ($char): 非白像素 ${ratio.toStringAsFixed(2)}%');
  }

  for (final ch in ['白', 'A']) {
    final ratio = await _renderAndStat(ch, null);
    print('[DIAG] 系统字体 "$ch": 非白像素 ${ratio.toStringAsFixed(2)}%');
  }

  // 黑方块对照：canvas 是否能写
  final blackRatio = await _renderBlackBlock();
  print('[DIAG] 黑方块对照: 非白像素 ${blackRatio.toStringAsFixed(2)}%');

  print('[DIAG] done');
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('diag done, see logcat')))));
}

Future<double> _renderAndStat(String char, String? family) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = 96.0;
  canvas.drawColor(Colors.white, BlendMode.src);
  final tp = TextPainter(
    text: TextSpan(
      text: char,
      style: TextStyle(
        fontFamily: family,
        fontSize: 72,
        color: Colors.black,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  tp.layout();
  tp.paint(canvas, const Offset(12, 12));
  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  int nonWhite = 0;
  final total = size.toInt() * size.toInt();
  for (var i = 0; i < bytes.length; i += 4) {
    if (bytes[i] < 250 || bytes[i + 1] < 250 || bytes[i + 2] < 250) nonWhite++;
  }
  return nonWhite / total * 100;
}

Future<double> _renderBlackBlock() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = 96.0;
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 96, 96),
    Paint()..color = Colors.black,
  );
  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  int nonWhite = 0;
  final total = size.toInt() * size.toInt();
  for (var i = 0; i < bytes.length; i += 4) {
    if (bytes[i] < 250 || bytes[i + 1] < 250 || bytes[i + 2] < 250) nonWhite++;
  }
  return nonWhite / total * 100;
}

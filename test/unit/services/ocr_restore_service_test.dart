import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/ocr_restore_service.dart';

void main() {
  group('OcrRestoreService.restorePuaInText', () {
    test('无 PUA 直接返回原文，decoded=0', () async {
      final svc = _buildService(renderPua: (_, __) async => '');
      final r = await svc.restorePuaInText('正常的中文文本', null);
      expect(r.text, '正常的中文文本');
      expect(r.decodedCount, 0);
      expect(r.totalPuaCount, 0);
    });

    test('PUA 全部识别成功则全部替换', () async {
      // mock renderPua 返回固定 base64；mock predictor 识别返回 "字"
      final svc = _buildService(
        renderPua: (cp, _) async => 'mock_b64_$cp',
        recognizeImage: (_) async => '字',
      );
      final text = '前${String.fromCharCode(0xE3E8)}后${String.fromCharCode(0xE3E9)}';
      final r = await svc.restorePuaInText(text, 'F');
      expect(r.totalPuaCount, 2);
      expect(r.decodedCount, 2);
      expect(r.text, '前字后字');
    });

    test('单个 PUA 识别失败留 □ 不中断', () async {
      // 注：cp 是 int，'mock_$cp' 走十进制插值；recognizeImage 比较时
      // 用 ${0xE3E8} 表达同一码点（同样十进制插值），保证两侧自洽。
      final svc = _buildService(
        renderPua: (cp, _) async => 'mock_$cp',
        recognizeImage: (b64) async => b64 == 'mock_${0xE3E8}' ? '字' : '',
      );
      final text = '${String.fromCharCode(0xE3E8)}X${String.fromCharCode(0xE3E9)}';
      final r = await svc.restorePuaInText(text, 'F');
      expect(r.totalPuaCount, 2);
      expect(r.decodedCount, 1);
      expect(r.text, '字X□');
    });

    test('renderPua 抛异常该字符留 □', () async {
      final svc = _buildService(
        renderPua: (cp, _) async {
          if (cp == 0xE3E8) throw Exception('render fail');
          return 'ok';
        },
        recognizeImage: (_) async => '字',
      );
      final text = '${String.fromCharCode(0xE3E8)}${String.fromCharCode(0xE3E9)}';
      final r = await svc.restorePuaInText(text, 'F');
      expect(r.text, '□字');
      expect(r.decodedCount, 1);
    });

    test('recognizeImage 抛 StateError（模型未加载）该字符留 □ 不闪退', () async {
      final svc = _buildService(
        renderPua: (cp, _) async => 'mock_b64_$cp',
        recognizeImage: (_) async => throw StateError('OCR 模型尚未加载完成'),
      );
      final text = '${String.fromCharCode(0xE3E8)}${String.fromCharCode(0xE3E9)}';
      final r = await svc.restorePuaInText(text, 'F');
      // 不应闪退：两个 PUA 都失败留 □，decodedCount=0
      expect(r.text, '□□');
      expect(r.decodedCount, 0);
      expect(r.totalPuaCount, 2);
    });

    test('重复 PUA：decodedCount 按码点去重，decodedRatio 不超 1.0', () async {
      final svc = _buildService(
        renderPua: (cp, _) async => 'mock_$cp',
        recognizeImage: (_) async => '字',
      );
      // 同一 PUA 0xE3E8 出现两次
      final text = '前${String.fromCharCode(0xE3E8)}中${String.fromCharCode(0xE3E8)}后';
      final r = await svc.restorePuaInText(text, 'F');
      expect(r.totalPuaCount, 1);       // 去重 1 个码点
      expect(r.decodedCount, 1);        // 码点维度，不重复计
      expect(r.decodedRatio, 1.0);      // 不超 1.0
      expect(r.text, '前字中字后');      // 两次出现都替换
    });
  });

  group('verifyFontFamily', () {
    test('空字体族返回 false', () async {
      final svc = _buildService(renderPua: (_, __) async => '');
      expect(await svc.verifyFontFamily(''), isFalse);
    });

    test('两个 PUA 渲染结果不同 -> true', () async {
      final svc = _buildService(
        renderPua: (cp, _) async => 'img_$cp',
      );
      expect(await svc.verifyFontFamily('RealFont'), isTrue);
    });

    test('两个 PUA 渲染结果相同（占位框）-> false', () async {
      final svc = _buildService(
        renderPua: (_, __) async => 'same_box', // 恒返回相同
      );
      expect(await svc.verifyFontFamily('BadFont'), isFalse);
    });
  });

  group('readableRatio', () {
    test('全 CJK 为 1.0', () {
      final svc = _buildService(renderPua: (_, __) async => '');
      expect(svc.readableRatio('中文文本'), 1.0);
    });

    test('空文本为 0', () {
      final svc = _buildService(renderPua: (_, __) async => '');
      expect(svc.readableRatio(''), 0);
    });

    test('半 CJK 半非 -> 0.5', () {
      final svc = _buildService(renderPua: (_, __) async => '');
      expect(svc.readableRatio('中A'), closeTo(0.5, 0.01));
    });
  });
}

// ── helper：构造一个注入 mock renderPua + mock predictor 的 service ──
OcrRestoreService _buildService({
  required Future<String> Function(int, String) renderPua,
  Future<String> Function(String base64)? recognizeImage,
}) {
  // OcrRestoreService 内部读 ocrPredictorProvider 拿 predictor；
  // 测试里通过 forTesting 构造直接注入 recognizeImageFn。
  return OcrRestoreService.forTesting(
    renderPua: renderPua,
    recognizeImageFn: recognizeImage ?? (_) async => '',
  );
}

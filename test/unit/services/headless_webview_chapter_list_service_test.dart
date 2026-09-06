/// HeadlessWebViewChapterListService 单元测试
///
/// 覆盖：
/// - restoreChapterListIfNeeded OCR 编排（static @visibleForTesting）
///   - needsOcr=true 还原 title + 每个 chapter.title，url 不动
///   - needsOcr=false 不还原直接返回原 record
///   - restoreService 抛异常降级返回原 record
///
/// 不覆盖（需集成测试）：
/// - fetchChapterList 全链路（_ensureWebView / _loadPage /
///   _executeChapterListScript / _renderPua），依赖 flutter_inappwebview 平台实现。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/services/headless_webview_chapter_list_service.dart';
import 'package:novel_app/services/logger_service.dart';
import 'package:novel_app/services/ocr_restore_service.dart';

// ===== Mock OcrRestoreService =====
//
// restorePuaInText 内部对单字符渲染/识别失败做了 per-codepoint try-catch
// （吞掉异常 + 替换 □），因此用 forTesting + 抛异常的 renderPua 无法触发
// restoreChapterListIfNeeded 的整体降级分支。改用 Mockito 直接 stub
// restorePuaInText 抛异常，才能验证降级路径。
class MockOcrRestoreService extends Mock implements OcrRestoreService {
  @override
  Future<OcrRestoreResult> restorePuaInText(String text, String? fontFamily) =>
      super.noSuchMethod(
        Invocation.method(#restorePuaInText, [text, fontFamily]),
        returnValue: Future<OcrRestoreResult>.value(
          OcrRestoreResult('', 0, 0),
        ),
        returnValueForMissingStub: Future<OcrRestoreResult>.value(
          OcrRestoreResult('', 0, 0),
        ),
      ) as Future<OcrRestoreResult>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LoggerService.resetForTesting();
  });

  // ================================================================
  // restoreChapterListIfNeeded — OCR 编排（static @visibleForTesting）
  //
  // 抽成 static 函数便于在纯 Dart 环境单测 OCR 编排逻辑，
  // 绕开 WebView 平台实现限制（fetchChapterList 走到 _ensureWebView 会抛异常）。
  // ================================================================
  group('restoreChapterListIfNeeded (OCR 编排)', () {
    test('needsOcr=true 还原 title 和每个 chapter.title，url 不动', () async {
      final restore = OcrRestoreService.forTesting(
        renderPua: (cp, _) async => 'mock',
        recognizeImageFn: (_) async => '字',
      );
      final chapters = [
        Chapter(
          title: '第${String.fromCharCode(0xE3E9)}章',
          url: 'https://a.com/1',
          chapterIndex: 0,
        ),
      ];
      final out =
          await HeadlessWebViewChapterListService.restoreChapterListIfNeeded(
        needsOcr: true,
        title: '小${String.fromCharCode(0xE3E8)}说',
        chapters: chapters,
        fontFamily: 'F',
        restoreService: restore,
      );
      expect(out.title, '小字说');
      expect(out.chapters.first.title, '第字章');
      // url 不动
      expect(out.chapters.first.url, 'https://a.com/1');
      // chapterIndex 保留
      expect(out.chapters.first.chapterIndex, 0);
    });

    test('needsOcr=false 不还原直接返回原 record', () async {
      final restore = OcrRestoreService.forTesting(
        renderPua: (_, __) async => '',
        recognizeImageFn: (_) async => 'X',
      );
      final chapters = [
        Chapter(
          title: '第一章',
          url: 'https://a.com/1',
          chapterIndex: 0,
        ),
      ];
      final out =
          await HeadlessWebViewChapterListService.restoreChapterListIfNeeded(
        needsOcr: false,
        title: '小说名',
        chapters: chapters,
        fontFamily: null,
        restoreService: restore,
      );
      expect(out.title, '小说名');
      expect(out.chapters.first.title, '第一章');
      expect(out.chapters.first.url, 'https://a.com/1');
      // 同一引用（短路返回）
      expect(identical(out.chapters, chapters), isTrue);
    });

    test('restoreService 抛异常降级返回原 title 和原 chapters', () async {
      // restorePuaInText 内部吞掉 per-codepoint 异常（替 □），
      // 故用 Mockito 直接 stub restorePuaInText 抛异常验证整体降级分支。
      final restore = MockOcrRestoreService();
      final originalTitle = '小${String.fromCharCode(0xE3E8)}说';
      final originalChapterTitle = '第${String.fromCharCode(0xE3E9)}章';
      final chapters = [
        Chapter(
          title: originalChapterTitle,
          url: 'https://a.com/1',
          chapterIndex: 0,
        ),
      ];
      when(restore.restorePuaInText(originalTitle, 'F'))
          .thenThrow(Exception('restore failed'));
      final out =
          await HeadlessWebViewChapterListService.restoreChapterListIfNeeded(
        needsOcr: true,
        title: originalTitle,
        chapters: chapters,
        fontFamily: 'F',
        restoreService: restore,
      );
      // 降级返回原文
      expect(out.title, originalTitle);
      expect(out.chapters.first.title, originalChapterTitle);
      expect(out.chapters.first.url, 'https://a.com/1');
    });

    test('fontFamily=null 降级返回原 record 不调 restoreService', () async {
      final restore = MockOcrRestoreService();
      final originalTitle = '小${String.fromCharCode(0xE3E8)}说';
      final chapters = [
        Chapter(
          title: '第${String.fromCharCode(0xE3E9)}章',
          url: 'https://a.com/1',
          chapterIndex: 0,
        ),
      ];
      final out =
          await HeadlessWebViewChapterListService.restoreChapterListIfNeeded(
        needsOcr: true,
        title: originalTitle,
        chapters: chapters,
        fontFamily: null,
        restoreService: restore,
      );
      expect(out.title, originalTitle);
      expect(out.chapters.first.title, chapters.first.title);
      verifyNever(restore.restorePuaInText(originalTitle, null));
    });

    test('fontFamily="" 降级返回原 record 不调 restoreService', () async {
      final restore = MockOcrRestoreService();
      final originalTitle = '小${String.fromCharCode(0xE3E8)}说';
      final chapters = [
        Chapter(
          title: '第${String.fromCharCode(0xE3E9)}章',
          url: 'https://a.com/1',
          chapterIndex: 0,
        ),
      ];
      final out =
          await HeadlessWebViewChapterListService.restoreChapterListIfNeeded(
        needsOcr: true,
        title: originalTitle,
        chapters: chapters,
        fontFamily: '',
        restoreService: restore,
      );
      expect(out.title, originalTitle);
      expect(out.chapters.first.title, chapters.first.title);
      verifyNever(restore.restorePuaInText(originalTitle, null));
    });
  });
}

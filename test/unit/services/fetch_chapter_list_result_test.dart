/// FetchChapterListResult / FetchContentResult 四态单元测试
///
/// 覆盖：
/// - 四态构造与 getter 互斥性
/// - success 携带数据
/// - noScript/busy/loadFailed 各自的判定
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/models/chapter.dart';
import 'package:novel_app/models/chapter_content_result.dart';
import 'package:novel_app/services/headless_webview_errors.dart';

void main() {
  // ================================================================
  // FetchChapterListResult
  // ================================================================
  group('FetchChapterListResult', () {
    test('success 携带章节列表', () {
      final chapters = [
        Chapter(title: '第一章', url: 'https://example.com/1', chapterIndex: 0),
        Chapter(title: '第二章', url: 'https://example.com/2', chapterIndex: 1),
      ];
      final result = FetchChapterListResult.success(chapters);

      expect(result.isSuccess, isTrue);
      expect(result.isNoScript, isFalse);
      expect(result.isBusy, isFalse);
      expect(result.isLoadFailed, isFalse);
      expect(result.chapters, hasLength(2));
      expect(result.chapters.first.title, '第一章');
    });

    test('noScript 状态', () {
      final result = FetchChapterListResult.noScript();

      expect(result.isSuccess, isFalse);
      expect(result.isNoScript, isTrue);
      expect(result.isBusy, isFalse);
      expect(result.isLoadFailed, isFalse);
    });

    test('busy 状态', () {
      final result = FetchChapterListResult.busy();

      expect(result.isSuccess, isFalse);
      expect(result.isNoScript, isFalse);
      expect(result.isBusy, isTrue);
      expect(result.isLoadFailed, isFalse);
    });

    test('loadFailed 状态', () {
      final result = FetchChapterListResult.loadFailed();

      expect(result.isSuccess, isFalse);
      expect(result.isNoScript, isFalse);
      expect(result.isBusy, isFalse);
      expect(result.isLoadFailed, isTrue);
    });

    test('success 空列表仍算 isSuccess（非空校验由调用方负责）', () {
      final result = FetchChapterListResult.success(const []);
      expect(result.isSuccess, isTrue);
      expect(result.chapters, isEmpty);
    });
  });

  // ================================================================
  // FetchContentResult
  // ================================================================
  group('FetchContentResult', () {
    test('success 携带章节内容', () {
      final content = ChapterContentResult(content: '正文', fromCache: false);
      final result = FetchContentResult.success(content);

      expect(result.isSuccess, isTrue);
      expect(result.isNoScript, isFalse);
      expect(result.isBusy, isFalse);
      expect(result.isLoadFailed, isFalse);
      expect(result.content.content, '正文');
    });

    test('noScript 状态', () {
      final result = FetchContentResult.noScript();
      expect(result.isNoScript, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.isLoadFailed, isFalse);
    });

    test('busy 状态', () {
      final result = FetchContentResult.busy();
      expect(result.isBusy, isTrue);
      expect(result.isSuccess, isFalse);
    });

    test('loadFailed 状态', () {
      final result = FetchContentResult.loadFailed();
      expect(result.isLoadFailed, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.isNoScript, isFalse);
    });
  });

  // ================================================================
  // 异常类型 userMessage
  // ================================================================
  group('异常类型 userMessage', () {
    test('PageLoadFailedException 提供 userMessage', () {
      const e = PageLoadFailedException('https://example.com');
      expect(e.userMessage, isNotEmpty);
      expect(e.userMessage, PageLoadFailedException.defaultMessage);
      expect(e.url, 'https://example.com');
    });

    test('NoExtractionScriptException 提供 userMessage', () {
      const e = NoExtractionScriptException('example.com');
      expect(e.userMessage, NoExtractionScriptException.defaultMessage);
    });

    test('WebViewBusyException 提供 userMessage', () {
      const e = WebViewBusyException('example.com');
      expect(e.userMessage, WebViewBusyException.defaultMessage);
    });
  });
}

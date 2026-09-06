import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/chapter_content_result.dart';

void main() {
  test('默认 fontFamily 为 null（向后兼容）', () {
    final r = ChapterContentResult(content: 'x');
    expect(r.fontFamily, isNull);
    expect(r.fromCache, isFalse);
  });

  test('可传 fontFamily', () {
    final r = ChapterContentResult(content: 'x', fontFamily: 'AntiCrawl');
    expect(r.fontFamily, 'AntiCrawl');
  });
}

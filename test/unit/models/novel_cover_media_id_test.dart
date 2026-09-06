import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/novel.dart';

void main() {
  group('Novel.coverMediaId', () {
    test('toMap 含 coverMediaId 键', () {
      final novel = Novel(
        title: '测试',
        author: '作者',
        url: 'custom://x',
        coverMediaId: 'media-abc',
      );
      expect(novel.toMap()['coverMediaId'], 'media-abc');
    });

    test('fromMap 读出 coverMediaId', () {
      final novel = Novel.fromMap({
        'id': 1,
        'title': '测试',
        'author': '作者',
        'url': 'custom://x',
        'coverMediaId': 'media-xyz',
      });
      expect(novel.coverMediaId, 'media-xyz');
    });

    test('fromMap 缺 coverMediaId 时为 null（兼容旧行）', () {
      final novel = Novel.fromMap({
        'id': 1,
        'title': '测试',
        'author': '作者',
        'url': 'custom://x',
      });
      expect(novel.coverMediaId, isNull);
    });

    test('copyWith 覆盖 coverMediaId', () {
      final novel = Novel(
        title: '测试',
        author: '作者',
        url: 'custom://x',
        coverMediaId: 'old',
      );
      expect(novel.copyWith(coverMediaId: 'new').coverMediaId, 'new');
    });
  });
}

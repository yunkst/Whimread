import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/models/site_script.dart';

void main() {
  group('SiteScript ocr 字段（v39 拆列后）', () {
    test('fromMap 读 chapter_list_ocr / chapter_content_ocr 列（1 → true）', () {
      final s = SiteScript.fromMap({
        'id': '1',
        'domain': 'a.com',
        'url_pattern': '',
        'chapter_list_js': '',
        'chapter_content_js': '',
        'sample_url': '',
        'created_at': 0,
        'last_used_at': 0,
        'use_count': 0,
        'verified': 0,
        'chapter_list_ocr': 1,
        'chapter_content_ocr': 1,
      });
      expect(s.chapterListOcr, isTrue);
      expect(s.chapterContentOcr, isTrue);
    });

    test('fromMap 两列缺失/0/null → false', () {
      final map = <String, dynamic>{
        'id': '1',
        'domain': 'a.com',
        'url_pattern': '',
        'chapter_list_js': '',
        'chapter_content_js': '',
        'sample_url': '',
        'created_at': 0,
        'last_used_at': 0,
        'use_count': 0,
        'verified': 0,
      };
      final s0 = SiteScript.fromMap(map);
      expect(s0.chapterListOcr, isFalse);
      expect(s0.chapterContentOcr, isFalse);

      final s1 = SiteScript.fromMap({
        ...map,
        'chapter_list_ocr': 0,
        'chapter_content_ocr': null,
      });
      expect(s1.chapterListOcr, isFalse);
      expect(s1.chapterContentOcr, isFalse);
    });

    test('番茄场景：chapter_list_ocr=false, chapter_content_ocr=true 各自独立', () {
      // 模拟番茄小说：目录页 title/chapter.title 是正常汉字，正文页有 PUA
      final s = SiteScript.fromMap({
        'id': '1',
        'domain': 'fanqie.example',
        'url_pattern': '',
        'chapter_list_js': 'js_list',
        'chapter_content_js': 'js_content',
        'sample_url': '',
        'created_at': 0,
        'last_used_at': 0,
        'use_count': 0,
        'verified': 0,
        'chapter_list_ocr': 0,
        'chapter_content_ocr': 1,
      });
      expect(s.chapterListOcr, isFalse);
      expect(s.chapterContentOcr, isTrue);
    });

    test('fromMap 不再读旧 ocr 列（保留 DB 兼容，但忽略）', () {
      // v39 起旧 ocr 列保留在 DB 但不再被读取
      final s = SiteScript.fromMap({
        'id': '1',
        'domain': 'a.com',
        'url_pattern': '',
        'chapter_list_js': '',
        'chapter_content_js': '',
        'sample_url': '',
        'created_at': 0,
        'last_used_at': 0,
        'use_count': 0,
        'verified': 0,
        'ocr': 1, // 旧列；新代码不读
        'chapter_list_ocr': 0,
        'chapter_content_ocr': 1,
      });
      // 即便旧列=1，新两列独立取值
      expect(s.chapterListOcr, isFalse);
      expect(s.chapterContentOcr, isTrue);
    });

    test('toMap 写新两列（true→1, false→0），不写旧 ocr 列', () {
      final base = SiteScript(
        id: '1',
        domain: 'a.com',
        urlPattern: '',
        chapterListJs: '',
        chapterContentJs: '',
        sampleUrl: '',
        createdAt: 0,
        lastUsedAt: 0,
        useCount: 0,
        verified: 0,
        chapterListOcr: true,
        chapterContentOcr: false,
      );
      final m = base.toMap();
      expect(m['chapter_list_ocr'], 1);
      expect(m['chapter_content_ocr'], 0);
      expect(m.containsKey('ocr'), isFalse); // 不再写旧列
    });

    test('copyWith 独立覆盖两列', () {
      final s = SiteScript(
        id: '1',
        domain: 'a.com',
        urlPattern: '',
        chapterListJs: '',
        chapterContentJs: '',
        sampleUrl: '',
        createdAt: 0,
        lastUsedAt: 0,
        useCount: 0,
        verified: 0,
        chapterListOcr: false,
        chapterContentOcr: false,
      );
      final s1 = s.copyWith(chapterListOcr: true);
      expect(s1.chapterListOcr, isTrue);
      expect(s1.chapterContentOcr, isFalse);
      expect(s.copyWith().chapterListOcr, isFalse); // 不传保持原值
    });

    test('构造默认两列均为 false（向后兼容）', () {
      final s = SiteScript(
        id: '1',
        domain: 'a.com',
        urlPattern: '',
        chapterListJs: '',
        chapterContentJs: '',
        sampleUrl: '',
        createdAt: 0,
        lastUsedAt: 0,
        useCount: 0,
        verified: 0,
      );
      expect(s.chapterListOcr, isFalse);
      expect(s.chapterContentOcr, isFalse);
    });
  });

  group('SiteScript bookshelfJs 字段（v40 新增）', () {
    test('fromMap 读 bookshelf_js 列', () {
      final s = SiteScript.fromMap({
        'id': '1',
        'domain': 'a.com',
        'url_pattern': '',
        'chapter_list_js': '',
        'chapter_content_js': '',
        'sample_url': '',
        'created_at': 0,
        'last_used_at': 0,
        'use_count': 0,
        'verified': 0,
        'bookshelf_js': 'const N=[...]; return JSON.stringify({novels:N});',
      });
      expect(s.bookshelfJs, contains('novels'));
      expect(s.hasBookshelfJs, isTrue);
    });

    test('fromMap 缺 bookshelf_js → 默认空串 + hasBookshelfJs=false', () {
      final s = SiteScript.fromMap({
        'id': '1',
        'domain': 'a.com',
        'url_pattern': '',
        'chapter_list_js': '',
        'chapter_content_js': '',
        'sample_url': '',
        'created_at': 0,
        'last_used_at': 0,
        'use_count': 0,
        'verified': 0,
      });
      expect(s.bookshelfJs, '');
      expect(s.hasBookshelfJs, isFalse);
    });

    test('toMap 写 bookshelf_js（空串也写出）', () {
      final s = SiteScript(
        id: '1',
        domain: 'a.com',
        urlPattern: '',
        chapterListJs: '',
        chapterContentJs: '',
        sampleUrl: '',
        createdAt: 0,
        lastUsedAt: 0,
        useCount: 0,
        verified: 0,
        bookshelfJs: '',
      );
      expect(s.toMap()['bookshelf_js'], '');
    });

    test('copyWith 覆盖 bookshelfJs 而不影响其它字段', () {
      final s0 = SiteScript(
        id: '1',
        domain: 'a.com',
        urlPattern: '',
        chapterListJs: 'list',
        chapterContentJs: '',
        sampleUrl: '',
        createdAt: 0,
        lastUsedAt: 0,
        useCount: 0,
        verified: 0,
      );
      final s1 = s0.copyWith(bookshelfJs: 'bs');
      expect(s1.bookshelfJs, 'bs');
      expect(s1.chapterListJs, 'list');
      expect(s0.bookshelfJs, ''); // 不传保持原值
    });
  });
}

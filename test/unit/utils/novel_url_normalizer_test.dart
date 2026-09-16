/// NovelUrlNormalizer 单元测试
///
/// 场景背景：手动添加存浏览器当前页 URL，书架同步存页面提取的 href，
/// 同一本书两条路径常见 URL 机械差异。归一化用于比较判定，不改变落库值。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/utils/novel_url_normalizer.dart';

void main() {
  group('normalize', () {
    test('http/https 视为相同', () {
      expect(
        NovelUrlNormalizer.normalize('http://a.com/book/1'),
        NovelUrlNormalizer.normalize('https://a.com/book/1'),
      );
    });

    test('尾部斜杠去掉（根路径除外）', () {
      expect(
        NovelUrlNormalizer.normalize('https://a.com/book/1/'),
        'https://a.com/book/1',
      );
      expect(NovelUrlNormalizer.normalize('https://a.com/'), 'https://a.com');
    });

    test('fragment 去掉', () {
      expect(
        NovelUrlNormalizer.normalize('https://a.com/book/1#comment'),
        'https://a.com/book/1',
      );
    });

    test('默认端口去掉，非默认端口保留', () {
      expect(
        NovelUrlNormalizer.normalize('https://a.com:443/book/1'),
        'https://a.com/book/1',
      );
      // http 统一映射为 https 比较（80 端口随之抹掉）
      expect(
        NovelUrlNormalizer.normalize('http://a.com:80/book/1'),
        'https://a.com/book/1',
      );
      expect(
        NovelUrlNormalizer.normalize('http://a.com:8080/book/1'),
        'https://a.com:8080/book/1',
      );
    });

    test('scheme/host 大小写归一', () {
      expect(
        NovelUrlNormalizer.normalize('HTTPS://WWW.A.com/Book/1'),
        'https://www.a.com/Book/1',
      );
    });

    test('query 保留', () {
      expect(
        NovelUrlNormalizer.normalize('https://a.com/book/1?page=2'),
        'https://a.com/book/1?page=2',
      );
    });

    test('custom:// 原样返回（原创标识不做归一化）', () {
      expect(
        NovelUrlNormalizer.normalize('custom://custom_novel_abc/'),
        'custom://custom_novel_abc/',
      );
    });

    test('无法解析或空串返回 trim 原文', () {
      expect(NovelUrlNormalizer.normalize('  '), '');
      // 无 scheme/host 的纯路径串：保守返回 trim 原文
      expect(NovelUrlNormalizer.normalize(' not-a-url '), 'not-a-url');
    });
  });

  group('looselyEquals', () {
    test('机械变体判定为同一本', () {
      expect(
        NovelUrlNormalizer.looselyEquals(
          'https://www.a.com/book/1',
          'http://www.a.com/book/1/',
        ),
        isTrue,
      );
      expect(
        NovelUrlNormalizer.looselyEquals(
          'https://a.com/book/1#top',
          'https://a.com/book/1',
        ),
        isTrue,
      );
    });

    test('路径不同的两本书不相等', () {
      expect(
        NovelUrlNormalizer.looselyEquals(
          'https://a.com/book/1',
          'https://a.com/book/2',
        ),
        isFalse,
      );
    });

    test('query 不同不相等（保守策略）', () {
      expect(
        NovelUrlNormalizer.looselyEquals(
          'https://a.com/book/1?page=1',
          'https://a.com/book/1?page=2',
        ),
        isFalse,
      );
    });
  });

  group('sameSiteHost', () {
    test('www / m / mobile / 裸域视为同站', () {
      expect(NovelUrlNormalizer.sameSiteHost('www.a.com', 'a.com'), isTrue);
      expect(NovelUrlNormalizer.sameSiteHost('m.a.com', 'www.a.com'), isTrue);
      expect(
          NovelUrlNormalizer.sameSiteHost('mobile.a.com', 'M.A.COM'), isTrue);
    });

    test('不同站点不相等', () {
      expect(NovelUrlNormalizer.sameSiteHost('a.com', 'b.com'), isFalse);
      // 前缀只是 host 头部别名，不能把 m.a.com 当成 a.com 的子域变体以外的站
      expect(NovelUrlNormalizer.sameSiteHost('m.a.com', 'm.b.com'), isFalse);
    });

    test('空 host 不相等', () {
      expect(NovelUrlNormalizer.sameSiteHost('', 'a.com'), isFalse);
      expect(NovelUrlNormalizer.sameSiteHost('', ''), isFalse);
    });
  });
}

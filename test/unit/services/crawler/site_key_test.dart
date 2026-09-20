/// SiteKey 测试
///
/// P1 修复爱丽丝网 bug 的核心：host 变体等价匹配。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/crawler/site_key.dart';

void main() {
  group('SiteKey 归一化', () {
    test('裸域保持不变', () {
      expect(SiteKey.fromHost('alice.com').value, 'alice.com');
    });

    test('小写归一', () {
      expect(SiteKey.fromHost('Alice.COM').value, 'alice.com');
      expect(SiteKey.fromHost('WWW.Alice.COM').value, 'alice.com');
    });

    test('去前后空格', () {
      expect(SiteKey.fromHost('  alice.com  ').value, 'alice.com');
    });

    test('剥除 www. 前缀', () {
      expect(SiteKey.fromHost('www.alice.com').value, 'alice.com');
    });

    test('剥除 m. 前缀', () {
      expect(SiteKey.fromHost('m.alice.com').value, 'alice.com');
    });

    test('剥除 wap./mobile. 前缀', () {
      expect(SiteKey.fromHost('wap.alice.com').value, 'alice.com');
      expect(SiteKey.fromHost('mobile.alice.com').value, 'alice.com');
    });

    test('保留非常见子域（不归并）', () {
      // novel. / bbs. 不是已知手机前缀，保留
      expect(SiteKey.fromHost('novel.alice.com').value, 'novel.alice.com');
      expect(SiteKey.fromHost('bbs.alice.com').value, 'bbs.alice.com');
    });

    test('剥前缀不会误剥裸域名（防止 m.xxx → xxx）', () {
      // m.alice.com 剥后是 alice.com ✓
      expect(SiteKey.fromHost('m.alice.com').value, 'alice.com');
      // host 只有 'm.' 本身时剥不出更短结果，原样返回（边界行为）
      expect(SiteKey.fromHost('m.').value, 'm.');
    });

    test('空 / null 返回 null', () {
      expect(SiteKey.tryFromHost(null), isNull);
      expect(SiteKey.tryFromHost(''), isNull);
      expect(SiteKey.tryFromHost('   '), isNull);
    });
  });

  group('SiteKey 等价比较', () {
    test('www./m./wap./裸域 互相等价', () {
      final variants = [
        'alice.com',
        'www.alice.com',
        'm.alice.com',
        'wap.alice.com',
        'mobile.alice.com',
        'ALICE.COM',
      ];
      final key = SiteKey.fromHost('alice.com');
      for (final v in variants) {
        expect(
          SiteKey.tryFromHost(v),
          key,
          reason: 'host "$v" 应该归一为 $key',
        );
      }
    });

    test('matchesHost 简洁用法', () {
      final key = SiteKey.fromHost('alice.com');
      expect(key.matchesHost('www.alice.com'), isTrue);
      expect(key.matchesHost('m.alice.com'), isTrue);
      expect(key.matchesHost('novel.alice.com'), isFalse);
      expect(key.matchesHost('example.com'), isFalse);
      expect(key.matchesHost(null), isFalse);
    });

    test('不同站点不等价', () {
      final a = SiteKey.fromHost('www.alice.com');
      final b = SiteKey.fromHost('www.bob.com');
      expect(a == b, isFalse);
      expect(a.matchesHost('bob.com'), isFalse);
    });
  });
}

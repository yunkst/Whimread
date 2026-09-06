import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/novel_agent/scenarios/network_request_recorder.dart';

void main() {
  test('add 后 snapshot 能返回该记录', () {
    final r = NetworkRequestRecorder();
    r.add(
      method: 'GET',
      url: 'https://api.x.com/chapter/list?novelId=123&page=1',
      headers: {'referer': 'https://api.x.com/'},
      isForMainFrame: false,
    );
    final snap = r.snapshot();
    expect(snap['total'], 1);
    expect(snap['returned'], 1);
    expect(snap['truncated_to'], 50);
    final reqs = snap['requests'] as List;
    expect(reqs.length, 1);
    final first = reqs[0] as Map<String, dynamic>;
    expect(first['method'], 'GET');
    expect(first['url'], 'https://api.x.com/chapter/list?novelId=123&page=1');
    expect(first['query_params'], {'novelId': '123', 'page': '1'});
    expect(first['request_headers'], {'referer': 'https://api.x.com/'});
    expect(first['is_for_main_frame'], false);
    expect(first['index'], 0);
    expect(first['ts_ms'], isA<int>());
  });

  test('FIFO 淘汰:超过 maxCapacity 丢最老', () {
    final r = NetworkRequestRecorder(maxCapacity: 3);
    for (var i = 0; i < 4; i++) {
      r.add(method: 'GET', url: 'https://x.com/$i', headers: const {});
    }
    final snap = r.snapshot(limit: 100);
    expect(snap['total'], 3);
    final reqs = (snap['requests'] as List).cast<Map<String, dynamic>>();
    expect(reqs.first['url'], 'https://x.com/1');  // index 0 已被淘汰
    expect(reqs.last['url'], 'https://x.com/3');
  });

  test('snapshot url_contains 过滤', () {
    final r = NetworkRequestRecorder();
    r.add(method: 'GET', url: 'https://x.com/api/chapter', headers: const {});
    r.add(method: 'GET', url: 'https://x.com/static/main.js', headers: const {});
    final snap = r.snapshot(urlContains: 'chapter', limit: 100);
    expect(snap['returned'], 1);
    expect(
      ((snap['requests'] as List).single as Map<String, dynamic>)['url'],
      'https://x.com/api/chapter',
    );
  });

  test('snapshot method 过滤(大小写不敏感)', () {
    final r = NetworkRequestRecorder();
    r.add(method: 'GET', url: 'https://x.com/a', headers: const {});
    r.add(method: 'POST', url: 'https://x.com/b', headers: const {});
    final snap = r.snapshot(method: 'post', limit: 100);
    expect(snap['returned'], 1);
    expect(
      ((snap['requests'] as List).single as Map<String, dynamic>)['method'],
      'POST',
    );
  });

  test('snapshot since_index 过滤', () {
    final r = NetworkRequestRecorder();
    r.add(method: 'GET', url: 'https://x.com/a', headers: const {});  // index 0
    r.add(method: 'GET', url: 'https://x.com/b', headers: const {});  // index 1
    r.add(method: 'GET', url: 'https://x.com/c', headers: const {});  // index 2
    final snap = r.snapshot(sinceIndex: 0, limit: 100);
    final reqs = (snap['requests'] as List).cast<Map<String, dynamic>>();
    expect(reqs.length, 2);
    expect(reqs.first['url'], 'https://x.com/b');
  });

  test('snapshot limit clamp 到 [1,100]', () {
    final r = NetworkRequestRecorder();
    r.add(method: 'GET', url: 'https://x.com/a', headers: const {});
    expect((r.snapshot(limit: 0) as Map)['truncated_to'], 1);
    expect((r.snapshot(limit: 999) as Map)['truncated_to'], 100);
  });

  test('header 值超 maxHeaderValueBytes 标 truncated', () {
    final r = NetworkRequestRecorder(maxHeaderValueBytes: 10);
    r.add(
      method: 'GET',
      url: 'https://x.com/a',
      headers: {'cookie': 'a-very-long-cookie-value-that-exceeds-limit'},
    );
    final snap = r.snapshot(limit: 100);
    final headers = (((snap['requests'] as List).single
        as Map<String, dynamic>)['request_headers']) as Map<String, dynamic>;
    expect(headers['_cookie_truncated'], 'true');
    expect((headers['cookie'] as String).endsWith('...'), isTrue);
  });

  test('query_params 多值取末个(Uri.queryParameters 行为)', () {
    final r = NetworkRequestRecorder();
    r.add(method: 'GET', url: 'https://x.com/?a=1&a=2', headers: const {});
    final snap = r.snapshot(limit: 100);
    final qp = (((snap['requests'] as List).single
        as Map<String, dynamic>)['query_params']) as Map;
    expect(qp['a'], '2');  // Uri.queryParameters 多值时取最后一个
  });

  test('clear 清空记录 + 重置 index', () {
    final r = NetworkRequestRecorder();
    r.add(method: 'GET', url: 'https://x.com/a', headers: const {});
    r.clear();
    r.add(method: 'GET', url: 'https://x.com/b', headers: const {});
    final snap = r.snapshot(limit: 100);
    expect(snap['total'], 1);
    expect(
      ((snap['requests'] as List).single as Map<String, dynamic>)['index'],
      0,  // clear 后 index 从 0 重新计
    );
  });

  test('method/headers 为 null(Android<21)不崩 + 默认值', () {
    final r = NetworkRequestRecorder();
    r.add(method: null, url: 'https://x.com/a', headers: null);
    final snap = r.snapshot(limit: 100);
    final first = ((snap['requests'] as List).single) as Map<String, dynamic>;
    expect(first['method'], 'GET');
    expect(first['request_headers'], {});
  });

  test('dispose 后 add 静默 no-op', () {
    final r = NetworkRequestRecorder();
    r.add(method: 'GET', url: 'https://x.com/a', headers: const {});
    r.dispose();
    r.add(method: 'GET', url: 'https://x.com/b', headers: const {});
    final snap = r.snapshot(limit: 100);
    expect(snap['total'], 0);
  });
}

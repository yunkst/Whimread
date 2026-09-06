// ignore_for_file: lines_longer_than_80_chars

/// RunStore 句柄机制单元测试
///
/// 验证 run_id 句柄的核心行为（纯 Dart 逻辑，不依赖 WebView）：
/// - execution 来源的自增 run_id（exec_n）
/// - database 来源的 run_id（db_{id}）
/// - LRU 淘汰策略
/// - get 刷新访问顺序
///
/// 相关工具逻辑（execute_js/save_script/get_cached_script/inspect_script）
/// 通过真实 WebView 的集成测试覆盖，见
/// integration_test/webview_extract/run_store_test.dart。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/services/novel_agent/scenarios/run_store.dart';

void main() {
  group('RunStore - execution 来源', () {
    test('put 返回自增的 exec_n run_id', () {
      final store = RunStore();

      final id1 = store.put(
        script: 'const P="{{URL}}"; (async()=>1)()',
        success: true,
        source: RunEntrySource.execution,
      );
      final id2 = store.put(
        script: 'const P="{{URL}}"; (async()=>2)()',
        success: true,
        source: RunEntrySource.execution,
      );
      final id3 = store.put(
        script: 'const P="{{URL}}"; (async()=>3)()',
        success: true,
        source: RunEntrySource.execution,
      );

      expect(id1, 'exec_1');
      expect(id2, 'exec_2');
      expect(id3, 'exec_3');
      expect(store.length, 3);
    });

    test('get 通过 run_id 取出完整脚本内容', () {
      final store = RunStore();
      const script = "const PAGE_URL = '{{URL}}'; return JSON.stringify({ok:true});";

      final id = store.put(
        script: script,
        success: true,
        source: RunEntrySource.execution,
        testUrl: 'https://example.com/ch1',
      );

      final entry = store.get(id);
      expect(entry, isNotNull);
      expect(entry!.runId, 'exec_1');
      expect(entry.script, script);
      expect(entry.source, RunEntrySource.execution);
      expect(entry.testUrl, 'https://example.com/ch1');
      expect(entry.success, isTrue);
    });

    test('get 不存在的 run_id 返回 null', () {
      final store = RunStore();
      expect(store.get('exec_999'), isNull);
      expect(store.get('db_unknown'), isNull);
    });

    test('contains 正确反映存在性', () {
      final store = RunStore();
      final id = store.put(
        script: "const P='{{URL}}';",
        success: true,
        source: RunEntrySource.execution,
      );

      expect(store.contains(id), isTrue);
      expect(store.contains('exec_999'), isFalse);
    });
  });

  group('RunStore - database 来源', () {
    test('put 返回 db_{rawId} 形式 run_id', () {
      final store = RunStore();

      final id = store.put(
        script: "const P='{{URL}}'; return JSON.stringify({title:'x'});",
        success: true,
        source: RunEntrySource.database,
        rawId: '1718000000000',
        domain: 'www.example.com',
      );

      expect(id, 'db_1718000000000');
      final entry = store.get(id);
      expect(entry, isNotNull);
      expect(entry!.source, RunEntrySource.database);
      expect(entry.dbId, '1718000000000');
      expect(entry.domain, 'www.example.com');
      expect(entry.testUrl, isNull);
    });

    test('同一 db id 重复 put 覆盖旧记录', () {
      final store = RunStore();

      store.put(
        script: 'old script',
        success: true,
        source: RunEntrySource.database,
        rawId: '42',
      );
      store.put(
        script: 'new script',
        success: true,
        source: RunEntrySource.database,
        rawId: '42',
      );

      expect(store.length, 1);
      final entry = store.get('db_42');
      expect(entry!.script, 'new script');
    });
  });

  group('RunStore - LRU 淘汰', () {
    test('超出 capacity 淘汰最早未访问的记录', () {
      final store = RunStore(capacity: 3);

      final id1 = store.put(script: 's1', success: true, source: RunEntrySource.execution);
      final id2 = store.put(script: 's2', success: true, source: RunEntrySource.execution);
      final id3 = store.put(script: 's3', success: true, source: RunEntrySource.execution);

      // 访问 id1，使其成为最近使用
      store.get(id1);

      // 插入第 4 个，触发淘汰（应淘汰 id2，因为 id1 刚被访问过）
      final id4 = store.put(script: 's4', success: true, source: RunEntrySource.execution);

      expect(store.length, 3);
      expect(store.contains(id1), isTrue, reason: 'id1 刚被访问，不应被淘汰');
      expect(store.contains(id2), isFalse, reason: 'id2 最早未访问，应被淘汰');
      expect(store.contains(id3), isTrue);
      expect(store.contains(id4), isTrue);
    });

    test('get 刷新访问顺序（被访问的记录不会被优先淘汰）', () {
      final store = RunStore(capacity: 2);

      final id1 = store.put(script: 's1', success: true, source: RunEntrySource.execution);
      final id2 = store.put(script: 's2', success: true, source: RunEntrySource.execution);

      // 访问 id1
      store.get(id1);

      // 插入第 3 个，应淘汰 id2（id1 刚被访问）
      store.put(script: 's3', success: true, source: RunEntrySource.execution);

      expect(store.contains(id1), isTrue);
      expect(store.contains(id2), isFalse);
    });

    test('clear 清空所有记录并重置计数器', () {
      final store = RunStore();
      store.put(script: 's1', success: true, source: RunEntrySource.execution);
      store.put(script: 's2', success: true, source: RunEntrySource.execution);

      store.clear();

      expect(store.length, 0);
      expect(store.contains('exec_1'), isFalse);

      // clear 后计数器重置，重新从 exec_1 开始
      final newId = store.put(script: 's3', success: true, source: RunEntrySource.execution);
      expect(newId, 'exec_1');
    });
  });

  group('RunEntry - toJson', () {
    test('toJson 包含关键字段但不含完整脚本', () {
      final store = RunStore();
      final id = store.put(
        script: 'const P="{{URL}}"; long script content here',
        success: true,
        source: RunEntrySource.execution,
        testUrl: 'https://t.com',
        resultSummary: '{"ok":true}',
      );

      final entry = store.get(id)!;
      final json = entry.toJson();

      expect(json['run_id'], 'exec_1');
      expect(json['success'], isTrue);
      expect(json['source'], 'execution');
      expect(json['test_url'], 'https://t.com');
      expect(json['result_summary'], '{"ok":true}');
      expect(json['script_length'], greaterThan(0));
      // toJson 不应包含完整脚本内容（避免占上下文）
      expect(json.containsKey('script'), isFalse);
    });
  });
}

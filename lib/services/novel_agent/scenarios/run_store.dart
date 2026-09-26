/// execute_js 执行记录的内存存储（句柄机制）
///
/// 解决「脚本在持久化边界被反复重传」的问题：
///
/// - **save 重传**：AI 用 execute_js 测试通过的脚本，save_script 原本要再传一遍
///   → 现在 execute_js 成功后把脚本注册到这里返回 run_id，
///     save_script 只传 run_id，零重传，且保存版本与测试版本天然一致。
///
/// - **load 重抄**：get_cached_script 从数据库读出的脚本，原本要塞进上下文
///   再被 AI 抄进 execute_js 参数
///   → 现在 load 时把脚本注册到这里返回 db_xxx 形式的 run_id，
///     后续 execute_js 通过 run_id 重跑，零重抄。
///
/// RunStore 是**单次场景会话**的内存缓存（不跨场景实例），LRU 淘汰最近
/// [capacity] 条记录。无需持久化——脚本本身已存在于 site_scripts 表。
library;

import 'dart:collection';

/// 记录来源
enum RunEntrySource {
  /// execute_js 现场执行产生
  execution,

  /// 从数据库 site_scripts 表加载
  database,
}

/// 一次脚本执行/加载的记录
class RunEntry {
  /// 句柄 ID（格式：`exec_{n}` 或 `db_{site_scripts.id}`）
  final String runId;

  /// 原始脚本（保留 {{URL}} 占位符，执行时再替换）
  final String script;

  /// 执行时的 test_url（database 来源时为 null）
  final String? testUrl;

  /// 执行是否成功
  final bool success;

  /// 执行结果摘要（截断后的 preview，便于调试）
  final String? resultSummary;

  /// 时间戳（毫秒）
  final int ts;

  /// 来源
  final RunEntrySource source;

  /// 数据库来源时的域名（database 来源时填充）
  final String? domain;

  /// 数据库来源时的原始 id（database 来源时填充）
  final String? dbId;

  const RunEntry({
    required this.runId,
    required this.script,
    required this.success,
    required this.ts,
    required this.source,
    this.testUrl,
    this.resultSummary,
    this.domain,
    this.dbId,
  });

  Map<String, dynamic> toJson() => {
        'run_id': runId,
        'success': success,
        'source': source.name,
        if (testUrl != null) 'test_url': testUrl,
        if (resultSummary != null) 'result_summary': resultSummary,
        if (domain != null) 'domain': domain,
        'script_length': script.length,
      };
}

/// 脚本执行记录的内存存储（LRU）
class RunStore {
  RunStore({this.capacity = 50});

  /// 最大保留记录数（超出后淘汰最早未访问的）
  final int capacity;

  /// execution 来源的自增计数器
  int _counter = 0;

  /// LRU 有序 Map（最近访问的位于迭代末尾）
  final LinkedHashMap<String, RunEntry> _store = LinkedHashMap();

  /// 注册一条记录，返回 run_id
  ///
  /// - [source] = [RunEntrySource.execution]：runId 形如 `exec_<n>`（自增）
  /// - [source] = [RunEntrySource.database]：runId 形如 `db_<rawId>`
  ///   （rawId 取自 site_scripts.id）
  String put({
    required String script,
    required bool success,
    required RunEntrySource source,
    String? testUrl,
    String? resultSummary,
    String? rawId,
    String? domain,
  }) {
    final String runId;
    if (source == RunEntrySource.database) {
      runId = 'db_${rawId ?? (_counter + 1)}';
    } else {
      _counter += 1;
      runId = 'exec_$_counter';
    }

    final entry = RunEntry(
      runId: runId,
      script: script,
      success: success,
      ts: DateTime.now().millisecondsSinceEpoch,
      source: source,
      testUrl: testUrl,
      resultSummary: resultSummary,
      domain: domain,
      dbId: source == RunEntrySource.database ? rawId : null,
    );

    // LRU：先移除再重新插入，使其位于末尾（最近访问）
    _store.remove(runId);
    _store[runId] = entry;

    // 容量淘汰：移除最早未访问的（迭代首个）
    while (_store.length > capacity) {
      _store.remove(_store.keys.first);
    }

    return runId;
  }

  /// 取出一条记录，同时刷新 LRU 访问顺序
  RunEntry? get(String runId) {
    final entry = _store[runId];
    if (entry == null) return null;
    _store.remove(runId);
    _store[runId] = entry;
    return entry;
  }

  /// 是否存在某条记录
  bool contains(String runId) => _store.containsKey(runId);

  /// 当前记录数
  int get length => _store.length;

  /// 清空（测试用）
  void clear() {
    _store.clear();
    _counter = 0;
  }
}

import 'dart:convert';

/// 单条网络请求记录(已截断、已解析 query_params)
class NetworkRequestRecord {
  final int index;
  final String method;
  final String url;
  final Map<String, String> queryParams;
  final Map<String, String> requestHeaders;
  final bool isForMainFrame;
  final int tsMs;

  const NetworkRequestRecord({
    required this.index,
    required this.method,
    required this.url,
    required this.queryParams,
    required this.requestHeaders,
    required this.isForMainFrame,
    required this.tsMs,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'method': method,
        'url': url,
        'query_params': queryParams,
        'request_headers': requestHeaders,
        'is_for_main_frame': isForMainFrame,
        'ts_ms': tsMs,
      };
}

/// Headless WebView 网络请求观察器(场景级)
///
/// 通过 [add] 累积请求,FIFO 淘汰,[snapshot] 返回过滤后的快照。
class NetworkRequestRecorder {
  NetworkRequestRecorder({
    this.maxCapacity = 500,
    this.maxHeaderValueBytes = 1024,
  });

  final int maxCapacity;
  final int maxHeaderValueBytes;

  final List<NetworkRequestRecord> _records = [];
  int _nextIndex = 0;
  bool _disposed = false;

  /// 添加一条请求记录。
  ///
  /// [method] / [headers] 可为 null(Android < 21),默认 method='GET'、headers={}。
  void add({
    required String url,
    String? method,
    Map<String, String>? headers,
    bool isForMainFrame = false,
  }) {
    if (_disposed) return;

    final parsed = _parseQueryParams(url);
    final truncatedHeaders = _truncateHeaders(headers ?? const {});

    final record = NetworkRequestRecord(
      index: _nextIndex++,
      method: method ?? 'GET',
      url: url,
      queryParams: parsed,
      requestHeaders: truncatedHeaders,
      isForMainFrame: isForMainFrame,
      tsMs: DateTime.now().millisecondsSinceEpoch,
    );

    _records.add(record);
    if (_records.length > maxCapacity) {
      _records.removeAt(0);
    }
  }

  /// 清空所有记录,重置 index 计数器(页面跳转时调用)
  void clear() {
    if (_disposed) return;
    _records.clear();
    _nextIndex = 0;
  }

  /// 释放:dispose 后 add/clear 静默 no-op。
  void dispose() {
    _disposed = true;
    _records.clear();
    _nextIndex = 0;
  }

  /// 返回过滤后的快照 envelope。
  ///
  /// 返回结构:{ total, returned, truncated_to, requests:[...] }
  /// - [urlContains]:URL 子串过滤(大小写敏感)
  /// - [method]:HTTP method 过滤(大小写不敏感)
  /// - [sinceIndex]:只返回 index > sinceIndex 的
  /// - [limit]:最多返回条数(默认 50,内部 clamp 到 [1,100])
  Map<String, dynamic> snapshot({
    String? urlContains,
    String? method,
    int? sinceIndex,
    int limit = 50,
  }) {
    final effectiveLimit = limit.clamp(1, 100);

    Iterable<NetworkRequestRecord> filtered = _records;
    if (urlContains != null && urlContains.isNotEmpty) {
      filtered = filtered.where((r) => r.url.contains(urlContains));
    }
    if (method != null && method.isNotEmpty) {
      final upper = method.toUpperCase();
      filtered = filtered.where((r) => r.method.toUpperCase() == upper);
    }
    if (sinceIndex != null) {
      filtered = filtered.where((r) => r.index > sinceIndex);
    }

    // 按时间顺序(老的在前)截取最近 effectiveLimit 条
    final all = filtered.toList();
    final total = _records.length;
    final subset = all.length > effectiveLimit
        ? all.sublist(all.length - effectiveLimit)
        : all;

    return {
      'total': total,
      'returned': subset.length,
      'truncated_to': effectiveLimit,
      'requests': subset.map((r) => r.toJson()).toList(),
    };
  }

  /// 从 URL 解析 query_params。URL 解析失败时返回 {}。
  Map<String, String> _parseQueryParams(String url) {
    try {
      final uri = Uri.parse(url);
      return Map<String, String>.from(uri.queryParameters);
    } catch (_) {
      return const {};
    }
  }

  /// 截断单个 header 值(按 UTF-8 字节数计),超长标 `_truncated`。
  Map<String, String> _truncateHeaders(Map<String, String> headers) {
    final result = <String, String>{};
    headers.forEach((key, value) {
      final bytes = utf8.encode(value);
      if (bytes.length <= maxHeaderValueBytes) {
        result[key] = value;
      } else {
        final truncated = utf8.decode(bytes.sublist(0, maxHeaderValueBytes),
            allowMalformed: true);
        result[key] = '$truncated...';
        result['_${key}_truncated'] = 'true';
      }
    });
    return result;
  }
}

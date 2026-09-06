/// 工具结果格式化器
///
/// 职责单一：把工具执行产出的 Map → (给 LLM 的截断版, 给 DB 的完整版)
/// - LLM 版始终是合法 JSON（对超长字段做智能裁剪，保留结构）
/// - `__meta`（run_id 等关键句柄）作为顶层 JSON key 拼回，永不截断
/// - `full` 是截断前的完整序列化，供 DB 持久化 / hydrate 续聊时 LLM 看到完整结果
///
/// 设计要点：
/// 1) **消除隐式时序契约**：调用方拿到的是 (llm, full) 二元返回值，
///    不再依赖 `final full = resultStr` 这类必须在截断前抓快照的写法。
/// 2) **错误分支优化**：保留 `error / message / suggestion` 字段，
///    `partial_data` 不再重复 `error` 内容（避免浪费预算 + JSON 被从中间切断）。
/// 3) **正常分支优化**：智能裁剪超长字段值，整体仍是合法 JSON，
///    不再输出 `... [truncated]` 拼在非法 JSON 后面的混合体。
/// 4) **短字段豁免 + 长字段比例分配**：序列化后 ≤ [shortFieldThreshold]
///    的字段直接保留原值（保护 id/title/count 等关键字段不被压没）；
///    仅当总长超预算时，对超长字段按体积比例公平压缩，最后硬校验兜底。
library;

import 'dart:convert';

/// 工具结果格式化产物
class ToolResultFormat {
  /// 给 LLM 的截断版（合法 JSON，受 maxChars 限制）
  final String llm;

  /// 给 DB 的完整原始结果（jsonEncode 一次序列化结果，未截断）
  final String full;

  const ToolResultFormat({required this.llm, required this.full});
}

/// 工具结果格式化器
class ToolResultFormatter {
  /// 给 LLM 的最大字符数（含外层 JSON 包装和 __meta）
  ///
  /// 默认 50000 字符 ≈ 12.5K tokens，覆盖单章正文（通常 3000-8000 字）。
  final int maxChars;

  /// 短字段豁免阈值：序列化后 ≤ 此值的字段直接保留原值，不参与压缩
  ///
  /// 默认 1000 字符。保护 id / title / count / position 等关键字段，
  /// 避免它们在大结果中被比例压缩算法压没。
  final int shortFieldThreshold;

  /// [truncated] 后缀在 value 上的标记（截断时拼接）
  static const _truncatedSuffix = '... [truncated]';

  const ToolResultFormatter({
    this.maxChars = 50000,
    this.shortFieldThreshold = 1000,
  });

  /// 格式化工具结果
  ///
  /// [result] 工具执行产出的 JSON 可解析结果（含 __meta）。
  /// 返回的 `llm` 是给 LLM 看的（可能截断），`full` 是给 DB 的完整版。
  ToolResultFormat format(Map<String, dynamic> result) {
    final full = jsonEncode(result);

    // 剥离 __meta：不参与预算（run_id 等关键句柄必须送达 LLM）
    final meta = result.remove('__meta') as Map<String, dynamic>?;
    final llm = _truncate(result, meta);

    return ToolResultFormat(llm: llm, full: full);
  }

  /// 截断 + 拼回 __meta
  String _truncate(Map<String, dynamic> body, Map<String, dynamic>? meta) {
    final encoded = jsonEncode(body);
    // __meta 的体积要从总预算里扣除，它本身永不裁剪
    final metaOverhead = meta == null ? 0 : jsonEncode(meta).length + 12;
    // 预留 5% 给硬校验补闭合括号 + 估算误差
    final bodyBudget = (maxChars - metaOverhead) * 95 ~/ 100;

    if (encoded.length <= bodyBudget) {
      return meta == null ? encoded : _withMeta(encoded, meta);
    }

    // 超过预算：按错误/正常分支智能裁剪
    final trimmed = body.containsKey('error')
        ? _trimErrorBody(body, bodyBudget)
        : _trimNormalBody(body, bodyBudget);

    final trimmedEncoded = jsonEncode(trimmed);
    // 硬校验兜底：估算误差可能让结果略超预算，补足缺失的闭合括号
    final safe = _hardClamp(trimmedEncoded, bodyBudget);
    final finalEncoded = _withMetaIfNeeded(safe, meta, maxChars);
    return finalEncoded;
  }

  /// 拼回 __meta（如果有），并保证最终总长 ≤ maxChars
  String _withMetaIfNeeded(
      String encoded, Map<String, dynamic>? meta, int maxTotal) {
    if (meta == null) return encoded;
    final combined = _withMeta(encoded, meta);
    if (combined.length <= maxTotal) return combined;
    // 加了 meta 后超总预算：再硬截一次
    return _hardClamp(combined, maxTotal);
  }

  /// 硬兜底：若裁剪后仍超预算，在 JSON 结构字符处截断，保证字符串一定闭合
  ///
  /// 原实现只统计 {, [ 深度，把截断点设在 raw [budget] 处，这会让截断点
  /// 落在字符串字面量中间，导致 jsonDecode 报 Unterminated string
  /// （OCR / HTML 等含大量特殊字符的长文本场景频发）。
  ///
  /// 修复：扫描时记录最后一个"截断后仍为合法 JSON 前缀"的位置 [bestEnd]
  /// 及其括号深度 [bestDepth]，在该处截断并补缺失的 `}`。
  /// 合法截断点 = 字符串外的 `,`（截到逗号前，保留前序字段）或 `}` / `]`
  /// （截到括号后）。这样字符串字面量永远完整闭合。
  ///
  /// 这是最后兜底：正常情况下 `_trimValue` 的 10% 安全裕量足以避免走到这。
  String _hardClamp(String encoded, int budget) {
    if (encoded.length <= budget) return encoded;

    int depth = 0;
    bool inString = false;
    bool escaped = false;
    int bestEnd = -1;
    int bestDepth = 0;

    for (int i = 0; i < budget; i++) {
      final ch = encoded[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (ch == '{' || ch == '[') depth++;
      if (ch == '}' || ch == ']') {
        depth--;
        bestEnd = i + 1;
        bestDepth = depth;
      } else if (ch == ',') {
        bestEnd = i;
        bestDepth = depth;
      }
    }

    // 1) Prefer: truncate at structural char outside string
    if (bestEnd > 0) {
      final cut = encoded.substring(0, bestEnd);
      final closing = bestDepth > 0 ? '}' * bestDepth : '';
      return '$cut$closing';
    }

    // 2) Fallback: budget is entirely inside a string literal (single huge field).
    //    Hand-rolling escape / surrogate boundary checks is error-prone, so let
    //    jsonDecode itself be the judge: probe from budget downward, first point
    //    that decodes cleanly wins. Rare path; perf acceptable.
    if (depth <= 0) return '{}';
    final closing = '}' * depth;
    final close = '"$closing';
    for (int tryK = budget - close.length; tryK > 0; tryK--) {
      // skip UTF-16 low surrogate to avoid splitting surrogate pairs
      if ((encoded.codeUnitAt(tryK) & 0xFC00) == 0xDC00) continue;
      final candidate = '${encoded.substring(0, tryK)}$close';
      try {
        jsonDecode(candidate);
        return candidate;
      } catch (_) {
        // truncation landed mid-escape or other invalid spot, try earlier
      }
    }
    return '{}';
  }

  /// 错误分支：保留 error/message/suggestion + partial_data（不含 error 重复）
  ///
  /// [bodyBudget] 扣除 __meta 后留给 body 的字符预算。
  Map<String, dynamic> _trimErrorBody(
      Map<String, dynamic> body, int bodyBudget) {
    final errorInfo = <String, dynamic>{
      'error': body['error'],
    };
    if (body['message'] != null) errorInfo['message'] = body['message'];
    if (body['suggestion'] != null) errorInfo['suggestion'] = body['suggestion'];

    final errorEncoded = jsonEncode(errorInfo);
    // 预留 errorInfo 自身 + partial_data 键名包装余量（30 字符）
    final remaining = bodyBudget - errorEncoded.length - 30;

    if (remaining <= 200) {
      // 预算太紧，只回错误信息本身
      return errorInfo;
    }

    // partial_data：把 body 里除 error/message/suggestion 外的字段裁剪后放入
    final partialSource = <String, dynamic>{};
    for (final entry in body.entries) {
      const reservedKeys = {'error', 'message', 'suggestion'};
      if (!reservedKeys.contains(entry.key)) {
        partialSource[entry.key] = entry.value;
      }
    }

    final partialEncoded = jsonEncode(partialSource);
    String partialData;
    if (partialEncoded.length <= remaining) {
      partialData = partialEncoded;
    } else {
      partialData =
          '${partialEncoded.substring(0, remaining - _truncatedSuffix.length)}$_truncatedSuffix';
    }

    return {
      ...errorInfo,
      'partial_data': partialData,
    };
  }

  /// 正常分支：短字段豁免 + 长字段比例分配
  ///
  /// 算法：
  /// 1) 估算每个 value 序列化后的字符数
  /// 2) 序列化后 ≤ [shortFieldThreshold] 的字段标记为「短字段」，直接保留原值
  /// 3) 算短字段占用体积 [reservedSize]，从 [bodyBudget] 扣除 → 剩余给长字段
  /// 4) 仅长字段之间按体积比例分配剩余预算
  /// 5) 若短字段本身就超预算（极端情况），退化为全字段比例分配
  Map<String, dynamic> _trimNormalBody(
      Map<String, dynamic> body, int bodyBudget) {
    // 1. 估算每个 value 的大小，区分短/长字段
    final keys = body.keys.toList();
    final fieldSizes = <int>[];
    int reservedSize = 0; // 短字段占用体积
    int longTotal = 0; // 长字段占用体积
    final isShort = <bool>[];
    for (final k in keys) {
      final size = _estimateValueSize(body[k]);
      fieldSizes.add(size);
      final short = size <= shortFieldThreshold;
      isShort.add(short);
      if (short) {
        reservedSize += size;
      } else {
        longTotal += size;
      }
    }

    // 2. 全是短字段（理论上不会走到这，因为外层已判定超预算），或短字段本身就超预算
    //    → 退化为全字段比例分配
    if (longTotal == 0) {
      return _trimByRatio(body, keys, fieldSizes, bodyBudget);
    }

    // 3. 短字段保留原值，长字段按比例分食 (bodyBudget - reservedSize)
    final longBudget = bodyBudget - reservedSize;
    if (longBudget <= 0) {
      // 短字段就吃满了预算：长字段只能给最小占位
      final trimmed = <String, dynamic>{};
      for (int idx = 0; idx < keys.length; idx++) {
        trimmed[keys[idx]] = isShort[idx] ? body[keys[idx]] : null;
      }
      return trimmed;
    }

    // 4. 长字段按体积比例分配 longBudget
    final longKeys = <String>[];
    final longSizes = <int>[];
    for (int idx = 0; idx < keys.length; idx++) {
      if (!isShort[idx]) {
        longKeys.add(keys[idx]);
        longSizes.add(fieldSizes[idx]);
      }
    }
    final longTrimmed = _trimByKeys(longKeys, longSizes, body, longBudget);

    // 5. 合并：短字段原值 + 长字段裁剪值
    final trimmed = <String, dynamic>{};
    for (int idx = 0; idx < keys.length; idx++) {
      trimmed[keys[idx]] = isShort[idx] ? body[keys[idx]] : longTrimmed[keys[idx]];
    }
    return trimmed;
  }

  /// 全字段比例分配（退化路径）
  Map<String, dynamic> _trimByRatio(
      Map<String, dynamic> body, List<String> keys, List<int> sizes, int budget) {
    final trimmed = _trimByKeys(keys, sizes, body, budget);
    return trimmed;
  }

  /// 按指定 keys/sizes 比例分配 budget
  ///
  /// 预算只给 value 用。key + 字段分隔符（, : {}）的字符由调用方扣除（已乘 0.95）。
  Map<String, dynamic> _trimByKeys(
      List<String> keys, List<int> sizes, Map<String, dynamic> body, int budget) {
    // 算 keys + 结构字符的固定开销，从 budget 里扣除
    int keyOverhead = 0;
    for (final k in keys) {
      // "key":
      keyOverhead += k.length + 3;
    }
    // 字段间 ,（keys.length - 1 个）
    keyOverhead += keys.length - 1;
    final valueBudget = budget - keyOverhead;
    if (valueBudget <= 0) {
      // 极端情况：仅 key 就超预算，全部置空
      return {for (final k in keys) k: null};
    }

    // 调整 sizes：让 sizes 总和等于 valueBudget
    final total = sizes.fold(0, (a, b) => a + b);
    final Map<String, int> fieldBudgets;
    if (total <= valueBudget) {
      // 总和不超预算：全部原样返回（保留结构）
      final trimmed = <String, dynamic>{};
      for (final k in keys) {
        trimmed[k] = _preserveValueStructure(body[k]);
      }
      return trimmed;
    }

    final ratio = valueBudget / total;
    fieldBudgets = {for (int i = 0; i < keys.length; i++) keys[i]: (sizes[i] * ratio).floor()};

    // 浮点取整微调，保证总和不超 valueBudget
    int allocated = fieldBudgets.values.fold(0, (a, b) => a + b);
    int i = 0;
    while (allocated > valueBudget && i < keys.length) {
      final k = keys[i];
      if (fieldBudgets[k]! > 0) {
        fieldBudgets[k] = fieldBudgets[k]! - 1;
        allocated--;
      }
      i++;
    }

    final trimmed = <String, dynamic>{};
    for (final k in keys) {
      trimmed[k] = _trimValue(body[k], fieldBudgets[k]!);
    }
    return trimmed;
  }

  /// 估算 value 序列化后的字符数（不实际序列化，快速估算）
  int _estimateValueSize(Object? value) {
    if (value == null) return 4; // "null"
    if (value is String) return value.length + 2; // +引号
    if (value is num || value is bool) return '$value'.length;
    if (value is List) {
      int sum = 2; // []
      for (final e in value) {
        sum += _estimateValueSize(e) + 1; // +逗号
      }
      return sum;
    }
    if (value is Map) {
      int sum = 2; // {}
      for (final entry in value.entries) {
        sum += (entry.key as String).length + 2; // "key"
        sum += _estimateValueSize(entry.value) + 3; // :和逗号
      }
      return sum;
    }
    return 20; // fallback
  }

  /// 递归保留结构（不裁剪）：仅处理内层 Map，其他原样返回
  ///
  /// 用于"总和不超预算"的快速路径，保证内层 Map 也走一遍递归以保留结构。
  Object? _preserveValueStructure(Object? value) {
    if (value is Map) {
      return _trimNormalBody(
          Map<String, dynamic>.from(value), maxChars);
    }
    return value;
  }

  /// 按指定字符预算裁剪 value
  ///
  /// [budget] 该 value 可占用的字符数（序列化后）。
  /// - String：截到 budget
  /// - List：累加保留能塞进预算的元素
  /// - Map：递归 [_trimNormalBody]（用 budget 作为内层 maxChars）
  /// - num/bool/null：原样返回
  Object? _trimValue(Object? value, int budget) {
    if (budget <= 0) {
      // 预算耗尽：返回最小占位
      return null;
    }
    if (value is String) {
      if (value.length + 2 <= budget) return value;
      final strBudget = budget - _truncatedSuffix.length - 2;
      if (strBudget <= 0) return '';
      return value.substring(0, strBudget) + _truncatedSuffix;
    }
    if (value is List) {
      final encoded = jsonEncode(value);
      if (encoded.length <= budget) return value;
      return _truncatedList(value, budget);
    }
    if (value is Map) {
      return _trimNormalBody(Map<String, dynamic>.from(value), budget);
    }
    // num / bool / null：无须裁剪
    return value;
  }

  /// 数组裁剪：从头累加，保留能塞进预算的元素
  ///
  /// [budget] 该数组可占用的字符数（序列化后）。
  List<dynamic> _truncatedList(List<dynamic> list, int budget) {
    if (list.isEmpty) return list;

    // 从头累加，找到最大可保留元素数
    int sum = 2; // []
    int keep = 0;
    for (final e in list) {
      final size = _estimateValueSize(e) + 1; // +逗号
      if (sum + size > budget - _truncatedSuffix.length) break;
      sum += size;
      keep++;
    }

    if (keep == 0) {
      // 一个元素都塞不下：尝试单元素深度裁剪
      final first = list[0];
      if (first is String) {
        return [_trimValue(first, budget)];
      }
      return [first]; // 占位，至少保留结构提示
    }

    return list.sublist(0, keep);
  }

  /// 拼回 __meta（作为顶层 JSON key，保持结构纯净）
  String _withMeta(String encoded, Map<String, dynamic> meta) {
    final body = jsonDecode(encoded) as Map<String, dynamic>;
    body['__meta'] = meta;
    return jsonEncode(body);
  }
}
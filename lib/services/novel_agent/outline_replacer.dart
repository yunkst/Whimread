/// 大纲片段替换器 — Agent update_outline 工具的容错匹配核心
///
/// 移植自 opencode 的 edit 工具（packages/opencode/src/tool/edit.ts），
/// 把 9 重 Replacer + Levenshtein 相似度 + 唯一性校验整套机制搬过来，
/// 用于在「现有大纲内容」里定位 AI 给出的 oldString 并替换为 newString。
///
/// 设计要点（与 opencode edit 完全一致）：
/// - 不按行号定位，避免行号漂移；纯靠 oldString 在 content 里匹配。
/// - 9 个 Replacer 按从严到松顺序尝试，每个 yield 出「真实命中串」候选。
/// - 非 replaceAll 时，候选串必须在 content 中唯一出现才算数；
///   某个 Replacer 找到多个匹配则跳过它，继续试下一个更宽松的。
/// - 全部试完仍无命中 → not_found；有命中但都歧义 → ambiguous。
library;

import 'dart:math' as math;

/// Replacer：在 content 中找出与 find 对应的「真实命中串」候选（可能多个）。
typedef Replacer = Iterable<String> Function(String content, String find);

// 相似度阈值（移植自 opencode edit.ts:150-151）
const double _singleCandidateSimilarityThreshold = 0.0;
const double _multipleCandidatesSimilarityThreshold = 0.3;

/// Levenshtein 编辑距离（移植自 opencode edit.ts:156-172）
int _levenshtein(String a, String b) {
  if (a.isEmpty || b.isEmpty) {
    return math.max(a.length, b.length);
  }
  // 矩阵大小 (a.length+1) x (b.length+1)
  final matrix = List<List<int>>.generate(
    a.length + 1,
    (i) => List<int>.generate(
      b.length + 1,
      (j) => i == 0 ? j : (j == 0 ? i : 0),
    ),
  );

  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = math.min(
        math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
        matrix[i - 1][j - 1] + cost,
      );
    }
  }
  return matrix[a.length][b.length];
}

/// 1. 字面精确匹配（opencode SimpleReplacer）
Replacer simpleReplacer = (content, find) sync* {
  yield find;
};

/// 2. 逐行 trim 后匹配（opencode LineTrimmedReplacer）
///
/// 逐行比较 trim 后内容，命中时回推真实下标，yield 原文中的对应片段
/// （保留原始空白，便于精确替换）。
Replacer lineTrimmedReplacer = (content, find) sync* {
  final originalLines = content.split('\n');
  var searchLines = find.split('\n');
  if (searchLines.isNotEmpty && searchLines.last.isEmpty) {
    searchLines = searchLines.sublist(0, searchLines.length - 1);
  }

  for (var i = 0; i <= originalLines.length - searchLines.length; i++) {
    var matches = true;
    for (var j = 0; j < searchLines.length; j++) {
      if (originalLines[i + j].trim() != searchLines[j].trim()) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;

    var matchStartIndex = 0;
    for (var k = 0; k < i; k++) {
      matchStartIndex += originalLines[k].length + 1;
    }
    var matchEndIndex = matchStartIndex;
    for (var k = 0; k < searchLines.length; k++) {
      matchEndIndex += originalLines[i + k].length;
      if (k < searchLines.length - 1) matchEndIndex += 1;
    }
    yield content.substring(matchStartIndex, matchEndIndex);
  }
};

/// 3. 首尾两行做锚点 + Levenshtein 相似度匹配中间（opencode BlockAnchorReplacer）
///
/// 至少 3 行才启用；收集首尾两行都命中的候选块，
/// 单候选用宽松阈值（0.0），多候选取最高相似且达 0.3 阈值者。
Replacer blockAnchorReplacer = (content, find) sync* {
  final originalLines = content.split('\n');
  var searchLines = find.split('\n');
  if (searchLines.length < 3) return;
  if (searchLines.isNotEmpty && searchLines.last.isEmpty) {
    searchLines = searchLines.sublist(0, searchLines.length - 1);
  }

  final firstLineSearch = searchLines.first.trim();
  final lastLineSearch = searchLines.last.trim();
  final searchBlockSize = searchLines.length;

  // 收集所有「首行 + 尾行」都命中的候选位置
  final candidates = <_Candidate>[];
  for (var i = 0; i < originalLines.length; i++) {
    if (originalLines[i].trim() != firstLineSearch) continue;
    for (var j = i + 2; j < originalLines.length; j++) {
      if (originalLines[j].trim() == lastLineSearch) {
        candidates.add(_Candidate(startLine: i, endLine: j));
        break; // 只取该首行之后第一个匹配的尾行
      }
    }
  }
  if (candidates.isEmpty) return;

  // 单候选：用宽松阈值
  if (candidates.length == 1) {
    final c = candidates.first;
    final actualBlockSize = c.endLine - c.startLine + 1;
    var similarity = 0.0;
    final linesToCheck =
        math.min(searchBlockSize - 2, actualBlockSize - 2); // 仅比较中间行
    if (linesToCheck > 0) {
      for (var j = 1;
          j < searchBlockSize - 1 && j < actualBlockSize - 1;
          j++) {
        final originalLine = originalLines[c.startLine + j].trim();
        final searchLine = searchLines[j].trim();
        final maxLen = math.max(originalLine.length, searchLine.length);
        if (maxLen == 0) continue;
        final distance = _levenshtein(originalLine, searchLine);
        similarity += (1 - distance / maxLen) / linesToCheck;
        if (similarity >= _singleCandidateSimilarityThreshold) break;
      }
    } else {
      similarity = 1.0; // 无中间行可比，靠锚点直接接受
    }
    if (similarity >= _singleCandidateSimilarityThreshold) {
      yield _sliceBlock(content, originalLines, c.startLine, c.endLine);
    }
    return;
  }

  // 多候选：取最高相似度，需达 0.3 阈值
  _Candidate? bestMatch;
  var maxSimilarity = -1.0;
  for (final c in candidates) {
    final actualBlockSize = c.endLine - c.startLine + 1;
    var similarity = 0.0;
    final linesToCheck =
        math.min(searchBlockSize - 2, actualBlockSize - 2);
    if (linesToCheck > 0) {
      for (var j = 1;
          j < searchBlockSize - 1 && j < actualBlockSize - 1;
          j++) {
        final originalLine = originalLines[c.startLine + j].trim();
        final searchLine = searchLines[j].trim();
        final maxLen = math.max(originalLine.length, searchLine.length);
        if (maxLen == 0) continue;
        final distance = _levenshtein(originalLine, searchLine);
        similarity += 1 - distance / maxLen;
      }
      similarity /= linesToCheck;
    } else {
      similarity = 1.0;
    }
    if (similarity > maxSimilarity) {
      maxSimilarity = similarity;
      bestMatch = c;
    }
  }
  if (bestMatch != null &&
      maxSimilarity >= _multipleCandidatesSimilarityThreshold) {
    yield _sliceBlock(content, originalLines, bestMatch.startLine,
        bestMatch.endLine);
  }
};

/// 4. 把所有空白折叠成单空格后再匹配（opencode WhitespaceNormalizedReplacer）
Replacer whitespaceNormalizedReplacer = (content, find) sync* {
  String normalizeWhitespace(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final normalizedFind = normalizeWhitespace(find);

  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (normalizeWhitespace(line) == normalizedFind) {
      yield line;
    } else if (normalizeWhitespace(line).contains(normalizedFind)) {
      // 子串匹配：在原文行里定位与 find 单词序列匹配的片段
      final words = find.trim().split(RegExp(r'\s+'));
      if (words.isNotEmpty) {
        final pattern = words
            .map((w) => RegExp.escape(w))
            .join(r'\s+');
        try {
          final regex = RegExp(pattern);
          final match = regex.firstMatch(line);
          if (match != null) yield match.group(0)!;
        } catch (_) {
          // 非法正则，跳过
        }
      }
    }
  }

  final findLines = find.split('\n');
  if (findLines.length > 1) {
    for (var i = 0; i <= lines.length - findLines.length; i++) {
      final block = lines.sublist(i, i + findLines.length);
      if (normalizeWhitespace(block.join('\n')) == normalizedFind) {
        yield block.join('\n');
      }
    }
  }
};

/// 5. 去掉公共最小缩进后再匹配（opencode IndentationFlexibleReplacer）
Replacer indentationFlexibleReplacer = (content, find) sync* {
  String removeIndentation(String text) {
    final lines = text.split('\n');
    final nonEmptyLines =
        lines.where((l) => l.trim().isNotEmpty).toList();
    if (nonEmptyLines.isEmpty) return text;
    var minIndent = nonEmptyLines
        .map((l) {
          final m = RegExp(r'^(\s*)').firstMatch(l);
          return m == null ? 0 : m.group(1)!.length;
        })
        .reduce(math.min);
    return lines
        .map((l) => l.trim().isEmpty ? l : l.substring(minIndent))
        .join('\n');
  }

  final normalizedFind = removeIndentation(find);
  final contentLines = content.split('\n');
  final findLines = find.split('\n');

  for (var i = 0; i <= contentLines.length - findLines.length; i++) {
    final block = contentLines.sublist(i, i + findLines.length).join('\n');
    if (removeIndentation(block) == normalizedFind) {
      yield block;
    }
  }
};

/// 6. 处理转义符差异（opencode EscapeNormalizedReplacer）
///
/// 把 \n \t \" 等转义序列还原后比较，命中时 yield 原文中的对应片段。
Replacer escapeNormalizedReplacer = (content, find) sync* {
  String unescape(String str) {
    return str.replaceAllMapped(
      RegExp(r'\\(.)'),
      (m) {
        final c = m.group(1);
        switch (c) {
          case 'n':
            return '\n';
          case 't':
            return '\t';
          case 'r':
            return '\r';
          case "'":
            return "'";
          case '"':
            return '"';
          case '`':
            return '`';
          case '\\':
            return '\\';
          case r'$':
            return r'$';
          default:
            // 反斜杠后跟其它字符(含字面换行等)→ 保持原文
            return m.group(0)!;
        }
      },
    );
  }

  final unescapedFind = unescape(find);

  // 直接用还原后的 find 去原文里找
  if (content.contains(unescapedFind)) {
    yield unescapedFind;
  }

  // 也尝试在原文里找「还原后等于 unescapedFind」的片段
  final lines = content.split('\n');
  final findLines = unescapedFind.split('\n');
  for (var i = 0; i <= lines.length - findLines.length; i++) {
    final block = lines.sublist(i, i + findLines.length).join('\n');
    if (unescape(block) == unescapedFind) {
      yield block;
    }
  }
};

/// 7. 整体 trim 后匹配（opencode TrimmedBoundaryReplacer）
Replacer trimmedBoundaryReplacer = (content, find) sync* {
  final trimmedFind = find.trim();
  if (trimmedFind == find) return; // 本身已 trim，没意义

  if (content.contains(trimmedFind)) {
    yield trimmedFind;
  }

  final lines = content.split('\n');
  final findLines = find.split('\n');
  for (var i = 0; i <= lines.length - findLines.length; i++) {
    final block = lines.sublist(i, i + findLines.length).join('\n');
    if (block.trim() == trimmedFind) {
      yield block;
    }
  }
};

/// 8. 首尾锚点 + 中间 50% 行相似（opencode ContextAwareReplacer）
///
/// 与 BlockAnchorReplacer 类似，但要求块行数 == find 行数，
/// 且中间非空行有 ≥50% 逐字相等才接受。
Replacer contextAwareReplacer = (content, find) sync* {
  var findLines = find.split('\n');
  if (findLines.length < 3) return;
  if (findLines.last.isEmpty) findLines = findLines.sublist(0, findLines.length - 1);

  final contentLines = content.split('\n');
  final firstLine = findLines.first.trim();
  final lastLine = findLines.last.trim();

  for (var i = 0; i < contentLines.length; i++) {
    if (contentLines[i].trim() != firstLine) continue;
    for (var j = i + 2; j < contentLines.length; j++) {
      if (contentLines[j].trim() != lastLine) continue;
      final blockLines = contentLines.sublist(i, j + 1);
      final block = blockLines.join('\n');
      if (blockLines.length != findLines.length) break;
      var matchingLines = 0;
      var totalNonEmptyLines = 0;
      for (var k = 1; k < blockLines.length - 1; k++) {
        final blockLine = blockLines[k].trim();
        final findLine = findLines[k].trim();
        if (blockLine.isNotEmpty || findLine.isNotEmpty) {
          totalNonEmptyLines++;
          if (blockLine == findLine) matchingLines++;
        }
      }
      if (totalNonEmptyLines == 0 ||
          matchingLines / totalNonEmptyLines >= 0.5) {
        yield block;
      }
      break;
    }
  }
};

/// 9. 配合 replaceAll，产出所有字面匹配（opencode MultiOccurrenceReplacer）
Replacer multiOccurrenceReplacer = (content, find) sync* {
  var startIndex = 0;
  while (true) {
    final index = content.indexOf(find, startIndex);
    if (index == -1) break;
    yield find;
    startIndex = index + find.length;
  }
};

/// 替换失败异常。reason 区分 not_found / ambiguous，供 executor 返回不同 error code。
class OutlineEditException implements Exception {
  /// 'not_found' | 'ambiguous'
  final String reason;
  final String message;

  const OutlineEditException._(this.reason, this.message);

  factory OutlineEditException.notFound(String oldString) =>
      OutlineEditException._(
        'not_found',
        'oldString not found in content',
      );

  factory OutlineEditException.ambiguous() => const OutlineEditException._(
        'ambiguous',
        'Found multiple matches for oldString. '
        'Provide more surrounding lines in oldString to identify the correct match.',
      );

  @override
  String toString() => message;
}

/// 候选块（首行 + 尾行锚点）
class _Candidate {
  final int startLine;
  final int endLine;
  const _Candidate({required this.startLine, required this.endLine});
}

/// 按行号切出 content 的子串（含行间 \n），供 BlockAnchor/ContextAware 使用。
String _sliceBlock(String content, List<String> lines, int startLine, int endLine) {
  var matchStartIndex = 0;
  for (var k = 0; k < startLine; k++) {
    matchStartIndex += lines[k].length + 1;
  }
  var matchEndIndex = matchStartIndex;
  for (var k = startLine; k <= endLine; k++) {
    matchEndIndex += lines[k].length;
    if (k < endLine) matchEndIndex += 1;
  }
  return content.substring(matchStartIndex, matchEndIndex);
}

/// 在 [content] 中定位 [oldString] 并替换为 [newString]。
///
/// 算法与 opencode edit 的 replace() 一致：
/// - 按 9 个 Replacer 顺序尝试，每个 yield 出候选「真实命中串」。
/// - [replaceAll]=true 时：命中即用 `content.replaceAll(search, newString)` 返回。
/// - [replaceAll]=false 时：仅当候选串在 content 中唯一出现才替换；
///   某个 Replacer 找到多个匹配则跳过它继续试下一个。
/// - 全部试完仍无命中 → 抛 [OutlineEditException.notFound]。
/// - 有命中但都歧义 → 抛 [OutlineEditException.ambiguous]。
///
/// [oldString] 与 [newString] 相同时直接抛 [ArgumentError]（不应进入此函数）。
String replaceOutlineSnippet({
  required String content,
  required String oldString,
  required String newString,
  bool replaceAll = false,
}) {
  if (oldString == newString) {
    throw ArgumentError('oldString and newString must be different');
  }

  var notFound = true;

  for (final replacer in <Replacer>[
    simpleReplacer,
    lineTrimmedReplacer,
    blockAnchorReplacer,
    whitespaceNormalizedReplacer,
    indentationFlexibleReplacer,
    escapeNormalizedReplacer,
    trimmedBoundaryReplacer,
    contextAwareReplacer,
    multiOccurrenceReplacer,
  ]) {
    for (final search in replacer(content, oldString)) {
      final index = content.indexOf(search);
      if (index == -1) continue;
      notFound = false;
      if (replaceAll) {
        return content.replaceAll(search, newString);
      }
      final lastIndex = content.lastIndexOf(search);
      if (index != lastIndex) continue; // 多处命中且非 replaceAll → 跳过此 replacer
      return content.substring(0, index) +
          newString +
          content.substring(index + search.length);
    }
  }

  if (notFound) throw OutlineEditException.notFound(oldString);
  throw OutlineEditException.ambiguous();
}

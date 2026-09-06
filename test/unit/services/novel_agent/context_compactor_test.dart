/// ContextCompactor 单元测试
///
/// 覆盖场景：
/// 1. 禁用压缩时永不触发
/// 2. 未达阈值时不压缩
/// 3. 超过阈值时正确压缩
/// 4. system 消息始终保留
/// 5. 工具调用关联性不丢失
/// 6. 压缩率计算正确
/// 7. 边界情况：所有消息都很长
/// 8. 边界情况：消息列表为空
/// 9. P1 预剪枝：4 个高频工具的 1-liner 模板
/// 10. P1 预剪枝：保护区间 / 只动 tool / 不动 user-assistant-system
/// 11. P1 预剪枝：CompactionResult.rewrittenContent 契约
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/context_compactor.dart';

void main() {
  group('ContextCompactor.needsCompaction', () {
    test('禁用压缩时永不触发', () {
      final compactor = ContextCompactor(config: CompactorConfig.disabled);
      final messages = _buildLargeMessages(100000);
      expect(compactor.needsCompaction(messages), isFalse);
    });

    test('空消息列表不需要压缩', () {
      final compactor = ContextCompactor();
      expect(compactor.needsCompaction([]), isFalse);
    });

    test('小消息列表未达阈值', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(maxContextChars: 10000),
      );
      final messages = [
        ChatMessage(role: 'user', content: 'hello'),
        ChatMessage(role: 'assistant', content: 'hi'),
      ];
      expect(compactor.needsCompaction(messages), isFalse);
    });

    test('超阈值时触发压缩', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 1000,
          preserveTailChars: 500,
        ),
      );
      // 总字符数 > 1000
      final messages = _buildLargeMessages(1500);
      expect(compactor.needsCompaction(messages), isTrue);
    });

    test('双轨：realPromptTokens 超限 → true（即使字符数很小）', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(maxContextTokens: 1000),
      );
      const messages = [ChatMessage(role: 'user', content: 'hi')];
      // 真实 usage 优先，直接对照 token 阈值，绕过字符启发式
      expect(
          compactor.needsCompaction(messages, realPromptTokens: 1000), isTrue);
      expect(
          compactor.needsCompaction(messages, realPromptTokens: 999), isFalse);
    });

    test('双轨：无 usage 时走 CJK×2 启发式 token 估算', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 100000, // 字符阈值不触发
          maxContextTokens: 10,
        ),
      );
      // 5 个 CJK 字符 × 2 = 10 tokens ≥ 10 → 触发
      const messages = [ChatMessage(role: 'user', content: '你好世界呀')];
      expect(compactor.needsCompaction(messages), isTrue);
      // 4 个 CJK 字符 × 2 = 8 tokens < 10 → 不触发
      const small = [ChatMessage(role: 'user', content: '你好世界')];
      expect(compactor.needsCompaction(small), isFalse);
    });
  });

  group('ContextCompactor.compact', () {
    test('压缩后 system 消息始终保留在头部', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 1000,
          preserveTailChars: 200,
        ),
      );
      const systemPrompt = 'You are a helpful assistant.';
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        ..._buildLargeMessages(1500),
      ];

      final result = compactor.compact(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      // 第一个消息应该是 system
      expect(result.messages.first.role, 'system');
      expect(result.messages.first.content, systemPrompt);

      // 第二个消息应该是压缩提示
      expect(result.messages[1].role, 'system');
      expect(result.messages[1].content, contains('[上下文压缩|'));
    });

    test('压缩后丢弃早期消息，保留尾部', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 1000,
          preserveTailChars: 300,
        ),
      );
      const systemPrompt = 'system';
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        // 5 条 user 消息，每条 200 字符
        for (int i = 0; i < 5; i++)
          ChatMessage(role: 'user', content: 'msg_$i ${'x' * 200}'),
      ];

      final result = compactor.compact(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      // 至少丢弃 1 条
      expect(result.droppedMessageCount, greaterThan(0));
      // 至少保留 1 条
      expect(result.keptMessageCount, greaterThan(0));
      // 移除的字符数应该 > 0
      expect(result.removedChars, greaterThan(0));
      // 压缩率 > 0
      expect(result.compressionRatio, greaterThan(0));
    });

    test('工具调用关联性不丢失（保留尾部包含 tool_call）', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 1000,
          preserveTailChars: 800,
        ),
      );
      const systemPrompt = 'system';

      // 构造 tool_call 关联：assistant(tool_calls) + tool 响应
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: 'old msg ${'x' * 500}'),
        // 这对 tool_call 必须保留
        ChatMessage(
          role: 'assistant',
          content: null,
          toolCalls: [
            ToolCall(
              id: 'call_abc',
              name: 'list_novels',
              arguments: {},
            ),
          ],
        ),
        ChatMessage(
          role: 'tool',
          content: '{"novels": []}',
          toolCallId: 'call_abc',
        ),
      ];

      final result = compactor.compact(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      // 找到 tool 响应消息，确认 tool_call_id 仍在
      final toolMsg = result.messages
          .where((m) => m.role == 'tool' && m.toolCallId == 'call_abc')
          .toList();
      expect(toolMsg, hasLength(1),
          reason: 'tool_call_id 关联性必须保留');

      // 找到对应的 assistant tool_calls
      final assistantMsg = result.messages
          .where((m) =>
              m.role == 'assistant' &&
              m.toolCalls != null &&
              m.toolCalls!.any((tc) => tc.id == 'call_abc'))
          .toList();
      expect(assistantMsg, hasLength(1),
          reason: 'assistant tool_calls 必须保留');
    });

    test('所有消息都很长时也能正常压缩', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 1000,
          preserveTailChars: 100,
        ),
      );
      const systemPrompt = 'system';
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        for (int i = 0; i < 10; i++)
          ChatMessage(role: 'user', content: 'x' * 1000),
      ];

      final result = compactor.compact(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      // 不会无限循环或崩溃
      expect(result.messages, isNotEmpty);
      expect(result.compactedChars, lessThan(result.originalChars));
    });

    test('消息列表刚好在预算内时不丢弃任何消息', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 10000,
          preserveTailChars: 5000,
        ),
      );
      const systemPrompt = 'system';
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        for (int i = 0; i < 3; i++)
          ChatMessage(role: 'user', content: 'x' * 100),
      ];

      final result = compactor.compact(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      // 总字符数小，所有消息都保留（不含 system 消息）
      expect(result.droppedMessageCount, 0);
      expect(result.keptMessageCount, 4);
    });
  });

  group('CompactorConfig', () {
    test('copyWith 正确更新字段', () {
      const original = CompactorConfig();
      final updated = original.copyWith(enabled: false, maxContextChars: 1000);

      expect(updated.enabled, isFalse);
      expect(updated.maxContextChars, 1000);
      expect(updated.preserveTailChars, original.preserveTailChars);
    });

    test('disabled 常量正确禁用', () {
      expect(CompactorConfig.disabled.enabled, isFalse);
    });
  });

  group('500K 阈值默认配置', () {
    test('默认 maxContextChars 为 500000 (适配 128K 上下文窗口)', () {
      const config = CompactorConfig();
      expect(config.maxContextChars, 500000);
    });

    test('默认 preserveTailChars 为 100000 (20% 比例)', () {
      const config = CompactorConfig();
      expect(config.preserveTailChars, 100000);
    });

    test('默认配置下小消息列表不触发压缩', () {
      final compactor = ContextCompactor();
      // 普通 Agent 对话累积远达不到 500K
      final messages = List.generate(
        20,
        (i) => ChatMessage(
          role: i % 2 == 0 ? 'user' : 'assistant',
          content: 'normal message $i ${'x' * 1000}', // 每条约 1K
        ),
      );
      expect(compactor.needsCompaction(messages), isFalse);
    });
  });

  group('配对保护 (v32)', () {
    test('切点不切断 assistant(toolCalls) 与其 tool 结果', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 1000,
          preserveTailChars: 350,
        ),
      );
      const systemPrompt = 'sys';
      // 构造：old user(大) + assistant(toolCalls) + tool(result)
      // preserveTailChars=350 使候选切点落在 assistant 与 tool 之间，
      // 配对保护应把 assistant 也纳入保留段。
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: 'old ${'x' * 600}'),
        ChatMessage(
          role: 'assistant',
          content: null,
          toolCalls: [ToolCall(id: 'c1', name: 'list_novels', arguments: {})],
        ),
        ChatMessage(
            role: 'tool', content: '{"ok":true}', toolCallId: 'c1'),
      ];

      final result = compactor.compact(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      // 保留段里若存在 tool，则其 assistant(toolCalls) 必须也保留（配对完整）
      final retained = result.messages.where((m) => m.role != 'system').toList();
      if (retained.any((m) => m.role == 'tool')) {
        expect(retained.any((m) => m.role == 'assistant'), isTrue,
            reason: 'tool 存在则其 assistant(toolCalls) 必须也保留');
        final asst = retained.firstWhere(
            (m) => m.role == 'assistant' && (m.toolCalls?.isNotEmpty ?? false));
        for (final tc in asst.toolCalls!) {
          expect(
              retained.any((m) => m.role == 'tool' && m.toolCallId == tc.id),
              isTrue,
              reason: 'toolCall ${tc.id} 必须有对应的 tool 结果，否则 API 400');
        }
      }
    });

    test('droppedAgentFromIndex 等于实际丢弃的起始索引', () {
      final compactor = ContextCompactor(
        config: const CompactorConfig(
          maxContextChars: 1000,
          preserveTailChars: 200,
        ),
      );
      const systemPrompt = 'sys';
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        for (int i = 0; i < 6; i++)
          ChatMessage(role: 'user', content: 'msg_$i ${'x' * 200}'),
      ];

      final result = compactor.compact(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      if (result.droppedMessageCount > 0) {
        expect(result.droppedAgentFromIndex, result.droppedMessageCount);
        // compact 后保留段 = messages.sublist(droppedAgentFromIndex)
        final expectedTail = messages.sublist(result.droppedAgentFromIndex);
        final actualTail =
            result.messages.where((m) => m.role != 'system').toList();
        expect(actualTail.length, expectedTail.length);
      }
    });
  });

  // ============================================================
  // P1 预剪枝测试
  // ============================================================
  //
  // 通过 compact() 端到端验证 rewrittenContent + result.messages 改写结果。
  // 关键 helper：
  // - _buildToolPair(toolCallId, toolName, content)：生成 assistant(toolCalls) + tool(result) 配对
  // - _forceAllPreserved()：preserveTailChars 设很大，让 splitIndex=0（不丢弃任何消息），
  //   这样所有 tool result 都在"保留段"，预剪枝改写后的内容会出现在 result.messages 里
  //   便于断言；同时 tool result 总数 > protectRecentToolResults 时较老的会落入可改写区间。

  group('P1 预剪枝: 1-liner 模板', () {
    test('read_chapter_content 纯文本 → [read_chapter] N 字', () {
      // read_chapter 返回纯文本（非 JSON），1-liner 也应是纯文本
      final pair = _buildToolPair('c_read', 'read_chapter_content', 'x' * 3000);
      final messages = <ChatMessage>[...pair];
      final result = _compactAllPreserved(messages, protectRecent: 0);

      // 找到改写后的 tool 消息（在 result.messages 中 role=='tool' 的）
      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      expect(toolMsg.content, equals('[read_chapter] 3000 字'));
      expect(result.rewrittenContent, hasLength(1));
      expect(result.rewrittenContent.first.newContent,
          equals('[read_chapter] 3000 字'));
    });

    test('list_chapters → [list_chapters] N 章', () {
      final content = jsonEncode({
        'novel': {'id': 'n1'},
        'chapters': List.generate(50, (i) => {'position': i + 1, 'title': 'ch$i'}),
        'count': 50,
      });
      final pair = _buildToolPair('c_list', 'list_chapters', content);
      final result = _compactAllPreserved([...pair], protectRecent: 0);

      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      expect(jsonDecode(toolMsg.content!), equals('[list_chapters] 50 章'));
    });

    test('search_in_chapters → [search] 搜"K" 命中 N 章/M 处', () {
      final content = jsonEncode({
        'keyword': '伏笔',
        'totalChaptersHit': 3,
        'totalMatches': 7,
        'results': [],
      });
      final pair = _buildToolPair('c_search', 'search_in_chapters', content);
      final result = _compactAllPreserved([...pair],
          protectRecent: 0, longFieldChars: 1);

      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      expect(jsonDecode(toolMsg.content!), equals('[search] 搜"伏笔" 命中 3 章/7 处'));
    });

    test('execute_js register 模式 → [execute_js] register r-xxx', () {
      final content = jsonEncode({
        'title': 'something',
        '__meta': {'run_id': 'abc12345-def', 'mode': 'register', 'store_size': 10},
      });
      final pair = _buildToolPair('c_js1', 'execute_js', content);
      final result = _compactAllPreserved([...pair],
          protectRecent: 0, longFieldChars: 1);

      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      expect(jsonDecode(toolMsg.content!), equals('[execute_js] register r-abc12345'));
    });

    test('execute_js replay 模式 → [execute_js] replay r-xxx', () {
      final content = jsonEncode({
        '__meta': {'run_id': 'xyz98765', 'mode': 'replay', 'store_size': 5},
      });
      final pair = _buildToolPair('c_js2', 'execute_js', content);
      final result = _compactAllPreserved([...pair],
          protectRecent: 0, longFieldChars: 1);

      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      expect(jsonDecode(toolMsg.content!), equals('[execute_js] replay r-xyz98765'));
    });

    test('execute_js 错误分支保留 error/message', () {
      final content = jsonEncode({
        'error': 'JS_TIMEOUT',
        'message': '脚本执行超过 60 秒未返回',
      });
      final pair = _buildToolPair('c_js_err', 'execute_js', content);
      final result = _compactAllPreserved([...pair],
          protectRecent: 0, longFieldChars: 1);

      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      final decoded = jsonDecode(toolMsg.content!) as Map<String, dynamic>;
      expect(decoded['error'], equals('JS_TIMEOUT'));
      expect(decoded['message'], equals('脚本执行超过 60 秒未返回'));
    });

    test('未知工具名 → [toolName] (N 字符)', () {
      final pair = _buildToolPair('c_unknown', 'some_unknown_tool', 'x' * 1000);
      final result = _compactAllPreserved([...pair], protectRecent: 0);

      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      expect(jsonDecode(toolMsg.content!), equals('[some_unknown_tool] (1000 字符)'));
    });

    test('损坏 JSON → fallback 通用模板，不崩溃', () {
      // read_chapter_content 走纯文本分支（不以 { 开头也不 jsonDecode），所以用其他工具测损坏 JSON
      final pair = _buildToolPair('c_bad', 'list_chapters',
          '{"novel": ${'malformed' * 60}}'); // 长度 > longFieldChars=500
      final result = _compactAllPreserved([...pair],
          protectRecent: 0, longFieldChars: 500);

      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      // 用 [toolName] (N 字符) 兜底（safeJsonDecode 失败）
      final decoded = jsonDecode(toolMsg.content!) as String;
      expect(decoded, startsWith('[list_chapters] ('));
      expect(decoded, endsWith('字符)'));
    });
  });

  group('P1 预剪枝: 去重 (Pass 1 MD5)', () {
    test('相同 content > dedupThresholdChars 时最早的被替换为 [dup]，最后保留原文', () {
      // 2 对 tool pair，content 完全相同（>200 字符）
      final sameContent = jsonEncode({
        'novel': {'id': 'n'},
        'chapters': List.filled(300, 'x'), // 长到肯定 >200
        'count': 50,
      });
      final messages = <ChatMessage>[
        ..._buildToolPair('c1', 'list_chapters', sameContent),
        ..._buildToolPair('c2', 'list_chapters', sameContent),
      ];
      final result = _compactAllPreserved(messages,
          protectRecent: 0, longFieldChars: 1);

      // 期望：最早的一条（i=1）被去重为 dup 标记（指向 i=3）
      // 最后一条（i=3）保留原文 → 但 Pass 2 也会改写它，因为 longFieldChars=1
      // 这里要验证：最早的工具消息被 dedup 替换（包含 "dup of"，且指向最后一条的索引）
      expect(result.rewrittenContent.length, greaterThanOrEqualTo(1));

      final toolMsgs = result.messages.where((m) => m.role == 'tool').toList();
      // 最早的工具消息的 content 应包含 "dup of"，且指向最后一条（index=3）
      final firstContent = jsonDecode(toolMsgs[0].content!) as String;
      expect(firstContent, contains('dup of'));
      expect(firstContent, contains('3')); // dup of 3
    });

    test('不同 toolName 的相同 content 也按 content MD5 去重（设计决策）', () {
      // 按用户决策：去重只看 content MD5，不区分 toolName（更激进）
      final sameContent = jsonEncode({'x': 'y' * 300});
      final messages = <ChatMessage>[
        ..._buildToolPair('c1', 'list_chapters', sameContent),
        ..._buildToolPair('c2', 'search_in_chapters', sameContent),
      ];
      final result = _compactAllPreserved(messages,
          protectRecent: 0, longFieldChars: 1);

      // 第一条应被去重为 dup 标记
      final toolMsgs = result.messages.where((m) => m.role == 'tool').toList();
      final firstContent = jsonDecode(toolMsgs[0].content!) as String;
      expect(firstContent, contains('dup of'));
    });

    test('相同 content 但 < dedupThresholdChars 不触发去重', () {
      // 短 content（< 200 字符），完全相同
      final sameShort = 'OK';
      final messages = <ChatMessage>[
        ..._buildToolPair('c1', 'list_chapters', sameShort),
        ..._buildToolPair('c2', 'list_chapters', sameShort),
      ];
      // 长字段阈值设为 1，确保如果去重触发会变成 1-liner；dedup 阈值默认 200
      final result = _compactAllPreserved(messages,
          protectRecent: 0, longFieldChars: 1);

      // 因为 content 长度 2 < dedupThresholdChars=200，去重不触发
      // 但 longFieldChars=1，content 长度 2 > 1，Pass 2 1-liner 会触发
      // 验证：没有 dup 标记（两条都被 1-liner 化，不是 dedup）
      for (final m in result.messages.where((m) => m.role == 'tool')) {
        final content = jsonDecode(m.content!) as String;
        expect(content, isNot(contains('dup of')));
      }
    });

    test('单条 tool result 不会被去重（去重至少需要 2 条相同 content）', () {
      final content = jsonEncode({
        'novel': {'id': 'n'},
        'chapters': List.filled(300, 'x'),
        'count': 1,
      });
      final pair = _buildToolPair('c1', 'list_chapters', content);
      final result = _compactAllPreserved([...pair],
          protectRecent: 0, longFieldChars: 1);

      // 单条不会触发去重，但会被 1-liner 改写
      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      final content1 = jsonDecode(toolMsg.content!) as String;
      expect(content1, isNot(contains('dup of')));
      expect(content1, contains('[list_chapters]'));
    });
  });

  group('P1 预剪枝: 保护区间', () {
    test('最近 N 条 tool result 不被改写（N=6 默认）', () {
      // 构造 8 条 tool result（每条配对 assistant），全部 content > longFieldChars
      // protectRecentToolResults 默认 6 → 后 6 条不动，前 2 条被改写
      final messages = <ChatMessage>[];
      for (var i = 0; i < 8; i++) {
        messages.addAll(_buildToolPair('c_$i', 'list_chapters',
            jsonEncode({'count': i, 'chapters': List.filled(200, 'x')})));
      }
      final result = _compactAllPreserved(messages);

      // 找到所有 tool 消息（跳过压缩插入的 2 条 system）
      final toolMsgs = result.messages.where((m) => m.role == 'tool').toList();
      expect(toolMsgs, hasLength(8));
      // 前 2 条被改写为 1-liner
      expect(jsonDecode(toolMsgs[0].content!), contains('[list_chapters]'));
      expect(jsonDecode(toolMsgs[1].content!), contains('[list_chapters]'));
      // 后 6 条保留原文（含 chapters 数组）
      for (var i = 2; i < 8; i++) {
        final decoded = jsonDecode(toolMsgs[i].content!) as Map<String, dynamic>;
        expect(decoded.containsKey('chapters'), isTrue);
      }
    });

    test('protectRecentToolResults = 0 时全部 tool result 都被改写', () {
      final messages = <ChatMessage>[
        ..._buildToolPair('c1', 'list_chapters',
            jsonEncode({'count': 1, 'chapters': List.filled(200, 'x')})),
        ..._buildToolPair('c2', 'list_chapters',
            jsonEncode({'count': 2, 'chapters': List.filled(200, 'x')})),
      ];
      final compactor = ContextCompactor(config: const CompactorConfig(
        maxContextChars: 1, // 强制可压缩
        preserveTailChars: 1000000, // 强制全保留（splitIndex=0）
        protectRecentToolResults: 0,
      ));
      final result = compactor.compact(messages: messages, systemPrompt: 'sys');

      final toolMsgs = result.messages.where((m) => m.role == 'tool').toList();
      // 两条都被改写
      expect(result.rewrittenContent, hasLength(2));
      for (final m in toolMsgs) {
        expect(jsonDecode(m.content!), contains('[list_chapters]'));
      }
    });

    test('tool result 不足 N 条时全部保护（默认 N=6）', () {
      // 只构造 3 条 tool result（< 默认 6），全部应被保护
      final messages = <ChatMessage>[];
      for (var i = 0; i < 3; i++) {
        messages.addAll(_buildToolPair('c_$i', 'list_chapters',
            jsonEncode({'count': i, 'chapters': List.filled(200, 'x')})));
      }
      final result = _compactAllPreserved(messages);

      expect(result.rewrittenContent, isEmpty);
      final toolMsgs = result.messages.where((m) => m.role == 'tool').toList();
      for (final m in toolMsgs) {
        final decoded = jsonDecode(m.content!) as Map<String, dynamic>;
        expect(decoded.containsKey('chapters'), isTrue);
      }
    });

    test('user/assistant/system 消息的 content 不被改写', () {
      final longText = 'x' * 2000;
      final messages = <ChatMessage>[
        ChatMessage(role: 'user', content: longText),
        ChatMessage(role: 'assistant', content: longText),
        ..._buildToolPair('c1', 'list_chapters',
            jsonEncode({'count': 1, 'chapters': List.filled(200, 'x')})),
      ];
      final result = _compactAllPreserved(messages, protectRecent: 0);

      // user/assistant 的 content 应原样保留
      final userMsg = result.messages.firstWhere((m) => m.role == 'user');
      expect(userMsg.content, equals(longText));
      final assistantMsgs = result.messages.where((m) => m.role == 'assistant');
      // assistant(toolCalls) 的 content 可能为 null；带文本的 assistant 保留原文
      for (final m in assistantMsgs) {
        if (m.content != null) expect(m.content, equals(longText));
      }
      // 只改写了 tool（1 条）
      expect(result.rewrittenContent, hasLength(1));
    });
  });

  group('P1 预剪枝: CompactionResult 契约', () {
    test('rewrittenContent 字段填充且 index 准确（基于压缩前索引）', () {
      final messages = <ChatMessage>[];
      for (var i = 0; i < 8; i++) {
        messages.addAll(_buildToolPair('c_$i', 'list_chapters',
            jsonEncode({'count': i, 'chapters': List.filled(200, 'x')})));
      }
      final result = _compactAllPreserved(messages);

      // 前 2 条 tool result 在可改写区间，应被改写
      // tool result 在原 messages 的索引是 1, 3, 5, 7, 9, 11, 13, 15（每对占 2 条）
      expect(result.rewrittenContent, hasLength(2));
      expect(result.rewrittenContent[0].index, equals(1));
      expect(result.rewrittenContent[1].index, equals(3));
    });

    test('改写后的消息在 result.messages 中以 1-liner 形式存在', () {
      // content 长度需 > longFieldChars=500 才被改写
      final longResults = List.generate(50, (i) => {'position': i, 'snippet': 'x' * 20});
      final pair = _buildToolPair('c1', 'search_in_chapters', jsonEncode({
        'keyword': 'K',
        'totalChaptersHit': 1,
        'totalMatches': 2,
        'results': longResults,
      }));
      final result = _compactAllPreserved([...pair], protectRecent: 0);

      expect(result.rewrittenContent, isNotEmpty);
      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      // result.messages 中的 content 与 rewrittenContent[0].newContent 一致
      expect(toolMsg.content, equals(result.rewrittenContent.first.newContent));
    });

    test('prePruneEnabled = false 时跳过预剪枝（行为退化为 v32）', () {
      final pair = _buildToolPair('c1', 'list_chapters',
          jsonEncode({'count': 1, 'chapters': List.filled(200, 'x')}));
      final compactor = ContextCompactor(config: const CompactorConfig(
        maxContextChars: 1,
        preserveTailChars: 1000000,
        prePruneEnabled: false,
      ));
      final result = compactor.compact(messages: [...pair], systemPrompt: 'sys');

      expect(result.rewrittenContent, isEmpty);
      // tool result 保留原文
      final toolMsg = result.messages.firstWhere((m) => m.role == 'tool');
      final decoded = jsonDecode(toolMsg.content!) as Map<String, dynamic>;
      expect(decoded.containsKey('chapters'), isTrue);
    });

    test('改写后 splitIndex 前移（同样 preserveTailChars 保留更多消息）', () {
      // 构造足够多消息，使未改写时 splitIndex > 0（会丢消息）
      final messages = <ChatMessage>[];
      for (var i = 0; i < 20; i++) {
        messages.addAll(_buildToolPair('c_$i', 'list_chapters',
            jsonEncode({'count': i, 'chapters': List.filled(500, 'x')})));
      }

      // 关闭预剪枝：splitIndex 偏大（丢更多）
      final offCompactor = ContextCompactor(config: const CompactorConfig(
        maxContextChars: 1,
        preserveTailChars: 5000,
        prePruneEnabled: false,
      ));
      final offResult = offCompactor.compact(messages: messages, systemPrompt: 'sys');

      // 开启预剪枝：老 tool result 缩成 1-liner，tail 能装更多消息 → splitIndex 更小
      final onCompactor = ContextCompactor(config: const CompactorConfig(
        maxContextChars: 1,
        preserveTailChars: 5000,
        prePruneEnabled: true,
      ));
      final onResult = onCompactor.compact(messages: messages, systemPrompt: 'sys');

      // 开启预剪枝后丢的消息数应 <= 关闭时
      expect(onResult.droppedMessageCount,
          lessThanOrEqualTo(offResult.droppedMessageCount));
      // 且确实发生了改写
      expect(onResult.rewrittenContent, isNotEmpty);
    });
  });
}

/// 构造 assistant(toolCalls) + tool(result) 配对
///
/// [toolCallId] 工具调用 ID
/// [toolName] 工具名（决定 1-liner 模板）
/// [content] tool result 的 content（JSON 文本或纯文本）
List<ChatMessage> _buildToolPair(
    String toolCallId, String toolName, String content) {
  return [
    ChatMessage(
      role: 'assistant',
      content: null,
      toolCalls: [
        ToolCall(id: toolCallId, name: toolName, arguments: {}),
      ],
    ),
    ChatMessage(
      role: 'tool',
      content: content,
      toolCallId: toolCallId,
    ),
  ];
}

/// 用"强制可压缩 + 强制全保留（splitIndex=0）"配置跑 compact
///
/// splitIndex=0 保证所有消息都进 result.messages（不丢），便于断言改写结果。
/// [protectRecent] 默认 6（与生产配置一致）；测试单条 tool pair 时可传 0
/// 让该条进入可改写区间。
/// [longFieldChars] 默认 500（与生产配置一致）；单 pair 模板测试的 content 长度
/// 通常较短，可传 1 让所有超 1 字符的 tool result 都触发 1-liner。
CompactionResult _compactAllPreserved(List<ChatMessage> messages,
    {int protectRecent = 6, int longFieldChars = 500}) {
  final compactor = ContextCompactor(config: CompactorConfig(
    maxContextChars: 1, // 强制 needsCompaction=true
    preserveTailChars: 1000000, // 巨大预算 → splitIndex=0（全保留）
    protectRecentToolResults: protectRecent,
    longFieldChars: longFieldChars,
  ));
  return compactor.compact(messages: messages, systemPrompt: 'sys');
}

/// 构建指定总字符数的消息列表
List<ChatMessage> _buildLargeMessages(int totalChars) {
  final messages = <ChatMessage>[];
  int remaining = totalChars;
  int idx = 0;
  while (remaining > 0) {
    final chunkSize = remaining > 100 ? 100 : remaining;
    messages.add(ChatMessage(
      role: idx % 2 == 0 ? 'user' : 'assistant',
      content: 'msg_$idx ${'x' * (chunkSize - 10)}',
    ));
    remaining -= chunkSize;
    idx++;
  }
  return messages;
}

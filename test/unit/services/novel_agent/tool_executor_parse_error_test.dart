/// ToolExecutor parse_error 短路链路测试
///
/// 验证 PR1 引入的 __parse_error 标记：
/// 1. args 含 __parse_error 标记 → ToolExecutor 立即返回 error=args_parse_failed
///    不进入 switch 分发；
/// 2. 短路对未知工具名同样生效（不报 unknown_tool）；
/// 3. 无标记的 args → 走正常 switch 分支。
///
/// 运行:
///   cd novel_app
///   flutter test test/unit/services/novel_agent/tool_executor_parse_error_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/services/dsl_engine/llm_provider.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

final _toolExecutorProvider = Provider<ToolExecutor>((ref) {
  return ToolExecutor(ref);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;

  setUp(() async {
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dbConnection = DatabaseConnection.forTesting(db);
    container = ProviderContainer(
      overrides: [
        databaseConnectionProvider.overrideWithValue(dbConnection),
      ],
    );
    executor = container.read(_toolExecutorProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('__parse_error 短路', () {
    test('含 __parse_error 标记的 args → 返回 error=args_parse_failed，不走 switch',
        () async {
      final args = {
        kArgsParseErrorKey: true,
        kArgsParseErrorDetailKey: 'FormatException: 缺右括号',
        kArgsRawPreviewKey: '{"position":1,"instruction":"未闭合',
      };

      final result = await executor.execute('create_chapter', args);
      final decoded = jsonDecode(result) as Map<String, dynamic>;

      expect(decoded['error'], 'args_parse_failed');
      expect(decoded['message'], contains('JSON'));
      expect(decoded['parse_error_detail'], 'FormatException: 缺右括号');
      expect(decoded['previous_args_preview'],
          '{"position":1,"instruction":"未闭合');
      expect(decoded['suggested_action'], contains('重新调用 create_chapter'));
    });

    test('__parse_error + 未知工具名 → 仍走短路（而非 unknown_tool）', () async {
      final args = {
        kArgsParseErrorKey: true,
        kArgsParseErrorDetailKey: 'x',
        kArgsRawPreviewKey: 'y',
      };
      final result = await executor.execute('totally_unknown_tool', args);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['error'], 'args_parse_failed');
    });

    test('无 __parse_error 标记 → 走正常 switch 分支（list_novels 无参可调）',
        () async {
      // list_novels 在 ToolExecutor 里是无需参数的合法工具
      final result = await executor.execute('list_novels', const {});
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded.containsKey('error'), false);
      expect(decoded['novels'], isA<List>());
      expect(decoded['count'], isA<int>());
    });

    test('__parse_error 标记但 detail/preview 缺失 → 不崩溃，使用 fallback',
        () async {
      // 只含 __parse_error 标记，无 detail/preview
      final args = {kArgsParseErrorKey: true};
      final result = await executor.execute('select_novel', args);
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['error'], 'args_parse_failed');
      expect(decoded['parse_error_detail'], '未知错误');
      expect(decoded['previous_args_preview'], '');
    });
  });
}
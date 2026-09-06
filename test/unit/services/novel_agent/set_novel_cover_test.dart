import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/interfaces/repositories/i_novel_repository.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

/// set_novel_cover 工具执行器测试。
/// 复用 text2img_tools_test 的 ProviderContainer + 真实内存 DB 模式。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final toolExecutorProvider =
      Provider<ToolExecutor>((ref) => ToolExecutor(ref));

  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;
  late INovelRepository novelRepo;
  late int novelId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
    ]);
    executor = container.read(toolExecutorProvider);
    novelRepo = container.read(novelRepositoryProvider);
    novelId = await container
        .read(bookshelfMutationProvider.notifier)
        .addNovel(
          Novel(title: '封面测试书', author: '作者', url: 'custom://cover-test'),
        );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Map<String, dynamic> decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  test('成功设置封面 mediaId', () async {
    final ctx = AgentScenarioContext(currentNovelId: novelId);
    final json = decode(await executor.execute(
      'set_novel_cover',
      {'mediaId': 'cover-1'},
      scenarioContext: ctx,
    ));

    expect(json['success'], true);
    expect(json['coverMediaId'], 'cover-1');
    expect(json['cleared'], false);

    final novel = await novelRepo.getNovelById(novelId);
    expect(novel?.coverMediaId, 'cover-1');
  });

  test('mediaId 传 null 清空封面', () async {
    await novelRepo.updateCoverMediaIdById(novelId, 'pre-existing');
    final ctx = AgentScenarioContext(currentNovelId: novelId);

    final json = decode(await executor.execute(
      'set_novel_cover',
      {'mediaId': null},
      scenarioContext: ctx,
    ));

    expect(json['success'], true);
    expect(json['cleared'], true);
    final novel = await novelRepo.getNovelById(novelId);
    expect(novel?.coverMediaId, isNull);
  });

  test('无当前小说返回 no_current_novel 引导', () async {
    final json = decode(await executor.execute(
      'set_novel_cover',
      {'mediaId': 'cover-1'},
      scenarioContext: const AgentScenarioContext(),
    ));

    expect(json['error'], 'no_current_novel');
    expect(json['suggested_tool'], 'list_novels');
  });

  test('未传 scenarioContext 同样返回 no_current_novel', () async {
    final json = decode(await executor.execute(
      'set_novel_cover',
      {'mediaId': 'cover-1'},
    ));

    expect(json['error'], 'no_current_novel');
  });
}

/// create_images 角色图集入集测试
///
/// 覆盖 create_images 新增的 character 参数链路：
/// - 指定角色：生成的 mediaIds 全部写入 character_images，成功 JSON 带
///   character / addedToGallery 标记
/// - prompt 不做任何自动拼接（角色的 facePrompts/bodyPrompts 由 LLM
///   自行写进 prompt，执行器原样透传）
/// - 角色不存在 → character_not_found 引导错误
/// - 未选小说就传 character → no_current_novel 引导错误
/// - 不传 character：行为不变（不写图集）
///
/// 生图后端用 fake ImageGenerationBackend override，请求会被记录下来
/// 供断言 prompt 透传结果。容器搭建对齐 text2img_tools_test.dart。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/bookshelf_mutation_provider.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/image_model_providers.dart';
import 'package:novel_app/core/providers/character_providers.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/models/novel.dart';
import 'package:novel_app/repositories/image_model_repository.dart';
import 'package:novel_app/services/image_generation/image_generation_backend.dart';
import 'package:novel_app/services/image_generation/image_generation_providers.dart';
import 'package:novel_app/services/novel_agent/agent_scenario.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

final _toolExecutorProvider =
    Provider<ToolExecutor>((ref) => ToolExecutor(ref));

/// 记录请求并返回固定 mediaIds 的假后端（覆盖全部 backendType）
class _FakeBackend implements ImageGenerationBackend {
  final List<ImageGenerationRequest> requests = [];

  @override
  String get id => 'fake';

  @override
  bool supports(ImageModelBackendType type) => true;

  @override
  Future<String?> validate(ImageModel model) async => null;

  @override
  Future<ImageGenerationResult> submit(
    ImageGenerationRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    requests.add(request);
    return ImageGenerationResult(
      mediaIds: List.generate(request.count, (i) => 'gen_${requests.length}_$i'),
      modelName: request.model.name,
    );
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;
  late ImageModelRepository imageRepo;
  late int novelId;
  late _FakeBackend fakeBackend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    fakeBackend = _FakeBackend();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
      imageGenerationBackendByTypeProvider
          .overrideWith((ref, type) => fakeBackend),
    ]);
    executor = container.read(_toolExecutorProvider);
    imageRepo = container.read(imageModelRepositoryProvider);
    novelId = await container
        .read(bookshelfMutationProvider.notifier)
        .addNovel(
          Novel(title: '图集测试书', author: '作者', url: 'custom://gallery-t2i'),
        );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Map<String, dynamic> decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  Future<void> insertModel() async {
    final now = DateTime.now();
    await imageRepo.save(ImageModel(
      name: '测试模型',
      isEnabled: true,
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<int> insertCharacter({
    required String name,
    String? facePrompts,
    String? bodyPrompts,
  }) {
    return container.read(characterRepositoryProvider).createCharacter(
          Character(
            novelUrl: 'custom://gallery-t2i',
            name: name,
            facePrompts: facePrompts,
            bodyPrompts: bodyPrompts,
          ),
        );
  }

  Future<List<Map<String, dynamic>>> galleryRows(int characterId) =>
      db.query('character_images',
          where: 'characterId = ?',
          whereArgs: [characterId],
          orderBy: 'sort ASC, id ASC');

  test('指定角色：原样透传 prompt（不自动拼接 face/body），全部入集', () async {
    await insertModel();
    final characterId = await insertCharacter(
      name: '林雪',
      facePrompts: 'blue eyes, silver hair',
      bodyPrompts: 'tall, slim',
    );
    final ctx = AgentScenarioContext(currentNovelId: novelId);

    final json = decode(await executor.execute('create_images', {
      'prompt': 'standing in a garden, blue eyes, silver hair',
      'character': '林雪',
      'count': 2,
    }, scenarioContext: ctx));

    expect(json['success'], true);
    expect(json['message'], contains('林雪'));

    // prompt 原样透传（角色特征由 LLM 自行写入，执行器不追加）
    expect(fakeBackend.requests, hasLength(1));
    expect(
      fakeBackend.requests.single.prompt,
      'standing in a garden, blue eyes, silver hair',
    );

    // 全部入集
    final rows = await galleryRows(characterId);
    expect(rows, hasLength(2));
    expect(rows.map((r) => r['mediaId']).toList(),
        ['gen_1_0', 'gen_1_1']);

    // JSON 标记
    final images = (json['images'] as List).cast<Map<String, dynamic>>();
    expect(images.every((img) => img['character'] == '林雪'), isTrue);
    expect(images.every((img) => img['addedToGallery'] == true), isTrue);
  });

  test('角色不存在 → character_not_found 引导', () async {
    await insertModel();
    final ctx = AgentScenarioContext(currentNovelId: novelId);

    final json = decode(await executor.execute('create_images', {
      'prompt': 'p',
      'character': '不存在的人',
    }, scenarioContext: ctx));

    expect(json['error'], 'character_not_found');
    expect(json['suggested_tool'], 'list_characters');
    expect(fakeBackend.requests, isEmpty);
  });

  test('未选小说就传 character → no_current_novel 引导', () async {
    await insertModel();
    await insertCharacter(name: '林雪');

    final json = decode(await executor.execute('create_images', {
      'prompt': 'p',
      'character': '林雪',
    }));

    expect(json['error'], 'no_current_novel');
    expect(fakeBackend.requests, isEmpty);
  });

  test('不传 character：行为不变（prompt 原样、不写图集）', () async {
    await insertModel();
    await insertCharacter(name: '林雪', facePrompts: 'blue eyes');
    final ctx = AgentScenarioContext(currentNovelId: novelId);

    final json = decode(await executor.execute('create_images', {
      'prompt': 'a landscape',
    }, scenarioContext: ctx));

    expect(json['success'], true);
    expect(fakeBackend.requests.single.prompt, 'a landscape');
    final images = (json['images'] as List).cast<Map<String, dynamic>>();
    expect(images.first.containsKey('addedToGallery'), isFalse);
    final rows = await db.query('character_images');
    expect(rows, isEmpty);
  });
}

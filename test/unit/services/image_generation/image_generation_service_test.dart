/// ImageGenerationService（生图统一提交门面）单元测试
///
/// 覆盖：参数校验（empty_prompt / invalid_aspect_ratio）、模型选取错误码
/// 透传（model_not_found / model_disabled）、异常→错误码映射
/// （engine_not_ready / generation_failed）、count 限幅与负向提示词取模型
/// 预设。后端用注入的 fake 捕获请求。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/image_model_providers.dart';
import 'package:novel_app/core/providers/services/network_service_providers.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/repositories/image_model_repository.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/image_generation/image_generation_backend.dart';
import 'package:novel_app/services/image_generation/image_generation_providers.dart';
import 'package:novel_app/services/image_generation/image_generation_service.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

/// 可编程 fake 后端：记录请求、按脚本返回/抛错
class _FakeBackend implements ImageGenerationBackend {
  final List<ImageGenerationRequest> received = [];
  Object? Function(ImageGenerationRequest request)? behavior;

  @override
  String get id => 'local_dream_embedded';

  @override
  bool supports(ImageModelBackendType type) => true;

  @override
  Future<String?> validate(ImageModel model) async => null;

  @override
  Future<ImageGenerationResult> submit(
    ImageGenerationRequest request, {
    void Function(int step, int total)? onProgress,
  }) async {
    received.add(request);
    final behavior = this.behavior;
    if (behavior != null) {
      final outcome = behavior(request);
      if (outcome != null) throw outcome;
    }
    return ImageGenerationResult(
        mediaIds: const ['media-1'], modelName: request.model.name);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Database db;
  late ImageModelRepository repo;
  late _FakeBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    backend = _FakeBackend();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
      apiServiceWrapperProvider
          .overrideWithValue(_UnusedApiServiceWrapper()),
      imageGenerationBackendByTypeProvider(
              ImageModelBackendType.localDreamEmbedded)
          .overrideWithValue(backend),
    ]);
    repo = container.read(imageModelRepositoryProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  ImageGenerationService service() =>
      container.read(imageGenerationServiceProvider);

  Future<ImageModel> insertModel({
    required String name,
    bool isEnabled = true,
    bool isDefault = false,
    String negativePrompt = 'lowres, preset',
    String aspectRatio = '',
  }) async {
    final now = DateTime.now();
    final id = await repo.save(ImageModel(
      name: name,
      backendType: ImageModelBackendType.localDreamEmbedded,
      remoteModelId: 'sdxl',
      filePath: '/packs/$name',
      negativePrompt: negativePrompt,
      defaultAspectRatio: aspectRatio,
      isEnabled: isEnabled,
      isDefault: isDefault,
      createdAt: now,
      updatedAt: now,
    ));
    return (await repo.getById(id))!;
  }

  test('空 prompt → empty_prompt，后端不被调用', () async {
    final outcome = await service().generate(prompt: '   ');
    expect(outcome.ok, isFalse);
    expect(outcome.errorJson!['error'], 'empty_prompt');
    expect(backend.received, isEmpty);
  });

  test('aspect_ratio 非法 → invalid_aspect_ratio，合法比例放行', () async {
    await insertModel(name: '主力', isDefault: true);

    final outcome = await service().generate(prompt: 'p', aspectRatio: 'wide');
    expect(outcome.errorJson!['error'], 'invalid_aspect_ratio');

    // 合法比例放行
    final ok = await service().generate(prompt: 'p', aspectRatio: '3:4');
    expect(ok.ok, isTrue);
  });

  test('modelName 不存在 → 透传 model_not_found', () async {
    final outcome = await service().generate(prompt: 'p', modelName: '不存在');
    expect(outcome.errorJson!['error'], 'model_not_found');
  });

  test('模型停用 → 透传 model_disabled', () async {
    await insertModel(name: '停用', isEnabled: false);
    final outcome = await service().generate(prompt: 'p', modelName: '停用');
    expect(outcome.errorJson!['error'], 'model_disabled');
  });

  test('成功路径：count 限幅 + 负向词取模型预设 + mediaIds 透传', () async {
    final model = await insertModel(name: '主力', isDefault: true);

    final outcome = await service().generate(prompt: 'p', count: 9);

    expect(outcome.ok, isTrue);
    expect(outcome.result!.mediaIds, ['media-1']);
    expect(outcome.result!.modelName, '主力');
    expect(backend.received.single.count, 4);
    expect(backend.received.single.negativePrompt, 'lowres, preset');
    expect(backend.received.single.model.id, model.id);
  });

  test('LocalEngineNotReadyException → engine_not_ready', () async {
    await insertModel(name: '主力', isDefault: true);
    backend.behavior = (_) => const LocalEngineNotReadyException('引擎未打包');

    final outcome = await service().generate(prompt: 'p');

    expect(outcome.ok, isFalse);
    expect(outcome.errorJson!['error'], 'engine_not_ready');
    expect(outcome.errorJson!['message'], contains('引擎未打包'));
  });

  group('模型默认比例回退', () {
    test('未显式传 ratio 时使用模型预设', () async {
      await insertModel(name: '主力', isDefault: true, aspectRatio: '3:4');

      final outcome = await service().generate(prompt: 'p');

      expect(outcome.ok, isTrue);
      expect(backend.received.single.aspectRatio, '3:4');
    });

    test('显式传 ratio 覆盖模型预设', () async {
      await insertModel(name: '主力', isDefault: true, aspectRatio: '3:4');

      await service().generate(prompt: 'p', aspectRatio: '16:9');

      expect(backend.received.single.aspectRatio, '16:9');
    });

    test('模型预设为脏值（非法格式）时静默忽略', () async {
      await insertModel(name: '主力', isDefault: true, aspectRatio: 'wide');

      final outcome = await service().generate(prompt: 'p');

      expect(outcome.ok, isTrue);
      expect(backend.received.single.aspectRatio, isNull);
    });

    test('无预设且未传 → aspectRatio 为 null', () async {
      await insertModel(name: '主力', isDefault: true);

      await service().generate(prompt: 'p');

      expect(backend.received.single.aspectRatio, isNull);
    });
  });

  test('未知异常 → generation_failed 兜底', () async {
    await insertModel(name: '主力', isDefault: true);
    backend.behavior = (_) => StateError('boom');

    final outcome = await service().generate(prompt: 'p');

    expect(outcome.errorJson!['error'], 'generation_failed');
    expect(jsonEncode(outcome.errorJson), contains('boom'));
  });
}

class _UnusedApiServiceWrapper extends ApiServiceWrapper {}

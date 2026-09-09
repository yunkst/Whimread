/// ToolExecutor 文生图工具单元测试（纯客户端本地引擎模式）
///
/// 2026-09-09 ComfyUI 后端移除后 create_images / list_text2img_models 的行为：
/// - list_text2img_models 读 image_models 表（用户管理的本地模型元数据）
/// - create_images 统一分发到 LocalSdCppBackend：
///     · 模型文件缺失/损坏 → generation_failed
///     · 引擎未集成（阶段 A stub）→ engine_not_ready
/// - modelName 不存在 / 模型停用 / 无模型时返回结构化错误
///
/// 本地模型数据通过真实 ImageModelRepository 写入 in-memory SQLite。
///
/// 运行：
///   cd novel_app
///   flutter test test/unit/services/novel_agent/text2img_tools_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/image_model_providers.dart';
import 'package:novel_app/core/providers/services/network_service_providers.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/repositories/image_model_repository.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

// 用一个本地 Provider 让 ProviderContainer 暴露带 Ref 的 ToolExecutor
final _toolExecutorProvider =
    Provider<ToolExecutor>((ref) => ToolExecutor(ref));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;
  late ImageModelRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dbConnection = DatabaseConnection.forTesting(db);
    container = ProviderContainer(overrides: [
      // ApiServiceWrapper 仍需注入（ListTile 设置页等处间接依赖），但生图链路不再用它
      apiServiceWrapperProvider.overrideWithValue(_UnusedApiServiceWrapper()),
      databaseConnectionProvider.overrideWithValue(dbConnection),
    ]);
    executor = container.read(_toolExecutorProvider);
    repo = container.read(imageModelRepositoryProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Map<String, dynamic> decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  Future<ImageModel> insertModel({
    required String name,
    String description = '',
    List<String> tags = const [],
    String filePath = '',
    int fileSize = 0,
    bool isEnabled = true,
    bool isDefault = false,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now();
    final model = ImageModel(
      name: name,
      description: description,
      tags: tags,
      filePath: filePath,
      fileSize: fileSize,
      isEnabled: isEnabled,
      isDefault: isDefault,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    final id = await repo.save(model);
    return (await repo.getById(id))!;
  }

  /// 在临时目录写一个合法 gguf 文件（magic + ≥16 字节），返回路径
  String writeValidGguf() {
    final tmpDir = Directory.systemTemp.createTempSync('t2i_local_sd_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final ggufPath = p.join(tmpDir.path, 'fake.gguf');
    File(ggufPath).writeAsBytesSync(
        [0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x00, 0x00] +
            List<int>.filled(16, 0));
    return ggufPath;
  }

  // =========================================================================
  // list_text2img_models
  // =========================================================================
  group('list_text2img_models', () {
    test('返回本地模型列表（name/description/tags/isDefault/promptSkill）', () async {
      await insertModel(
        name: '古风水墨',
        description: '擅长中国古风水墨插画',
        tags: const ['古风', '水墨'],
        sortOrder: 0,
      );
      await insertModel(
        name: '写实人像',
        description: '擅长写实人脸',
        tags: const ['写实'],
        sortOrder: 1,
      );

      final json = decode(await executor.execute('list_text2img_models', {}));

      expect(json['error'], isNull);
      expect(json['count'], 2);
      final models = (json['models'] as List).cast<Map<String, dynamic>>();
      expect(models.first['name'], '古风水墨');
      expect(models.first['description'], '擅长中国古风水墨插画');
      expect(models.first['tags'], ['古风', '水墨']);
      expect(models.first['backendType'], 'local_sd');
      // promptSkill 由描述+标签拼出（含关键词）
      expect(models.first['promptSkill'], contains('古风'));
    });

    test('isDefault / defaultModelName 标记正确', () async {
      await insertModel(name: '甲', sortOrder: 0);
      await insertModel(name: '乙', isDefault: true, sortOrder: 1);

      final json = decode(await executor.execute('list_text2img_models', {}));

      expect(json['defaultModelName'], '乙');
      final models = (json['models'] as List).cast<Map<String, dynamic>>();
      expect(
        models.firstWhere((m) => m['name'] == '乙')['isDefault'],
        true,
      );
    });

    test('停用模型不出现在列表', () async {
      await insertModel(name: '可见');
      await insertModel(name: '不可见', isEnabled: false);

      final json = decode(await executor.execute('list_text2img_models', {}));

      final names =
          (json['models'] as List).map((m) => m['name']).toList();
      expect(names, ['可见']);
    });

    test('空列表时返回 count=0 且 message 引导去「生图模型管理」', () async {
      final json = decode(await executor.execute('list_text2img_models', {}));

      expect(json['count'], 0);
      expect(json['models'], isEmpty);
      final msg = json['message'] as String;
      expect(msg, contains('生图模型管理'));
    });
  });

  // =========================================================================
  // create_images - 模型选择
  // =========================================================================
  group('create_images - 模型选择', () {
    test('不传 modelName → 用默认模型（engine_not_ready 响应里带不出模型名，'
        '用 list 验证默认选取路径走到了引擎）', () async {
      await insertModel(name: '非默认', sortOrder: 0);
      await insertModel(
          name: '默认模型', isDefault: true, sortOrder: 1, filePath: writeValidGguf());

      // 默认模型文件合法 → 引擎未集成错误（说明选择逻辑走通）
      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
      }));

      expect(json['error'], 'engine_not_ready');
    });

    test('不传 modelName 且无默认 → 退回第一个启用模型', () async {
      await insertModel(name: '第一个', sortOrder: 0, filePath: writeValidGguf());

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
      }));

      expect(json['error'], 'engine_not_ready');
    });
  });

  // =========================================================================
  // create_images - 本地引擎（阶段 A：stub）
  // =========================================================================
  group('create_images - 本地引擎', () {
    test('模型文件不存在 → generation_failed', () async {
      await insertModel(
        name: '本地模型',
        filePath: '/tmp/nonexistent_gguf_${DateTime.now().microsecondsSinceEpoch}.gguf',
      );

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'modelName': '本地模型',
      }));

      expect(json['error'], 'generation_failed');
      expect(json['message'], contains('已丢失'));
    });

    test('模型文件存在 + gguf 头合法 → engine_not_ready（阶段 A stub）', () async {
      await insertModel(
        name: '本地模型',
        filePath: writeValidGguf(),
        fileSize: 24,
      );

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'modelName': '本地模型',
      }));

      expect(json['error'], 'engine_not_ready');
      expect(json['message'], contains('尚未集成'));
    });
  });

  // =========================================================================
  // create_images - 错误分支
  // =========================================================================
  group('create_images - 错误分支', () {
    test('modelName 不存在 → model_not_found 且列出可用模型', () async {
      await insertModel(name: '甲');

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'modelName': '不存在',
      }));

      expect(json['error'], 'model_not_found');
      expect(json['message'], contains('甲'));
    });

    test('模型已停用 → model_disabled', () async {
      await insertModel(name: '停用的', isEnabled: false);

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'modelName': '停用的',
      }));

      expect(json['error'], 'model_disabled');
    });

    test('无任何模型 → no_models_available 引导', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
      }));

      expect(json['error'], 'no_models_available');
      expect(json['message'], contains('生图模型管理'));
    });

    test('缺 prompt 返回 missing_arg 错误', () async {
      final json = decode(await executor.execute('create_images', {}));

      expect(json.containsKey('error'), true);
      expect(json['message'], contains('prompt'));
    });
  });
}

/// 占位 wrapper：生图链路已不走 ApiServiceWrapper，但 ToolExecutor 依赖图里
/// 部分 provider 仍会构造它，注入空实现避免触发真实网络初始化。
class _UnusedApiServiceWrapper extends ApiServiceWrapper {}
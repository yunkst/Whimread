/// ToolExecutor 文生图工具单元测试
///
/// 覆盖 list_text2img_models 与 create_images 两个工具：
/// - 正常路径（模型列表、单图/多图提交、imageId 格式、modelName 透传）
/// - count 边界 clamp 到 [1,4]
/// - 缺 prompt 参数错误
/// - backend 抛错时返回 backend_unavailable 引导
///
/// 用 _FakeApiServiceWrapper（继承 ApiServiceWrapper，仅重写 4 个文生图方法）
/// 通过 override apiServiceWrapperProvider 注入，不依赖真实网络。
///
/// 运行：
///   cd novel_app
///   flutter test test/unit/services/novel_agent/text2img_tools_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart';

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/services/network_service_providers.dart';
import 'package:novel_app/services/api_service_wrapper.dart';
import 'package:novel_app/services/novel_agent/tool_executor.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

// ──────────────────────────────────────────────────────────────────────
// Fake ApiServiceWrapper
// ──────────────────────────────────────────────────────────────────────

/// 仅重写 4 个文生图方法的假 ApiServiceWrapper。
/// 测试用例通过修改字段控制返回值/抛异常。
class _FakeApiServiceWrapper extends ApiServiceWrapper {
  _FakeApiServiceWrapper();

  // getText2ImgModels
  List<Map<String, dynamic>>? modelsResult;
  Object? modelsError;

  // submitText2ImgTask
  Object? submitError;
  int _submitCount = 0;
  String Function(int index)? taskIdFor;

  // fetchText2ImgImage
  (Uint8List?, int)? fetchResult;

  @override
  Future<List<Map<String, dynamic>>> getText2ImgModels() async {
    if (modelsError != null) throw modelsError!;
    return List<Map<String, dynamic>>.from(modelsResult ?? const []);
  }

  @override
  Future<String> submitText2ImgTask({
    required String prompt,
    String? modelName,
    String? negativePrompt,
  }) async {
    if (submitError != null) throw submitError!;
    // 计数器无条件递增，保证并发提交时每张图拿到不同 index
    final idx = _submitCount++;
    final gen = taskIdFor;
    if (gen != null) return gen(idx);
    return 'fake-task-$idx';
  }

  @override
  Future<(Uint8List?, int)> fetchText2ImgImage(String taskId) async {
    return fetchResult ?? (null, 202);
  }
}

// 用一个本地 Provider 让 ProviderContainer 暴露带 Ref 的 ToolExecutor
final _toolExecutorProvider =
    Provider<ToolExecutor>((ref) => ToolExecutor(ref));

// ──────────────────────────────────────────────────────────────────────
// 测试主体
// ──────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeApiServiceWrapper fakeApi;
  late ProviderContainer container;
  late ToolExecutor executor;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    final dbConnection = DatabaseConnection.forTesting(db);
    fakeApi = _FakeApiServiceWrapper();
    container = ProviderContainer(overrides: [
      apiServiceWrapperProvider.overrideWithValue(fakeApi),
      databaseConnectionProvider.overrideWithValue(dbConnection),
    ]);
    executor = container.read(_toolExecutorProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Map<String, dynamic> decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  // =========================================================================
  // list_text2img_models
  // =========================================================================
  group('list_text2img_models', () {
    test('正常返回模型列表（title→name 映射已在 ApiServiceWrapper 完成）', () async {
      fakeApi.modelsResult = [
        {'name': '动漫风17.5', 'description': '...', 'isDefault': true},
        {'name': '写实1', 'description': '...', 'isDefault': false},
      ];

      final json = decode(await executor.execute('list_text2img_models', {}));

      expect(json['error'], isNull);
      expect(json['count'], 2);
      final models = (json['models'] as List).cast<Map<String, dynamic>>();
      expect(models.first['name'], '动漫风17.5');
      expect(models.first['isDefault'], true);
    });

    test('空列表时返回 count=0 且带提示 message', () async {
      fakeApi.modelsResult = [];

      final json = decode(await executor.execute('list_text2img_models', {}));

      expect(json['error'], isNull);
      expect(json['count'], 0);
      expect(json['models'], isEmpty);
      expect(json['message'], isNotNull, reason: '空列表应附带引导提示');
    });

    test('backend 抛错时返回 backend_unavailable 引导', () async {
      // 配置 host → 走 _kBackendUnreachableMsg 分支（异常细节透传 + 含进阶提示）
      SharedPreferences.setMockInitialValues({'backend_host': 'http://test:3800'});
      fakeApi.modelsError = Exception('connection refused');

      final json = decode(await executor.execute('list_text2img_models', {}));

      expect(json['error'], 'backend_unavailable');
      expect(json['message'], contains('connection refused'));
      expect(json['message'], contains('进阶功能'));
      expect(json['message'], contains('设置 → 进阶服务 → 后端服务配置'));
    });
  });

  // =========================================================================
  // create_images
  // =========================================================================
  group('create_images - 正常路径', () {
    test('单图（count 不传默认 1）', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': '1girl, anime style',
      }));

      expect(json['success'], true);
      expect(json['count'], 1);
      final images = (json['images'] as List).cast<Map<String, dynamic>>();
      expect(images.length, 1);
      expect(images.first['prompt'], '1girl, anime style');
      // mediaId 即后端 task_id（统一句柄，不再有独立 imageId）
      expect(images.first['mediaId'], isA<String>());
      expect(images.first['mediaId'], 'fake-task-0');
    });

    test('多图（count=3）每张 taskId 独立、imageId 后缀递增', () async {
      fakeApi.taskIdFor = (i) => 'task-$i';

      final json = decode(await executor.execute('create_images', {
        'prompt': 'scene',
        'count': 3,
      }));

      expect(json['count'], 3);
      final images = (json['images'] as List).cast<Map<String, dynamic>>();
      expect(images.length, 3);
      // mediaId = 各任务独立 task_id
      expect(images.map((i) => i['mediaId']).toList(),
          ['task-0', 'task-1', 'task-2']);
    });

    test('modelName 透传到 images 元素', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'modelName': '写实1',
      }));

      final images = (json['images'] as List).cast<Map<String, dynamic>>();
      expect(images.first['modelName'], '写实1');
    });
  });

  group('create_images - count 边界 clamp 到 [1,4]', () {
    test('count=0 → 实际提交 1 张', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'count': 0,
      }));
      expect(json['count'], 1);
    });

    test('count=5 → clamp 到 4 张', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'count': 5,
      }));
      expect(json['count'], 4, reason: 'count 上限 4，防止 LLM 失控');
    });

    test('count=-1 → clamp 到 1 张', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'count': -1,
      }));
      expect(json['count'], 1);
    });

    test('count=4 边界值合法', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'count': 4,
      }));
      expect(json['count'], 4);
    });
  });

  group('create_images - 参数错误', () {
    test('缺 prompt 返回 missing_arg 错误', () async {
      final json = decode(await executor.execute('create_images', {}));

      expect(json['success'], isNull);
      expect(json.containsKey('error'), true);
      expect(json['message'], contains('prompt'));
    });

    test('prompt 为空字符串返回错误', () async {
      final json = decode(await executor.execute('create_images', {
        'prompt': '   ',
      }));

      expect(json.containsKey('error'), true);
    });
  });

  group('create_images - backend 失败', () {
    test('submit 抛错时返回 backend_unavailable', () async {
      // 配置 host → 走 _kBackendUnreachableMsg 分支（异常细节透传 + 含进阶提示）
      SharedPreferences.setMockInitialValues({'backend_host': 'http://test:3800'});
      fakeApi.submitError = Exception('ComfyUI offline');

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
        'count': 2,
      }));

      expect(json['error'], 'backend_unavailable');
      expect(json['message'], contains('ComfyUI offline'));
      expect(json.containsKey('success'), false,
          reason: '失败时不应伪装成功');
      expect(json['message'], contains('进阶功能'));
      expect(json['message'], contains('设置 → 进阶服务 → 后端服务配置'));
    });
  });

  // =========================================================================
  // 进阶功能文案（按 host 是否配置分两支）
  // =========================================================================
  group('create_images - 进阶功能文案', () {
    test('backend 抛错且 host 未配置时，文案含"进阶功能"和配置路径', () async {
      fakeApi.submitError = Exception('connection refused');
      // 默认 SharedPreferences mock 为空 → getHost() 返回 null

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
      }));

      expect(json['error'], 'backend_unavailable');
      final msg = json['message'] as String;
      expect(msg, contains('进阶功能'));
      expect(msg, contains('设置 → 进阶服务 → 后端服务配置'));
      expect(msg, contains('本地部署'));
    });

    test('backend 抛错且 host 已配置时，文案前缀带错误细节 + 同样含进阶提示', () async {
      SharedPreferences.setMockInitialValues({'backend_host': 'http://my-host:3800'});
      fakeApi.submitError = Exception('Connection timed out');

      final json = decode(await executor.execute('create_images', {
        'prompt': 'p',
      }));

      expect(json['error'], 'backend_unavailable');
      final msg = json['message'] as String;
      expect(msg, contains('Connection timed out'));
      expect(msg, contains('进阶功能'));
      expect(msg, contains('设置 → 进阶服务 → 后端服务配置'));
    });
  });
}

/// 匹配形如 img_{任意数字}_N 的列表（用于多图 imageId 后缀断言）
Matcher matchesImgIds(List<String> patterns) =>
    _ImageIdListMatcher(patterns);

class _ImageIdListMatcher extends Matcher {
  final List<String> patterns;
  _ImageIdListMatcher(this.patterns);

  @override
  bool matches(item, Map matchState) {
    if (item is! List) return false;
    if (item.length != patterns.length) return false;
    for (var i = 0; i < patterns.length; i++) {
      final regex =
          RegExp('^${patterns[i].replaceAll('*', r'\d+')}\$');
      if (!regex.hasMatch(item[i].toString())) return false;
    }
    return true;
  }

  @override
  Description describe(Description description) =>
      description.add('匹配 imageId 列表模式 $patterns');
}

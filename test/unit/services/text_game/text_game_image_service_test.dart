/// TextGameImageService（异步场景生图）测试
///
/// 覆盖：
/// - submitForTool 立即返回 submitted:true（不等待生成）
/// - 后台串行完成：backend 收到请求（prompt/count/negative 透传），
///   tool 消息被改写为含 mediaIds 的最终结果（与 create_images 结果同构）
/// - 生成失败：tool 消息改写为 error JSON，任务状态 failed
/// - 参数校验：空 prompt / 非法比例
/// - 串行队列：两个任务按提交顺序执行
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart' show Database;

import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/core/providers/database_providers.dart';
import 'package:novel_app/core/providers/image_model_providers.dart';
import 'package:novel_app/core/providers/text_game_providers.dart';
import 'package:novel_app/models/chat_message_record.dart';
import 'package:novel_app/models/chat_session.dart';
import 'package:novel_app/models/image_model.dart';
import 'package:novel_app/models/text_game.dart';
import 'package:novel_app/repositories/image_model_repository.dart';
import 'package:novel_app/services/image_generation/image_generation_backend.dart';
import 'package:novel_app/services/image_generation/image_generation_providers.dart';
import 'package:novel_app/services/text_game/text_game_image_service.dart';
import '../../../helpers/test_database_setup.dart' as test_db;

/// 可编排成功/失败的假后端
class _ScriptedBackend implements ImageGenerationBackend {
  final List<ImageGenerationRequest> requests = [];

  /// 每次 submit 弹出一个行为；空则默认成功
  final List<Completer<ImageGenerationResult>> completers = [];

  @override
  String get id => 'fake_scripted';

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
    if (completers.isNotEmpty) {
      return completers.removeAt(0).future;
    }
    return ImageGenerationResult(
      mediaIds: ['gen_${requests.length}'],
      modelName: request.model.name,
    );
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late Database db;
  late ProviderContainer container;
  late _ScriptedBackend backend;
  late TextGameImageService service;
  late int sessionId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await test_db.TestDatabaseSetup.createInMemoryDatabase();
    backend = _ScriptedBackend();
    container = ProviderContainer(overrides: [
      databaseConnectionProvider
          .overrideWithValue(DatabaseConnection.forTesting(db)),
      imageGenerationBackendByTypeProvider
          .overrideWith((ref, type) => backend),
    ]);
    service = container.read(textGameImageServiceProvider);

    // 建会话 + 一条 tool 消息（模拟 finalize 落库的 create_scene_image 结果）
    final sessionRepo = container.read(chatSessionRepositoryProvider);
    sessionId = await sessionRepo.createSession(
        ChatSession(scenarioId: 'text_game', title: 't'));
    await sessionRepo.appendMessage(ChatMessageRecord(
      sessionId: sessionId,
      role: 'assistant',
      content: '',
      toolCallsJson: '[{"id":"call_1","name":"create_scene_image",'
          '"arguments":{"prompt":"moonlit cliff"}}]',
      timestamp: DateTime.now(),
      agentMsgIndex: 0,
    ));
    await sessionRepo.appendMessage(ChatMessageRecord(
      sessionId: sessionId,
      role: 'tool',
      content: jsonEncode({'success': true, 'submitted': true, 'taskId': 'x'}),
      toolCallId: 'call_1',
      timestamp: DateTime.now(),
      agentMsgIndex: 1,
    ));

    // 启用一个默认生图模型
    final now = DateTime.now();
    await container.read(imageModelRepositoryProvider).save(ImageModel(
          name: '测试生图',
          isEnabled: true,
          isDefault: true,
          negativePrompt: 'blurry',
          createdAt: now,
          updatedAt: now,
        ));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<String> toolMessageContent() async {
    final records =
        await container.read(chatSessionRepositoryProvider).listMessages(sessionId);
    return records.firstWhere((r) => r.role == 'tool').content ?? '';
  }

  test('提交立即返回，后台完成后改写 tool 消息为最终结果', () async {
    final done = Completer<void>();
    service.onChanged.listen((_) {
      final t = service.taskByToolCallId('call_1');
      if (t?.status == TextGameImageTaskStatus.completed && !done.isCompleted) {
        done.complete();
      }
    });

    final reply = await service.submitForTool(
      chatSessionId: sessionId,
      toolCallId: 'call_1',
      args: {'prompt': 'moonlit cliff', 'aspect_ratio': '3:4'},
    );

    // 立即返回：submitted=true，不含 mediaIds
    final parsed = jsonDecode(reply) as Map<String, dynamic>;
    expect(parsed['submitted'], true);
    expect(parsed['taskId'], isNotNull);

    await done.future.timeout(const Duration(seconds: 5));

    // backend 收到的请求透传了 prompt / 比例 / 负向词 / count=1
    expect(backend.requests, hasLength(1));
    final req = backend.requests.first;
    expect(req.prompt, 'moonlit cliff');
    expect(req.aspectRatio, '3:4');
    expect(req.count, 1);
    expect(req.negativePrompt, 'blurry');

    // tool 消息被改写为最终结果（与 create_images 结果同构）
    final content = jsonDecode(await toolMessageContent()) as Map<String, dynamic>;
    expect(content['success'], true);
    expect((content['images'] as List).first['mediaId'], 'gen_1');
  });

  test('生成失败：任务 failed，tool 消息改写为 error JSON', () async {
    final c = Completer<ImageGenerationResult>();
    backend.completers.add(c);
    // 预挂监听：completeError 与 submit 内 await 之间若无人监听，
    // 会被测试 zone 判为 unhandled async error 直接判负
    unawaited(c.future.catchError((Object e) =>
        ImageGenerationResult(mediaIds: const [], modelName: 'x')));
    c.completeError(Exception('engine dead'));

    final failed = Completer<void>();
    service.onChanged.listen((_) {
      final t = service.taskByToolCallId('call_1');
      if (t?.status == TextGameImageTaskStatus.failed && !failed.isCompleted) {
        failed.complete();
      }
    });

    final reply = await service.submitForTool(
      chatSessionId: sessionId,
      toolCallId: 'call_1',
      args: {'prompt': 'p'},
    );
    expect((jsonDecode(reply) as Map<String, dynamic>)['submitted'], true);

    await failed.future.timeout(const Duration(seconds: 5));
    final content = jsonDecode(await toolMessageContent()) as Map<String, dynamic>;
    expect(content['error'], 'generation_failed');
  });

  test('参数校验：空 prompt / 非法比例 / 缺会话', () async {
    final empty = await service.submitForTool(
      chatSessionId: sessionId,
      toolCallId: 'call_1',
      args: {'prompt': ' '},
    );
    expect(empty, contains('empty_prompt'));

    final badRatio = await service.submitForTool(
      chatSessionId: sessionId,
      toolCallId: 'call_1',
      args: {'prompt': 'p', 'aspect_ratio': '16 by 9'},
    );
    expect(badRatio, contains('invalid_aspect_ratio'));

    final noSession = await service.submitForTool(
      chatSessionId: null,
      toolCallId: null,
      args: {'prompt': 'p'},
    );
    expect(noSession, contains('missing_session'));

    expect(backend.requests, isEmpty, reason: '校验失败不应触达后端');
  });

  test('串行队列：两个任务按提交顺序执行', () async {
    final first = Completer<ImageGenerationResult>();
    backend.completers.add(first);

    await service.submitForTool(
      chatSessionId: sessionId,
      toolCallId: 'call_1',
      args: {'prompt': 'first'},
    );
    // 第二个任务复用同一 toolCallId 的消息（简化：验证链顺序即可）
    final secondTaskId = jsonDecode(await service.submitForTool(
      chatSessionId: sessionId,
      toolCallId: 'call_2',
      args: {'prompt': 'second'},
    )) as Map<String, dynamic>;

    // 第一个任务未放行 → 第二个尚未开始（串行）
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(backend.requests, hasLength(1), reason: '第一个任务未完成前第二个不应开始');

    first.complete(ImageGenerationResult(mediaIds: ['g1'], modelName: '测试生图'));
    // 等待第二个任务也执行完
    for (var i = 0; i < 100 && backend.requests.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(backend.requests, hasLength(2));
    expect(backend.requests[1].prompt, 'second');
    expect(secondTaskId['taskId'], isNotNull);
  });
}

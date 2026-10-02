/// 文字游戏场景图异步生图服务
///
/// 与同步 create_images 的核心差异：工具调用只做「校验 + 选模型 + 入队」
/// 并立即返回，backend.submit 在后台串行链中执行——agent 不被数十秒的
/// 生成过程卡住，继续推进剧情；生成完成后自动改写剧情消息链里对应的
/// tool 消息内容（补上 mediaIds），游玩页监听 [onChanged] 实时渲染。
///
/// 状态真相：
/// - 运行中/本次 App 存活期内 → 本服务内存任务表（按 toolCallId 查）
/// - 跨重启 → chat_messages 里被改写的 tool 消息 content（hydrate 渲染）
///
/// 队列：串行 Future 链（端侧 NPU 引擎不支持并行；远程设备按提交顺序
/// 生成）。App 被杀时队列丢失——tool 消息保持「已提交」状态，游玩页
/// 显示生成中断占位，v1 不做重试。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novel_app/services/logger_service.dart';

import '../image_generation/image_generation_backend.dart';
import '../image_generation/image_generation_providers.dart';
import '../image_generation/image_model_picker.dart';
import '../image_generation/local_sd_backend.dart';
import '../../core/providers/database_providers.dart'
    show chatSessionRepositoryProvider;
import '../../core/providers/image_model_providers.dart'
    show imageModelRepositoryProvider;
import '../../models/image_model.dart';

/// 任务状态
enum TextGameImageTaskStatus { queued, running, completed, failed }

/// 一次场景图生成任务（内存态，App 生命周期内有效）
class TextGameImageTask {
  final String taskId;
  final int sessionId;
  final String toolCallId;
  final String prompt;
  final String? aspectRatio;
  final ImageModel model;
  TextGameImageTaskStatus status;
  List<String> mediaIds;
  String? error;

  /// 最终 tool 消息内容（completed/failed 后填充，与 DB 改写内容一致；
  /// 游玩页用它同步内存消息链）
  String? finalContent;

  TextGameImageTask({
    required this.taskId,
    required this.sessionId,
    required this.toolCallId,
    required this.prompt,
    this.aspectRatio,
    required this.model,
    this.status = TextGameImageTaskStatus.queued,
    this.mediaIds = const [],
    this.error,
  });
}

class TextGameImageService {
  final Ref _ref;

  /// 任务表变更通知（提交/开始/完成/失败都会触发）
  final _onChangedController = StreamController<void>.broadcast();
  Stream<void> get onChanged => _onChangedController.stream;

  final Map<String, TextGameImageTask> _tasks = {};
  Future<void> _chain = Future.value();
  int _seq = 0;

  TextGameImageService(this._ref);

  /// 只读任务表快照（游玩页渲染用）
  Map<String, TextGameImageTask> get tasks => Map.unmodifiable(_tasks);

  /// 按 toolCallId 查任务（一个 create_scene_image 工具调用对应一个任务）
  TextGameImageTask? taskByToolCallId(String toolCallId) {
    for (final t in _tasks.values) {
      if (t.toolCallId == toolCallId) return t;
    }
    return null;
  }

  /// create_scene_image 工具入口：校验 + 选模型（同步部分）→ 入队 → 立即返回。
  ///
  /// 返回值即工具结果 JSON：校验失败返回 error（LLM 当场知道并纠正）；
  /// 成功返回 submitted:true + taskId（不等待生成完成）。
  Future<String> submitForTool({
    required int? chatSessionId,
    required String? toolCallId,
    required Map<String, dynamic> args,
  }) async {
    final prompt = (args['prompt'] as String?)?.trim() ?? '';
    if (prompt.isEmpty) {
      return jsonEncode({
        'error': 'empty_prompt',
        'message': 'create_scene_image 的 prompt 不能为空',
      });
    }
    final aspectRatio = (args['aspect_ratio'] as String?)?.trim();
    if (aspectRatio != null &&
        aspectRatio.isNotEmpty &&
        !RegExp(r'^\s*\d{1,4}\s*:\s*\d{1,4}\s*$').hasMatch(aspectRatio)) {
      return jsonEncode({
        'error': 'invalid_aspect_ratio',
        'message': 'aspect_ratio 需为 "宽:高" 格式的比例（如 "1:1"、"3:4"、"16:9"）。',
      });
    }
    if (chatSessionId == null || toolCallId == null || toolCallId.isEmpty) {
      return jsonEncode({
        'error': 'missing_session',
        'message': '缺少会话或工具调用标识，无法登记生成任务',
      });
    }

    final repo = _ref.read(imageModelRepositoryProvider);
    final pick = await pickImageModel(repo);
    if (pick.errorJson != null) return jsonEncode(pick.errorJson);
    final model = pick.model!;

    final taskId = 'tgi_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    final task = TextGameImageTask(
      taskId: taskId,
      sessionId: chatSessionId,
      toolCallId: toolCallId,
      prompt: prompt,
      aspectRatio: aspectRatio,
      model: model,
    );
    _tasks[taskId] = task;
    _notify();

    LoggerService.instance.i(
      '场景图任务已提交: taskId=$taskId sessionId=${task.sessionId} '
      'toolCallId=${task.toolCallId} model=${model.name}',
      category: LogCategory.ai,
      tags: ['text_game', 'image', 'submit'],
    );

    // 串行链执行；catchError 兜底防单任务异常饿死后续任务
    _chain = _chain.then((_) => _runTask(task));
    _chain = _chain.catchError((Object e) {
      LoggerService.instance.w('场景图任务链异常: $e',
          category: LogCategory.ai, tags: ['text_game', 'image', 'chain']);
    });

    return jsonEncode({
      'success': true,
      'submitted': true,
      'taskId': taskId,
      'message': '场景图已提交后台生成（模型：${model.name}），完成后自动插入剧情。'
          '请继续输出后续剧情，不要等待，也不要向玩家提及生成进度。',
    });
  }

  /// 后台执行单个任务（串行链内调用）
  Future<void> _runTask(TextGameImageTask task) async {
    task.status = TextGameImageTaskStatus.running;
    _notify();
    try {
      final backend =
          _ref.read(imageGenerationBackendByTypeProvider(task.model.backendType));
      final result = await backend.submit(ImageGenerationRequest(
        model: task.model,
        prompt: task.prompt,
        // 负向提示词来自模型预设（与 create_images 行为一致），LLM 不传
        negativePrompt: task.model.negativePrompt.isEmpty
            ? null
            : task.model.negativePrompt,
        count: 1,
        aspectRatio: task.aspectRatio,
      ));
      task
        ..status = TextGameImageTaskStatus.completed
        ..mediaIds = result.mediaIds;
      // 先落库再广播：onChanged 的消费者（游玩页）重建时 DB 与任务态一致
      await _rewriteToolMessage(task, content: _completedContent(task));
      _notify();
      LoggerService.instance.i(
        '场景图生成完成: taskId=${task.taskId} mediaIds=${result.mediaIds.length}',
        category: LogCategory.ai,
        tags: ['text_game', 'image', 'completed'],
      );
    } on LocalEngineNotReadyException catch (e) {
      task
        ..status = TextGameImageTaskStatus.failed
        ..error = e.message;
      await _rewriteToolMessage(
        task,
        content: jsonEncode({'error': 'engine_not_ready', 'message': e.message}),
      );
      _notify();
    } catch (e, st) {
      task
        ..status = TextGameImageTaskStatus.failed
        ..error = e.toString();
      LoggerService.instance.e(
        '场景图生成失败: taskId=${task.taskId} - $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['text_game', 'image', 'failed'],
      );
      await _rewriteToolMessage(
        task,
        content: jsonEncode({
          'error': 'generation_failed',
          'message': '生图失败：$e',
        }),
      );
      _notify();
    }
  }

  String _completedContent(TextGameImageTask task) {
    return jsonEncode({
      'success': true,
      'submitted': true,
      'message': '场景图已生成。',
      // 与 create_images 结果同构：MediaGalleryCard 式解析可直接渲染
      'images': task.mediaIds
          .map((m) => {
                'mediaId': m,
                'prompt': task.prompt,
                'modelName': task.model.name,
              })
          .toList(),
      'count': task.mediaIds.length,
    });
  }

  /// 生成结束（成功/失败）后把剧情消息链里对应的 tool 消息改写为最终结果，
  /// hydrate 重放时图片/错误直接从消息内容恢复。
  ///
  /// 只改 DB；内存 _agentMessages 由游玩页控制器监听 onChanged 后经
  /// ScenarioSession.updateToolMessageContent 同步（用 [TextGameImageTask.finalContent]，
  /// 会话可能未驻内存）。
  /// 注意：完成事件若发生在某轮 compaction 重写之后、且当时会话未驻内存，
  /// 下一次内存基准的整链重写会把本改写覆盖回「已提交」态——图片文件仍在，
  /// 仅历史卡片退化为占位，v1 接受此边界。
  Future<void> _rewriteToolMessage(
    TextGameImageTask task, {
    required String content,
  }) async {
    task.finalContent = content;
    try {
      final sessionRepo = _ref.read(chatSessionRepositoryProvider);
      final record =
          await sessionRepo.findMessageByToolCallId(task.sessionId, task.toolCallId);
      final messageId = record?.id;
      if (messageId == null) {
        LoggerService.instance.w(
          '场景图任务找不到对应消息: sessionId=${task.sessionId} '
          'toolCallId=${task.toolCallId}（会话可能已删除）',
          category: LogCategory.ai,
          tags: ['text_game', 'image', 'rewrite', 'missing'],
        );
        return;
      }
      await sessionRepo.updateMessageContent(messageId, content);
    } catch (e, st) {
      LoggerService.instance.e(
        '场景图结果落库失败: taskId=${task.taskId} - $e',
        stackTrace: st.toString(),
        category: LogCategory.ai,
        tags: ['text_game', 'image', 'rewrite', 'failed'],
      );
    }
  }

  void _notify() => _onChangedController.add(null);

  void dispose() {
    _onChangedController.close();
    _tasks.clear();
  }
}

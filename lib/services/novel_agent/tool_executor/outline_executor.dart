/// 设定 / 大纲子执行器 — update_background_setting /
/// update_outline / write_outline / get_outline
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../../models/outline.dart';
import '../../logger_service.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../agent_scenario.dart';
import '../outline_replacer.dart';
import '../tool_executor_helpers.dart';

class OutlineExecutor with ToolExecutorHelpers {
  OutlineExecutor(this.ref);
  @override
  final Ref ref;

  /// 读取当前小说的背景设定（get_background_setting 工具）
  ///
  /// 与 [updateBackgroundSetting] 对称：先 [resolveCurrentNovelUrl] 校验小说
  /// 存在，再 getNovelById 取 backgroundSetting 字段。背景设定为空（未设置或仅
  /// 空白）时不视为错误，返回 empty=true 并引导用 update_background_setting 创建。
  Future<String> getBackgroundSetting(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final currentNovelId = ctx?.currentNovelId;
    if (currentNovelId == null) {
      return jsonEncode(guidanceError(
        'no_current_novel',
        '尚未选择当前小说。',
        suggestedTool: 'list_novels',
      ));
    }

    final repo = ref.read(novelRepositoryProvider);
    final novel = await repo.getNovelById(currentNovelId);
    // resolveCurrentNovelUrl 已保证小说存在；此处兜底防 DB 在两次查询间被删。
    if (novel == null) {
      return jsonEncode(guidanceError(
        'novel_not_found',
        '当前小说不存在。',
        suggestedTool: 'list_novels',
      ));
    }

    final setting = novel.backgroundSetting;
    final isEmpty = setting == null || setting.trim().isEmpty;
    final novelContext = buildCurrentNovelContext(ctx);
    LoggerService.instance.i(
      '获取背景设定: novelId=$currentNovelId, empty=$isEmpty',
      category: LogCategory.ai,
      tags: ['agent', 'tool', 'get_background_setting'],
    );
    if (isEmpty) {
      return jsonEncode({
        'novel': novelContext,
        'setting': null,
        'empty': true,
        'message': '当前小说暂无背景设定。如需建立世界观设定，请用 update_background_setting。',
        'suggested_tool': 'update_background_setting',
      });
    }
    return jsonEncode({
      'novel': novelContext,
      'setting': setting,
      'empty': false,
    });
  }

  Future<String> updateBackgroundSetting(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (setting, settingErr) = parser.requireString('setting');
    if (settingErr != null) return settingErr;

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    // resolveCurrentNovelUrl 成功即保证 ctx.currentNovelId != null，
    // 此处用 ?. + if 消除 ctx!.currentNovelId! 双重强解包。
    final currentNovelId = ctx?.currentNovelId;
    if (currentNovelId == null) {
      return jsonEncode(guidanceError(
        'no_current_novel',
        '尚未选择当前小说。',
        suggestedTool: 'list_novels',
      ));
    }

    final repo = ref.read(novelRepositoryProvider);
    final affected = await repo.updateBackgroundSettingById(currentNovelId, setting);
    if (affected == 0) {
      return jsonEncode(guidanceError(
        'novel_not_found',
        '当前小说不存在。',
        suggestedTool: 'list_novels',
        suggestedArgs: const <String, dynamic>{},
      ));
    }

    LoggerService.instance.i('更新背景设定: novelId=$currentNovelId',
        category: LogCategory.ai, tags: ['agent', 'tool', 'update_background_setting']);
    return jsonEncode({'success': true, 'message': '背景设定已更新'});
  }

  Future<String> updateOutline(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (oldString, oldErr) = parser.requireString('oldString');
    if (oldErr != null) return oldErr;
    final (newString, newErr) = parser.requireString('newString');
    if (newErr != null) return newErr;
    final (replaceAll, allErr) = parser.optionalBool('replaceAll');
    if (allErr != null) return allErr;

    if (oldString == newString) {
      return jsonEncode({
        'error': 'invalid_param',
        'message': 'oldString 与 newString 不能相同',
      });
    }

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(outlineRepositoryProvider);
    final outline = await repo.getOutlineByNovelUrl(novelUrl);
    if (outline == null) {
      LoggerService.instance.w('大纲不存在，引导用 write_outline 创建',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'update_outline', 'not_found']);
      return jsonEncode(guidanceError(
        'not_found',
        '暂无大纲，请用 write_outline 创建。',
        suggestedTool: 'write_outline',
      ));
    }

    try {
      final newContent = replaceOutlineSnippet(
        content: outline.content,
        oldString: oldString,
        newString: newString,
        replaceAll: replaceAll ?? false,
      );
      // edit 场景大纲必然已存在，用 updateOutlineContent 仅更新 content+updated_at，
      // 不动 created_at，语义比 saveOutline 的 upsert 更准。
      await repo.updateOutlineContent(novelUrl, outline.title, newContent);
    } on OutlineEditException catch (e) {
      final errorCode =
          e.reason == 'ambiguous' ? 'ambiguous_match' : 'not_found';
      LoggerService.instance.d(
        '更新大纲失败: $errorCode, novelUrl=$novelUrl',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'update_outline', errorCode],
      );
      return jsonEncode({'error': errorCode, 'message': e.message});
    }

    LoggerService.instance.i('更新大纲: novelUrl=$novelUrl',
        category: LogCategory.ai, tags: ['agent', 'tool', 'update_outline']);
    return jsonEncode({'success': true, 'message': '大纲已更新'});
  }

  Future<String> writeOutline(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (content, contentErr) = parser.requireString('content');
    if (contentErr != null) return contentErr;

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    // 大纲不再要求标题：用当前小说书名兜底（与大纲编辑页未填标题时的行为一致），
    // 书名缺失时回退为空串（outlines.title 为 NOT NULL，空串合法）。
    final title = (ctx?.currentNovelTitle ?? '').trim();

    final repo = ref.read(outlineRepositoryProvider);
    final outline = Outline(
      novelUrl: novelUrl,
      title: title,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await repo.saveOutline(outline);
    LoggerService.instance.i('写入大纲: novelUrl=$novelUrl',
        category: LogCategory.ai, tags: ['agent', 'tool', 'write_outline']);
    return jsonEncode({'success': true, 'message': '大纲已保存'});
  }

  Future<String> getOutline(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(outlineRepositoryProvider);
    final outline = await repo.getOutlineByNovelUrl(novelUrl);
    if (outline == null) {
      LoggerService.instance.w('大纲不存在',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'get_outline', 'not_found']);
      return jsonEncode({'error': 'not_found', 'message': '暂无大纲'});
    }

    // 读成功后供 LLM 拿到当前大纲内容（用于后续 update_outline 的 oldString 参考）
    final novelContext = buildCurrentNovelContext(ctx);
    LoggerService.instance.i('获取大纲成功',
        category: LogCategory.ai, tags: ['agent', 'tool', 'get_outline']);
    return jsonEncode({
      'novel': novelContext,
      'title': outline.title,
      'content': outline.content,
      'updatedAt': outline.updatedAt.toIso8601String(),
    });
  }
}

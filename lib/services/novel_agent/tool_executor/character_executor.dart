/// 角色子执行器 — list_characters / update_character / create_character / delete_character
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../../models/character.dart';
import '../../logger_service.dart';
import '../tool_arg_parser.dart' show ToolArgParser;
import '../agent_scenario.dart';
import '../tool_executor_helpers.dart';

class CharacterExecutor with ToolExecutorHelpers {
  CharacterExecutor(this.ref);
  @override
  final Ref ref;

  Future<String> listCharacters(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(characterRepositoryProvider);
    final characters = await repo.getCharacters(novelUrl);
    final list = characters.map((c) => {
          'name': c.name,
          'gender': c.gender,
          'age': c.age,
          'occupation': c.occupation,
          'personality': c.personality,
          'appearanceFeatures': c.appearanceFeatures,
          'bodyType': c.bodyType,
          'clothingStyle': c.clothingStyle,
          'backgroundStory': c.backgroundStory,
          'aliases': c.aliases,
          'avatarMediaId': c.avatarMediaId,
        }).toList();

    final novelContext = buildCurrentNovelContext(ctx);
    LoggerService.instance.i('列出角色: ${list.length} 个',
        category: LogCategory.ai, tags: ['agent', 'tool', 'list_characters']);
    return jsonEncode({
      'novel': novelContext,
      'characters': list,
      'count': list.length,
    });
  }

  Future<String> updateCharacter(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (name, nameErr) = parser.requireString('name');
    if (nameErr != null) return nameErr;

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(characterRepositoryProvider);
    final existing = await repo.findCharacterByName(novelUrl, name);
    if (existing == null) {
      LoggerService.instance.d(
        '工具引导错误: character_not_found name=$name',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'update_character', 'character_not_found'],
      );
      return jsonEncode(guidanceError(
        'character_not_found',
        '角色 "$name" 不存在。使用 create_character 创建新角色。',
        suggestedTool: 'list_characters',
        suggestedArgs: const <String, dynamic>{},
      ));
    }

    final (gender, genderErr) = parser.nullableString('gender');
    if (genderErr != null) return genderErr;
    final (age, ageErr) = parser.optionalInt('age');
    if (ageErr != null) return ageErr;
    final (occupation, occupationErr) = parser.nullableString('occupation');
    if (occupationErr != null) return occupationErr;
    final (personality, personalityErr) =
        parser.nullableString('personality');
    if (personalityErr != null) return personalityErr;
    final (appearanceFeatures, appearanceErr) =
        parser.nullableString('appearanceFeatures');
    if (appearanceErr != null) return appearanceErr;
    // description 作为外貌特征的兜底（兼容旧用法，与 createCharacter 对齐）
    final (description, _) = parser.nullableString('description');
    final resolvedAppearance =
        appearanceFeatures ?? description ?? existing.appearanceFeatures;
    final (bodyType, bodyErr) = parser.nullableString('bodyType');
    if (bodyErr != null) return bodyErr;
    final (clothingStyle, clothingErr) =
        parser.nullableString('clothingStyle');
    if (clothingErr != null) return clothingErr;
    final (backgroundStory, bgErr) =
        parser.nullableString('backgroundStory');
    if (bgErr != null) return bgErr;
    final (aliases, aliasesErr) = parser.optionalStringList('aliases');
    if (aliasesErr != null) return aliasesErr;
    final (avatarMediaId, avatarErr) = parser.nullableString('avatarMediaId');
    if (avatarErr != null) return avatarErr;

    final updated = existing.copyWith(
      gender: gender ?? existing.gender,
      age: age ?? existing.age,
      occupation: occupation ?? existing.occupation,
      personality: personality ?? existing.personality,
      appearanceFeatures: resolvedAppearance,
      bodyType: bodyType ?? existing.bodyType,
      clothingStyle: clothingStyle ?? existing.clothingStyle,
      backgroundStory: backgroundStory ?? existing.backgroundStory,
      aliases: aliases ?? existing.aliases,
      avatarMediaId: avatarMediaId ?? existing.avatarMediaId,
    );
    await repo.updateCharacter(updated);

    LoggerService.instance.i('更新角色: "$name"',
        category: LogCategory.ai, tags: ['agent', 'tool', 'update_character']);
    return jsonEncode({'success': true, 'message': '角色 "$name" 已更新'});
  }

  Future<String> createCharacter(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (name, nameErr) = parser.requireString('name');
    if (nameErr != null) return nameErr;

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(characterRepositoryProvider);

    // 检查是否已存在
    final existing = await repo.findCharacterByName(novelUrl, name);
    if (existing != null) {
      LoggerService.instance.w('角色已存在: "$name"',
          category: LogCategory.ai,
          tags: ['agent', 'tool', 'create_character', 'duplicate']);
      return jsonEncode({
        'error': 'duplicate',
        'message': '角色 "$name" 已存在。使用 update_character 更新。',
      });
    }

    final (gender, genderErr) = parser.nullableString('gender');
    if (genderErr != null) return genderErr;
    final (age, ageErr) = parser.optionalInt('age');
    if (ageErr != null) return ageErr;
    final (occupation, occupationErr) = parser.nullableString('occupation');
    if (occupationErr != null) return occupationErr;
    final (personality, personalityErr) =
        parser.nullableString('personality');
    if (personalityErr != null) return personalityErr;
    final (appearanceFeatures, appearanceErr) =
        parser.nullableString('appearanceFeatures');
    if (appearanceErr != null) return appearanceErr;
    final (bodyType, bodyErr) = parser.nullableString('bodyType');
    if (bodyErr != null) return bodyErr;
    final (clothingStyle, clothingErr) =
        parser.nullableString('clothingStyle');
    if (clothingErr != null) return clothingErr;
    final (backgroundStory, bgErr) =
        parser.nullableString('backgroundStory');
    if (bgErr != null) return bgErr;
    final (aliases, aliasesErr) = parser.optionalStringList('aliases');
    if (aliasesErr != null) return aliasesErr;
    // description 作为外貌特征的兜底（兼容旧用法）
    final (description, _) = parser.nullableString('description');

    // 结构化字段未传 appearanceFeatures 时，回退到 description
    final resolvedAppearance =
        appearanceFeatures ?? description ?? '';

    final character = Character(
      novelUrl: novelUrl,
      name: name,
      gender: gender,
      age: age,
      occupation: occupation,
      personality: personality,
      appearanceFeatures: resolvedAppearance,
      bodyType: bodyType,
      clothingStyle: clothingStyle,
      backgroundStory: backgroundStory,
      aliases: aliases,
    );
    final id = await repo.createCharacter(character);

    LoggerService.instance.i('创建角色: "$name" (id=$id)',
        category: LogCategory.ai, tags: ['agent', 'tool', 'create_character']);
    return jsonEncode({
      'success': true,
      'message': '角色 "$name" 已创建',
      'characterId': id,
    });
  }

  /// 删除指定名字的角色
  ///
  /// 复用 findCharacterByName 取 ID（避免暴露真实 ID 给 LLM），存在则 deleteCharacter 删除。
  /// 注意：仅删除 characters 表中的角色卡；该角色出现在章节正文里的字样不会被自动修改，
  /// 如需改正文请用 update_chapter_content / rewrite_chapter。
  Future<String> deleteCharacter(
    Map<String, dynamic> args,
    AgentScenarioContext? ctx,
  ) async {
    final parser = ToolArgParser(args);
    final (name, nameErr) = parser.requireString('name');
    if (nameErr != null) return nameErr;

    final novelResolve = await resolveCurrentNovelUrl(ctx);
    if (novelResolve.errorJson != null) {
      return jsonEncode(novelResolve.errorJson);
    }
    final novelUrl = novelResolve.url!;

    final repo = ref.read(characterRepositoryProvider);
    final existing = await repo.findCharacterByName(novelUrl, name);
    if (existing == null) {
      LoggerService.instance.d(
        '工具引导错误: character_not_found name=$name',
        category: LogCategory.ai,
        tags: ['agent', 'tool', 'delete_character', 'character_not_found'],
      );
      return jsonEncode(guidanceError(
        'character_not_found',
        '角色 "$name" 不存在。使用 list_characters 查看所有角色。',
        suggestedTool: 'list_characters',
        suggestedArgs: const <String, dynamic>{},
      ));
    }

    await repo.deleteCharacter(existing.id!);

    LoggerService.instance.i('删除角色: "$name" (id=${existing.id})',
        category: LogCategory.ai, tags: ['agent', 'tool', 'delete_character']);
    return jsonEncode({
      'success': true,
      'message': '角色 "$name" 已删除',
      'deletedName': name,
    });
  }
}

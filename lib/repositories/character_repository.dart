import 'package:sqflite/sqflite.dart';
import '../models/character.dart';
import 'base_repository.dart';
import '../services/logger_service.dart';
import '../core/interfaces/repositories/i_character_repository.dart';

/// 角色仓库类
///
/// 负责角色的数据访问操作，包括：
/// - 角色的CRUD操作
/// - 角色搜索和查询
/// - 角色图片管理
/// - 批量更新操作（用于AI伴读）
///
/// 注意：关系管理方法已移至 CharacterRelationRepository
class CharacterRepository extends BaseRepository
    implements ICharacterRepository {
  /// 构造函数 - 接受数据库连接实例
  CharacterRepository({required super.dbConnection});

  // ========== 角色CRUD操作 ==========

  /// 创建角色
  ///
  /// [character] 要创建的角色对象
  /// 返回新插入记录的ID
  @override
  Future<int> createCharacter(Character character) async {
    try {
      final db = await database;
      final id = await db.insert(
        'characters',
        character.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      LoggerService.instance.i(
        '创建角色: ${character.name} (id=$id)',
        category: LogCategory.character,
        tags: ['character', 'create', 'success'],
      );
      return id;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '创建角色失败: ${character.name} - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['character', 'create', 'failed'],
      );
      rethrow;
    }
  }

  /// 获取小说的所有角色
  ///
  /// [novelUrl] 小说URL
  /// 返回按创建时间升序排列的角色列表
  @override
  Future<List<Character>> getCharacters(String novelUrl) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'characters',
      where: 'novelUrl = ?',
      whereArgs: [novelUrl],
      orderBy: 'createdAt ASC',
    );

    return List.generate(maps.length, (i) {
      return Character.fromMap(maps[i]);
    });
  }

  /// 根据ID获取角色
  ///
  /// [id] 角色ID
  /// 返回角色对象，如果不存在则返回null
  @override
  Future<Character?> getCharacter(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'characters',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Character.fromMap(maps.first);
    }
    return null;
  }

  /// 更新角色
  ///
  /// [character] 要更新的角色对象（必须包含id）
  /// 返回受影响的行数
  @override
  Future<int> updateCharacter(Character character) async {
    try {
      final db = await database;
      final updatedCharacter = character.copyWith(
        updatedAt: DateTime.now(),
      );

      final affected = await db.update(
        'characters',
        updatedCharacter.toMap(),
        where: 'id = ?',
        whereArgs: [character.id],
      );
      LoggerService.instance.i(
        '更新角色: ${character.name} (id=${character.id}, affected=$affected)',
        category: LogCategory.character,
        tags: ['character', 'update', 'success'],
      );
      return affected;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新角色失败: ${character.name} (id=${character.id}) - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['character', 'update', 'failed'],
      );
      rethrow;
    }
  }

  /// 删除角色
  ///
  /// [id] 角色ID
  /// 返回受影响的行数
  @override
  Future<int> deleteCharacter(int id) async {
    try {
      final db = await database;
      final affected = await db.delete(
        'characters',
        where: 'id = ?',
        whereArgs: [id],
      );
      LoggerService.instance.i(
        '删除角色: id=$id (affected=$affected)',
        category: LogCategory.character,
        tags: ['character', 'delete', 'success'],
      );
      return affected;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除角色失败: id=$id - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['character', 'delete', 'failed'],
      );
      rethrow;
    }
  }

  /// 根据名称查找角色
  ///
  /// [novelUrl] 小说URL
  /// [name] 角色名称
  /// 返回角色对象，如果不存在则返回null
  @override
  Future<Character?> findCharacterByName(String novelUrl, String name) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'characters',
      where: 'novelUrl = ? AND name = ?',
      whereArgs: [novelUrl, name],
    );

    if (maps.isNotEmpty) {
      return Character.fromMap(maps.first);
    }
    return null;
  }

  /// 更新或插入角色（去重逻辑）
  ///
  /// 如果角色已存在（按novelUrl和name匹配），则更新现有角色
  /// 如果角色不存在，则创建新角色
  ///
  /// [newCharacter] 要更新或插入的角色
  /// 返回操作后的角色对象
  @override
  Future<Character> updateOrInsertCharacter(Character newCharacter) async {
    try {
      final db = await database;

      // 查找是否已存在同名角色
      final existingCharacter = await findCharacterByName(
        newCharacter.novelUrl,
        newCharacter.name,
      );

      if (existingCharacter != null) {
        // 更新现有角色，保留原有ID和创建时间
        final updatedCharacter = existingCharacter.copyWith(
          age: newCharacter.age,
          gender: newCharacter.gender,
          occupation: newCharacter.occupation,
          personality: newCharacter.personality,
          bodyType: newCharacter.bodyType,
          clothingStyle: newCharacter.clothingStyle,
          appearanceFeatures: newCharacter.appearanceFeatures,
          backgroundStory: newCharacter.backgroundStory,
          updatedAt: DateTime.now(),
        );

        await db.update(
          'characters',
          updatedCharacter.toMap(),
          where: 'id = ?',
          whereArgs: [existingCharacter.id],
        );

        LoggerService.instance.i(
          '更新角色: ${newCharacter.name} (ID: ${existingCharacter.id})',
          category: LogCategory.character,
          tags: ['update', 'success'],
        );
        return updatedCharacter;
      } else {
        // 创建新角色
        final id = await db.insert(
          'characters',
          newCharacter.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        LoggerService.instance.i(
          '创建新角色: ${newCharacter.name} (ID: $id)',
          category: LogCategory.character,
          tags: ['create', 'success'],
        );
        return newCharacter.copyWith(id: id);
      }
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '更新或插入角色失败: ${newCharacter.name} - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['character', 'update_or_insert', 'failed'],
      );
      rethrow;
    }
  }

  /// 批量更新角色
  ///
  /// 接受新角色列表，对每个角色执行去重更新逻辑
  ///
  /// [newCharacters] 要更新的角色列表
  /// 返回成功更新的角色列表
  @override
  Future<List<Character>> batchUpdateCharacters(
      List<Character> newCharacters) async {
    final updatedCharacters = <Character>[];

    for (final character in newCharacters) {
      try {
        final updatedCharacter = await updateOrInsertCharacter(character);
        updatedCharacters.add(updatedCharacter);
      } catch (e, stackTrace) {
        LoggerService.instance.e(
          '批量更新角色失败: ${character.name} - $e',
          stackTrace: stackTrace.toString(),
          category: LogCategory.character,
          tags: ['batch', 'error'],
        );
        // 继续处理其他角色，不中断整个批量操作
        continue;
      }
    }

    LoggerService.instance.i(
      '批量更新完成，成功更新 ${updatedCharacters.length}/${newCharacters.length} 个角色',
      category: LogCategory.character,
      tags: ['batch', 'update'],
    );
    return updatedCharacters;
  }

  /// 获取小说的所有角色名称
  ///
  /// [novelUrl] 小说URL
  /// 返回按名称字母顺序排列的角色名称列表
  @override
  Future<List<String>> getCharacterNames(String novelUrl) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'characters',
      columns: ['name'],
      where: 'novelUrl = ?',
      whereArgs: [novelUrl],
      orderBy: 'name ASC',
    );

    return maps.map((map) => map['name'] as String).toList();
  }

  /// 检查角色是否存在
  ///
  /// [id] 角色ID
  /// 返回角色是否存在
  @override
  Future<bool> characterExists(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'characters',
      where: 'id = ?',
      whereArgs: [id],
    );

    return maps.isNotEmpty;
  }

  /// 根据ID列表获取多个角色
  ///
  /// [ids] 角色ID列表
  /// 返回按创建时间升序排列的角色列表，如果ID列表为空则返回空列表
  @override
  Future<List<Character>> getCharactersByIds(List<int> ids) async {
    if (ids.isEmpty) return [];

    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final List<Map<String, dynamic>> maps = await db.query(
      'characters',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'createdAt ASC',
    );

    return List.generate(maps.length, (i) {
      return Character.fromMap(maps[i]);
    });
  }

  /// 删除小说的所有角色
  ///
  /// [novelUrl] 小说URL
  /// 返回受影响的行数
  @override
  Future<int> deleteAllCharacters(String novelUrl) async {
    try {
      final db = await database;
      final affected = await db.delete(
        'characters',
        where: 'novelUrl = ?',
        whereArgs: [novelUrl],
      );
      LoggerService.instance.i(
        '删除小说所有角色: novelUrl=$novelUrl (affected=$affected)',
        category: LogCategory.character,
        tags: ['character', 'delete_all', 'success'],
      );
      return affected;
    } catch (e, stackTrace) {
      LoggerService.instance.e(
        '删除小说所有角色失败: novelUrl=$novelUrl - $e',
        stackTrace: stackTrace.toString(),
        category: LogCategory.character,
        tags: ['character', 'delete_all', 'failed'],
      );
      rethrow;
    }
  }

  // ========== 角色图片管理 ==========

  /// 更新角色的缓存图片URL
  ///
  /// [characterId] 角色ID
  /// [imageUrl] 缓存图片URL
  /// 返回受影响的行数
  @override
  Future<int> updateCharacterCachedImage(
      int characterId, String? imageUrl) async {
    final db = await database;
    final affected = await db.update(
      'characters',
      {
        'cachedImageUrl': imageUrl,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [characterId],
    );
    LoggerService.instance.d(
      '更新角色缓存图: id=$characterId (affected=$affected)',
      category: LogCategory.cache,
      tags: ['character', 'image', 'update'],
    );
    return affected;
  }

  /// 清除角色的缓存图片URL
  ///
  /// [characterId] 角色ID
  /// 返回受影响的行数
  @override
  Future<int> clearCharacterCachedImage(int characterId) async {
    final db = await database;
    final affected = await db.update(
      'characters',
      {
        'cachedImageUrl': null,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [characterId],
    );
    LoggerService.instance.d(
      '清除角色缓存图: id=$characterId (affected=$affected)',
      category: LogCategory.cache,
      tags: ['character', 'image', 'clear'],
    );
    return affected;
  }

  /// 批量清除角色的缓存图片URL
  ///
  /// [novelUrl] 小说URL
  /// 返回受影响的行数
  @override
  Future<int> clearAllCharacterCachedImages(String novelUrl) async {
    final db = await database;
    final affected = await db.update(
      'characters',
      {
        'cachedImageUrl': null,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'novelUrl = ?',
      whereArgs: [novelUrl],
    );
    LoggerService.instance.d(
      '清除全部角色缓存图: novelUrl=$novelUrl (affected=$affected)',
      category: LogCategory.cache,
      tags: ['character', 'image', 'clear_all'],
    );
    return affected;
  }

  /// 获取角色的缓存图片URL
  ///
  /// [characterId] 角色ID
  /// 返回头像缓存路径，如果没有设置则返回null
  @override
  Future<String?> getCharacterCachedImage(int characterId) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'characters',
      columns: ['cachedImageUrl'],
      where: 'id = ?',
      whereArgs: [characterId],
      limit: 1,
    );

    if (maps.isNotEmpty && maps.first['cachedImageUrl'] != null) {
      return maps.first['cachedImageUrl'] as String?;
    }

    return null;
  }

  /// 更新角色头像信息（扩展方法，支持更多元数据）
  ///
  /// [characterId] 角色ID
  /// [imageUrl] 头像URL/路径
  /// [originalFilename] 原始图集文件名（未使用）
  /// [originalImageUrl] 原始图片URL（未使用）
  /// 返回受影响的行数
  @override
  Future<int> updateCharacterAvatar(
    int characterId, {
    String? imageUrl,
    String? originalFilename,
    String? originalImageUrl,
  }) async {
    final db = await database;

    final Map<String, dynamic> updateData = {
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    if (imageUrl != null) {
      updateData['cachedImageUrl'] = imageUrl;
    } else {
      updateData['cachedImageUrl'] = null;
    }

    final affected = await db.update(
      'characters',
      updateData,
      where: 'id = ?',
      whereArgs: [characterId],
    );
    LoggerService.instance.i(
      '更新角色头像: id=$characterId (affected=$affected)',
      category: LogCategory.character,
      tags: ['character', 'avatar', 'update'],
    );
    return affected;
  }

  /// 检查角色是否有头像缓存
  ///
  /// [characterId] 角色ID
  /// 返回是否有头像缓存
  @override
  Future<bool> hasCharacterAvatar(int characterId) async {
    final cachedUrl = await getCharacterCachedImage(characterId);
    return cachedUrl != null && cachedUrl.isNotEmpty;
  }

  /// 更新角色头像的媒体资源ID（图像/视频）
  ///
  /// [characterId] 角色ID
  /// [mediaId] 媒体资源ID，传 null 清空头像
  /// 返回受影响的行数
  @override
  Future<int> updateCharacterAvatarMediaId(
      int characterId, String? mediaId) async {
    final db = await database;
    final affected = await db.update(
      'characters',
      {
        'avatarMediaId': mediaId,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [characterId],
    );
    LoggerService.instance.d(
      '更新角色头像媒体: id=$characterId mediaId=$mediaId (affected=$affected)',
      category: LogCategory.character,
      tags: ['character', 'avatar', 'update'],
    );
    return affected;
  }
}

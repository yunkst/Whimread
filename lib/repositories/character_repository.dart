import 'package:sqflite/sqflite.dart';
import '../models/character.dart';
import '../models/character_gallery_image.dart';
import 'base_repository.dart';
import '../services/logger_service.dart';
import '../core/interfaces/repositories/i_character_repository.dart';

/// 角色仓库类
///
/// 负责角色的数据访问操作，包括：
/// - 角色的CRUD操作
/// - 角色搜索和查询
/// - 角色图片管理
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
      // 先清图集关联行，再删角色主行（图集表无外键，靠 repository 联动）
      await db.delete(
        'character_images',
        where: 'characterId = ?',
        whereArgs: [id],
      );
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

  /// 删除小说的所有角色
  ///
  /// [novelUrl] 小说URL
  /// 返回受影响的行数
  @override
  Future<int> deleteAllCharacters(String novelUrl) async {
    try {
      final db = await database;
      // 先按子查询清掉该小说全部角色的图集关联行（须在删角色前执行）
      await db.execute(
        'DELETE FROM character_images WHERE characterId IN '
        '(SELECT id FROM characters WHERE novelUrl = ?)',
        [novelUrl],
      );
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

  // ========== 角色图集（character_images，v50） ==========

  /// 追加一张图集图片（sort 取当前最大值 +1，新图排在末尾）
  ///
  /// [characterId] 角色ID
  /// [mediaId] 媒体资源ID（须已通过 MediaProxy 登记存在）
  /// 返回新增条目（含 id / sort）
  @override
  Future<CharacterGalleryImage> addCharacterImage(
      int characterId, String mediaId) async {
    final db = await database;
    final maxRow = await db.rawQuery(
        'SELECT MAX(sort) as maxSort FROM character_images '
        'WHERE characterId = ?',
        [characterId]);
    final nextSort = (maxRow.first['maxSort'] as int? ?? -1) + 1;
    final entry = CharacterGalleryImage(
      characterId: characterId,
      mediaId: mediaId,
      sort: nextSort,
      createdAt: DateTime.now(),
    );
    final id = await db.insert('character_images', entry.toMap());
    LoggerService.instance.d(
      '角色图集追加: characterId=$characterId mediaId=$mediaId sort=$nextSort',
      category: LogCategory.character,
      tags: ['character', 'gallery', 'add'],
    );
    return entry.copyWith(id: id);
  }

  /// 查询角色图集（按 sort, id 升序）
  ///
  /// [characterId] 角色ID
  @override
  Future<List<CharacterGalleryImage>> getCharacterImages(
      int characterId) async {
    final db = await database;
    final maps = await db.query(
      'character_images',
      where: 'characterId = ?',
      whereArgs: [characterId],
      orderBy: 'sort ASC, id ASC',
    );
    return maps.map(CharacterGalleryImage.fromMap).toList();
  }

  /// 从图集移除一条（仅删关联行，不删 media_items 里的媒体文件——
  /// 同一 mediaId 可能仍被头像/聊天消息引用）
  ///
  /// [imageId] character_images 行主键
  /// 返回受影响的行数
  @override
  Future<int> removeCharacterImage(int imageId) async {
    final db = await database;
    final affected = await db.delete(
      'character_images',
      where: 'id = ?',
      whereArgs: [imageId],
    );
    LoggerService.instance.d(
      '角色图集移除: imageId=$imageId (affected=$affected)',
      category: LogCategory.character,
      tags: ['character', 'gallery', 'remove'],
    );
    return affected;
  }
}

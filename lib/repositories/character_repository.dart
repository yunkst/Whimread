import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../models/character.dart';
import '../models/character_gallery_image.dart';
import '../models/character_revision.dart';
import 'base_repository.dart';
import '../services/logger_service.dart';
import '../core/interfaces/repositories/i_character_repository.dart';

/// 角色仓库类
///
/// 负责角色的数据访问操作，包括：
/// - 角色的CRUD操作
/// - 角色搜索和查询
/// - 角色图片管理
/// - 角色卡版本记录（v53）：create/update/头像变更成功后自动追加快照版本，
///   回滚 = 写回历史快照并追加 rollback 版本（append-only）
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
  /// [source]/[sourceRef]/[reason] 版本记录三元组（首次创建即 baseline 版本）
  /// 返回新插入记录的ID
  @override
  Future<int> createCharacter(
    Character character, {
    String source = CharacterRevisionSource.manual,
    String? sourceRef,
    String? reason,
  }) {
    return guard(
      'character.createCharacter',
      () async {
        final db = await database;
        final id = await db.insert(
          'characters',
          character.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _insertRevision(
          character.copyWith(id: id),
          source: source,
          sourceRef: sourceRef,
          reason: reason ?? '创建角色',
        );
        LoggerService.instance.i(
          '创建角色: ${character.name} (id=$id)',
          category: LogCategory.character,
          tags: ['character', 'create', 'success'],
        );
        return id;
      },
      message: (e) => '创建角色失败: ${character.name} - $e',
      category: LogCategory.character,
      tags: ['character', 'create', 'failed'],
    );
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
  /// [source]/[sourceRef]/[reason] 版本记录三元组（成功后追加改后快照版本）
  /// 返回受影响的行数
  @override
  Future<int> updateCharacter(
    Character character, {
    String source = CharacterRevisionSource.manual,
    String? sourceRef,
    String? reason,
  }) {
    return guard(
      'character.updateCharacter',
      () async {
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
        if (affected > 0) {
          await _insertRevision(
            updatedCharacter,
            source: source,
            sourceRef: sourceRef,
            reason: reason,
          );
        }
        LoggerService.instance.i(
          '更新角色: ${character.name} (id=${character.id}, affected=$affected)',
          category: LogCategory.character,
          tags: ['character', 'update', 'success'],
        );
        return affected;
      },
      message: (e) =>
          '更新角色失败: ${character.name} (id=${character.id}) - $e',
      category: LogCategory.character,
      tags: ['character', 'update', 'failed'],
    );
  }

  /// 删除角色
  ///
  /// [id] 角色ID
  /// 返回受影响的行数
  @override
  Future<int> deleteCharacter(int id) {
    return guard(
      'character.deleteCharacter',
      () async {
        final db = await database;
        // 先清图集关联行与版本记录，再删角色主行（两表均无外键，靠 repository 联动）
        await db.delete(
          'character_images',
          where: 'characterId = ?',
          whereArgs: [id],
        );
        await db.delete(
          'character_revisions',
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
      },
      message: (e) => '删除角色失败: id=$id - $e',
      category: LogCategory.character,
      tags: ['character', 'delete', 'failed'],
    );
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
  Future<int> deleteAllCharacters(String novelUrl) {
    return guard(
      'character.deleteAllCharacters',
      () async {
        final db = await database;
        // 先按子查询清掉该小说全部角色的图集关联行与版本记录（须在删角色前执行）
        await db.execute(
          'DELETE FROM character_images WHERE characterId IN '
          '(SELECT id FROM characters WHERE novelUrl = ?)',
          [novelUrl],
        );
        await db.execute(
          'DELETE FROM character_revisions WHERE characterId IN '
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
      },
      message: (e) => '删除小说所有角色失败: novelUrl=$novelUrl - $e',
      category: LogCategory.character,
      tags: ['character', 'delete_all', 'failed'],
    );
  }

  // ========== 角色图片管理 ==========

  /// 更新角色头像的媒体资源ID（图像/视频）
  ///
  /// [characterId] 角色ID
  /// [mediaId] 媒体资源ID，传 null 清空头像
  /// [sourceRef] 版本来源定位（如「角色详情页」）
  /// 返回受影响的行数
  @override
  Future<int> updateCharacterAvatarMediaId(
      int characterId, String? mediaId,
      {String? sourceRef}) async {
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
    if (affected > 0) {
      final card = await getCharacter(characterId);
      if (card != null) {
        await _insertRevision(
          card,
          source: CharacterRevisionSource.manual,
          sourceRef: sourceRef,
          reason: mediaId == null ? '清除头像' : '更新头像',
        );
      }
    }
    LoggerService.instance.d(
      '更新角色头像媒体: id=$characterId mediaId=$mediaId (affected=$affected)',
      category: LogCategory.character,
      tags: ['character', 'avatar', 'update'],
    );
    return affected;
  }

  // ========== 角色卡版本记录（character_revisions，v53） ==========

  /// 追加一条版本快照（改后整卡）。内部方法：由 create/update/头像变更调用。
  Future<void> _insertRevision(
    Character card, {
    required String source,
    String? sourceRef,
    String? reason,
  }) async {
    final db = await database;
    await db.insert(
      'character_revisions',
      CharacterRevision(
        characterId: card.id!,
        snapshotJson: jsonEncode(card.toMap()),
        source: source,
        sourceRef: sourceRef,
        reason: reason,
        createdAt: DateTime.now(),
      ).toMap(),
    );
  }

  /// 查询角色卡版本历史（新→旧）
  ///
  /// [characterId] 角色ID
  /// [limit] 限制条数（缺省全量；版本列表页可先取最近 50 条）
  @override
  Future<List<CharacterRevision>> getRevisions(int characterId,
      {int? limit}) async {
    final db = await database;
    final maps = await db.query(
      'character_revisions',
      where: 'characterId = ?',
      whereArgs: [characterId],
      orderBy: 'createdAt DESC, id DESC',
      limit: limit,
    );
    return maps.map(CharacterRevision.fromMap).toList();
  }

  /// 按 id 取单条版本
  @override
  Future<CharacterRevision?> getRevision(int revisionId) async {
    final db = await database;
    final maps = await db.query(
      'character_revisions',
      where: 'id = ?',
      whereArgs: [revisionId],
    );
    if (maps.isEmpty) return null;
    return CharacterRevision.fromMap(maps.first);
  }

  /// 回滚到指定版本：把该版本的快照写回角色卡，并追加一条 rollback 版本
  /// （历史 append-only，回滚动作本身可追溯）。
  ///
  /// 返回是否成功（版本不存在/快照损坏/角色已删除均为 false）。
  @override
  Future<bool> rollbackToRevision(int revisionId, {String? sourceRef}) async {
    final revision = await getRevision(revisionId);
    if (revision == null) return false;
    final snapshot = revision.parseSnapshot();
    if (snapshot == null || snapshot.id == null) return false;
    // 角色可能已被删除：update 影响 0 行时 updateCharacter 不会记版本，
    // 这里先确认存在，避免"假回滚成功"。
    final existing = await getCharacter(snapshot.id!);
    if (existing == null) return false;

    final affected = await updateCharacter(
      snapshot,
      source: CharacterRevisionSource.rollback,
      sourceRef: sourceRef,
      reason: '回滚到版本 #${revision.id}',
    );
    return affected > 0;
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

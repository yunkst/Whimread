import '../../../models/character.dart';
import '../../../models/character_gallery_image.dart';

/// 角色数据仓库接口
///
/// 负责角色的数据访问操作，包括角色的CRUD操作、
/// 角色搜索和查询、角色图片管理
///
/// 注意：关系管理方法已移至 ICharacterRelationRepository
abstract class ICharacterRepository {
  // ========== 角色CRUD操作 ==========

  /// 创建角色
  ///
  /// [character] 要创建的角色对象
  /// 返回新插入记录的ID
  Future<int> createCharacter(Character character);

  /// 获取小说的所有角色
  ///
  /// [novelUrl] 小说URL
  /// 返回按创建时间升序排列的角色列表
  Future<List<Character>> getCharacters(String novelUrl);

  /// 根据ID获取角色
  ///
  /// [id] 角色ID
  /// 返回角色对象，如果不存在则返回null
  Future<Character?> getCharacter(int id);

  /// 更新角色
  ///
  /// [character] 要更新的角色对象（必须包含id）
  /// 返回受影响的行数
  Future<int> updateCharacter(Character character);

  /// 删除角色
  ///
  /// [id] 角色ID
  /// 返回受影响的行数
  Future<int> deleteCharacter(int id);

  /// 根据名称查找角色
  ///
  /// [novelUrl] 小说URL
  /// [name] 角色名称
  /// 返回角色对象，如果不存在则返回null
  Future<Character?> findCharacterByName(String novelUrl, String name);

  /// 删除小说的所有角色
  ///
  /// [novelUrl] 小说URL
  /// 返回受影响的行数
  Future<int> deleteAllCharacters(String novelUrl);

  // ========== 角色图片管理 ==========

  /// 更新角色头像的媒体资源ID
  ///
  /// [characterId] 角色ID
  /// [mediaId] 媒体资源ID（图像或视频），传 null 清空头像
  /// 返回受影响的行数
  Future<int> updateCharacterAvatarMediaId(int characterId, String? mediaId);

  // ========== 角色图集（character_images，v50） ==========

  /// 追加一张图集图片（sort 取当前最大值 +1）
  ///
  /// [characterId] 角色ID
  /// [mediaId] 媒体资源ID（须已通过 MediaProxy 登记存在）
  /// 返回新增条目（含 id / sort）
  Future<CharacterGalleryImage> addCharacterImage(
      int characterId, String mediaId);

  /// 查询角色图集（按 sort, id 升序）
  ///
  /// [characterId] 角色ID
  Future<List<CharacterGalleryImage>> getCharacterImages(int characterId);

  /// 从图集移除一条（仅删关联行，不删媒体文件）
  ///
  /// [imageId] character_images 行主键
  /// 返回受影响的行数
  Future<int> removeCharacterImage(int imageId);
}

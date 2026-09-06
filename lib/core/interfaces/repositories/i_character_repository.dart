import '../../../models/character.dart';

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

  /// 更新或插入角色（去重逻辑）
  ///
  /// 如果角色已存在（按novelUrl和name匹配），则更新现有角色
  /// 如果角色不存在，则创建新角色
  ///
  /// [newCharacter] 要更新或插入的角色
  /// 返回操作后的角色对象
  Future<Character> updateOrInsertCharacter(Character newCharacter);

  /// 批量更新角色
  ///
  /// 接受新角色列表，对每个角色执行去重更新逻辑
  ///
  /// [newCharacters] 要更新的角色列表
  /// 返回成功更新的角色列表
  Future<List<Character>> batchUpdateCharacters(List<Character> newCharacters);

  /// 获取小说的所有角色名称
  ///
  /// [novelUrl] 小说URL
  /// 返回按名称字母顺序排列的角色名称列表
  Future<List<String>> getCharacterNames(String novelUrl);

  /// 检查角色是否存在
  ///
  /// [id] 角色ID
  /// 返回角色是否存在
  Future<bool> characterExists(int id);

  /// 根据ID列表获取多个角色
  ///
  /// [ids] 角色ID列表
  /// 返回按创建时间升序排列的角色列表，如果ID列表为空则返回空列表
  Future<List<Character>> getCharactersByIds(List<int> ids);

  /// 删除小说的所有角色
  ///
  /// [novelUrl] 小说URL
  /// 返回受影响的行数
  Future<int> deleteAllCharacters(String novelUrl);

  // ========== 角色图片管理 ==========

  /// 更新角色的缓存图片URL
  ///
  /// [characterId] 角色ID
  /// [imageUrl] 缓存图片URL
  /// 返回受影响的行数
  Future<int> updateCharacterCachedImage(int characterId, String? imageUrl);

  /// 清除角色的缓存图片URL
  ///
  /// [characterId] 角色ID
  /// 返回受影响的行数
  Future<int> clearCharacterCachedImage(int characterId);

  /// 批量清除角色的缓存图片URL
  ///
  /// [novelUrl] 小说URL
  /// 返回受影响的行数
  Future<int> clearAllCharacterCachedImages(String novelUrl);

  /// 获取角色的缓存图片URL
  ///
  /// [characterId] 角色ID
  /// 返回头像缓存路径，如果没有设置则返回null
  Future<String?> getCharacterCachedImage(int characterId);

  /// 更新角色头像信息（扩展方法，支持更多元数据）
  ///
  /// [characterId] 角色ID
  /// [imageUrl] 头像URL/路径
  /// [originalFilename] 原始图集文件名（未使用）
  /// [originalImageUrl] 原始图片URL（未使用）
  /// 返回受影响的行数
  Future<int> updateCharacterAvatar(
    int characterId, {
    String? imageUrl,
    String? originalFilename,
    String? originalImageUrl,
  });

  /// 检查角色是否有头像缓存
  ///
  /// [characterId] 角色ID
  /// 返回是否有头像缓存
  Future<bool> hasCharacterAvatar(int characterId);

  /// 更新角色头像的媒体资源ID
  ///
  /// [characterId] 角色ID
  /// [mediaId] 媒体资源ID（图像或视频），传 null 清空头像
  /// 返回受影响的行数
  Future<int> updateCharacterAvatarMediaId(int characterId, String? mediaId);
}

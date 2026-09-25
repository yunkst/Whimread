import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/character.dart';
import '../../models/character_gallery_image.dart';
import 'database_providers.dart';

/// 角色列表 Provider（按小说 URL 索引）
///
/// 返回该小说下的所有角色，按创建时间升序（沿用 Repository 排序）。
/// 增 / 改 / 删 后调用 `ref.invalidate(characterListProvider(novelUrl))` 刷新。
final characterListProvider =
    FutureProvider.family<List<Character>, String>((ref, novelUrl) async {
  final repo = ref.watch(characterRepositoryProvider);
  return repo.getCharacters(novelUrl);
});

/// 角色图集 Provider（按角色 ID 索引）
///
/// 返回该角色的图集条目（按 sort, id 升序）。
/// 追加 / 移除后调用 `ref.invalidate(characterGalleryProvider(characterId))`
/// 刷新——Agent 生成入集（media_executor）与详情页管理共用同一刷新约定。
final characterGalleryProvider =
    FutureProvider.family<List<CharacterGalleryImage>, int>((ref, characterId) {
  final repo = ref.watch(characterRepositoryProvider);
  return repo.getCharacterImages(characterId);
});

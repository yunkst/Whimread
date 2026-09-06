import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/character.dart';
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

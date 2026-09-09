/// 生图模型相关 Provider
///
/// 手写 Provider（避免 codegen），模式与 mediaProxyProvider / siteScriptRepositoryProvider 一致：
/// - repository 挂 keepAlive 的 databaseConnectionProvider
/// - 列表用 FutureProvider，UI CRUD 后 ref.invalidate 刷新
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/image_model.dart';
import '../../repositories/image_model_repository.dart';
import 'database_providers.dart';

/// ImageModelRepository Provider
///
/// 生图模型元数据（image_models 表）的持久化操作
final imageModelRepositoryProvider = Provider<ImageModelRepository>((ref) {
  final dbConnection = ref.watch(databaseConnectionProvider);
  return ImageModelRepository(dbConnection: dbConnection);
});

/// 全部生图模型列表（按 sort_order 排序）
///
/// CRUD 后调用 `ref.invalidate(imageModelListProvider)` 刷新。
final imageModelListProvider = FutureProvider<List<ImageModel>>((ref) async {
  final repo = ref.watch(imageModelRepositoryProvider);
  return repo.getAll();
});

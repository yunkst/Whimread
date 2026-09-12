/// 生图后端 Provider + dispatcher
///
/// 生图完全走客户端本地引擎（sd.cpp）。未来接入 NPU（qnn）时在
/// [imageGenerationBackendsProvider] 的映射表里加一项即可。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart' show databaseConnectionProvider;
import '../../core/providers/services/network_service_providers.dart' show apiServiceWrapperProvider;
import '../../models/image_model.dart';
import '../media/media_proxy.dart';
import 'image_generation_backend.dart';
import 'local_sd_backend.dart';

/// 本地 sd.cpp 后端 Provider（阶段 B：FFI 真实现；签名与阶段 A 一致）
final localSdCppBackendProvider = Provider<LocalSdCppBackend>((ref) {
  final dbConn = ref.watch(databaseConnectionProvider);
  final api = ref.watch(apiServiceWrapperProvider);
  return LocalSdCppBackend(
    mediaProxy: MediaProxy(dbConn: dbConn, api: api),
  );
});

/// 后端实例映射（按 backendType 路由）
final imageGenerationBackendsProvider =
    Provider<Map<ImageModelBackendType, ImageGenerationBackend>>((ref) {
  return {
    ImageModelBackendType.localSd: ref.watch(localSdCppBackendProvider),
  };
});

/// 按 backendType 取出对应后端（family）
///
/// backendType 不识别时回退到本地引擎（单后端现状下即唯一实现）
final imageGenerationBackendByTypeProvider = Provider.family<
    ImageGenerationBackend, ImageModelBackendType>((ref, type) {
  final backends = ref.watch(imageGenerationBackendsProvider);
  return backends[type] ?? ref.watch(localSdCppBackendProvider);
});
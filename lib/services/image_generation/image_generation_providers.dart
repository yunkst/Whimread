/// 生图后端 Provider + dispatcher
///
/// 唯一后端：local_dream_embedded（本机嵌入式 Local Dream 引擎子进程）。
/// 历史上曾有 local_sd（端侧 sd.cpp FFI）与 local_dream（局域网设备宿主）
/// 两个后端，均已下线；未来接入新后端时在
/// [imageGenerationBackendsProvider] 的映射表里加一项即可。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_providers.dart' show databaseConnectionProvider;
import '../../models/image_model.dart';
import '../media/media_proxy.dart';
import '../local_dream_embedded/engine_manager.dart';
import 'image_generation_backend.dart';
import '../logger_service.dart';
import 'image_generation_service.dart';
import 'local_dream_embedded_backend.dart';

/// Local Dream 嵌入式引擎后端 Provider（引擎子进程全局单例）
final localDreamEmbeddedEngineManagerProvider =
    Provider<LocalDreamEngineManager>((ref) {
  final manager = LocalDreamEngineManager();
  ref.onDispose(() {
    // 容器销毁时停掉引擎子进程并关闭状态流
    //（防热重载/测试容器重建后留下孤儿进程）
    unawaited(manager.stop());
    manager.dispose();
  });
  return manager;
});

/// 引擎自检（引擎二进制 / QNN 运行库就绪情况；模型管理页提示条用）
final localDreamReadinessProvider =
    FutureProvider<({bool binary, bool qnn})>((ref) async {
  final manager = ref.watch(localDreamEmbeddedEngineManagerProvider);
  final binary = await manager.isBinaryAvailable();
  final qnn = await manager.isQnnRuntimeReady();
  // 自检结果只显示在提示条上，日志无痕迹；engine_not_ready 的排查要靠它
  // 判断是缺引擎二进制还是缺 QNN 运行库。
  LoggerService.instance.i(
    '引擎自检：binary=$binary，qnn=$qnn',
    category: LogCategory.ai,
    tags: const ['local_dream_engine', 'readiness'],
  );
  return (binary: binary, qnn: qnn);
});

final localDreamEmbeddedBackendProvider = Provider<LocalDreamEmbeddedBackend>(
    (ref) {
  final dbConn = ref.watch(databaseConnectionProvider);
  return LocalDreamEmbeddedBackend(
    mediaProxy: MediaProxy(dbConn: dbConn),
    engineManager: ref.watch(localDreamEmbeddedEngineManagerProvider),
  );
});

/// 后端实例映射（按 backendType 路由）
final imageGenerationBackendsProvider =
    Provider<Map<ImageModelBackendType, ImageGenerationBackend>>((ref) {
  return {
    ImageModelBackendType.localDreamEmbedded:
        ref.watch(localDreamEmbeddedBackendProvider),
  };
});

/// 按 backendType 取出对应后端（family）
///
/// backendType 不识别时（历史残留行）回退到嵌入式引擎（唯一实现）
final imageGenerationBackendByTypeProvider = Provider.family<
    ImageGenerationBackend, ImageModelBackendType>((ref, type) {
  final backends = ref.watch(imageGenerationBackendsProvider);
  return backends[type] ?? ref.watch(localDreamEmbeddedBackendProvider);
});

/// 生图统一提交门面（模型选取 + 请求构造 + 错误码映射）
final imageGenerationServiceProvider = Provider<ImageGenerationService>(
    (ref) => ImageGenerationService(ref));

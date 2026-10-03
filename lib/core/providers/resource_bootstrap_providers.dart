/// 启动资源引导 Provider。
///
/// 编排三类动态资源的启动校验/下载（详见
/// lib/services/app_resource_manager.dart 头注释）：
/// - ui_fonts  : 走统一 manifest，下载后 FontLoader 注册
/// - ocr_model : 委托 OcrModelDownloader（独立 manifest），仅汇报进度
/// - local_dream_qnn : 走统一 manifest，NPU 引擎 dlopen 用的 QNN 运行库
///   （.so）；引擎启动时只解析本地目录，不再触发网络（非 Android 自动跳过）
///
/// 跳过语义：SharedPreferences 记 `resource_bootstrap_skipped_<manifestVersion>`，
/// 同一 manifest 版本内跳过后不再弹引导页（后台静默补下载），manifest
/// 升版后重新弹。
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/app_resource_manager.dart';
import '../../services/logger_service.dart';
import '../../services/ocr_model_downloader.dart';
import 'ocr_providers.dart';

part 'resource_bootstrap_providers.g.dart';

final _prefKeyPrefix = 'resource_bootstrap_skipped_';

@riverpod
AppResourceManager appResourceManager(Ref ref) => AppResourceManager();

/// 启动资源引导编排器（Notifier 驱动 ResourceBootstrapScreen）
@riverpod
class ResourceBootstrapNotifier extends _$ResourceBootstrapNotifier {
  static const _itemOrder = [
    ResourceIds.uiFonts,
    ResourceIds.ocrModel,
    ResourceIds.localDreamQnn,
  ];

  Dio? _downloadDio;

  /// build 期同步捕获的依赖：skip() 后引导页 unmount → autoDispose
  /// Notifier dispose → 此后再 ref.read 会抛 StateError。后台静默
  /// 补下载必须在 dispose 后继续跑，所以依赖只能在存活期捕获到字段里。
  AppResourceManager? _manager;
  OcrModelDownloader? _downloader;

  /// dispose 标记（Riverpod 2.4 无 ref.mounted）：置位后 state 写入
  /// 全部 no-op，避免向已 dispose 的 Notifier 写 state 抛 StateError
  bool _disposed = false;

  @override
  ResourceBootstrapState build() {
    ref.onDispose(() => _disposed = true);
    _manager = ref.read(appResourceManagerProvider);
    _downloader = ref.read(ocrModelDownloaderProvider);
    return const ResourceBootstrapState(itemIds: _itemOrder, items: {});
  }

  void _update(String id, ResourceItemState s) {
    if (_disposed) return; // dispose 后后台补下载继续，UI 状态写入静默丢弃
    final items = Map<String, ResourceItemState>.of(state.items);
    items[id] = s;
    state = state.copyWith(items: items);
  }

  void _progress(String id, int received, int total) {
    final cur = state.items[id];
    // 字节进度回调可能晚于状态推进，completed 后忽略
    if (cur == null || cur.status == ResourceItemStatus.ready) return;
    _update(id, cur.copyWith(status: ResourceItemStatus.downloading,
        received: received, total: total, error: null));
  }

  void _fail(String id, Object e) {
    final cur = state.items[id] ??
        ResourceItemState(id: id, status: ResourceItemStatus.pending);
    _update(id, cur.copyWith(status: ResourceItemStatus.failed,
        error: e.toString()));
  }

  void _ready(String id) {
    final cur = state.items[id] ??
        ResourceItemState(id: id, status: ResourceItemStatus.pending);
    _update(id, cur.copyWith(status: ResourceItemStatus.ready,
        received: 1, total: 1, error: null));
  }

  /// 启动入口：校验本地 + 按需下载。manifest 拉取失败时全部放行
  /// （保持旧行为：各功能自行按需降级）。
  ///
  /// 结果反映在 [state]：全部就绪时 [ResourceBootstrapState.completed]，
  /// UI 结合 [skippedThisManifest] 决定展示引导页或直接放行。
  Future<void> bootstrap() async {
    state = state.copyWith(checking: true);
    for (final id in _itemOrder) {
      _update(id, ResourceItemState(id: id, status: ResourceItemStatus.checking));
    }

    final manager = ref.read(appResourceManagerProvider);
    final prefs = await SharedPreferences.getInstance();
    AppResourcesManifest? manifest;
    try {
      manifest = await manager.fetchManifest();
    } catch (e, st) {
      LoggerService.instance.w(
        '资源 manifest 拉取失败，放行进入 App(功能按需降级): $e',
        stackTrace: st.toString(),
        category: LogCategory.general,
        tags: ['resource', 'bootstrap', 'manifest-error'],
      );
      // 全部按 ready 放行，不阻塞
      for (final id in _itemOrder) {
        _update(id, ResourceItemState(id: id, status: ResourceItemStatus.ready));
      }
      state = state.copyWith(checking: false, completed: true);
      return;
    }

    final skippedKey = '$_prefKeyPrefix${manifest.manifestVersion}';
    final silentlySkip = prefs.getBool(skippedKey) ?? false;
    _skippedThisManifest = silentlySkip;

    // manifest 拉取阶段结束：此后进入逐资源校验/下载，
    // UI（_ResourceGate）据此从加载页切到引导页展示进度
    state = state.copyWith(checking: false);

    // 并行推进三个资源；任一失败不影响其他资源
    await Future.wait([
      _bootstrapFonts(manager, manifest),
      _bootstrapOcr(),
      _bootstrapQnn(manager, manifest),
    ]);

    final allReady = !state.hasFailure &&
        state.items.values.every((s) => s.status == ResourceItemStatus.ready);
    state = state.copyWith(completed: allReady);
    if (allReady) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
          '$_prefKeyPrefix${manifest.manifestVersion}', false);
    }
  }

  /// 本 manifest 版本内用户是否跳过过（bootstrap() 后有效）。
  /// UI 据此决定：有缺失时是弹引导页还是直接放行（后台静默补）。
  bool get skippedThisManifest => _skippedThisManifest;
  bool _skippedThisManifest = false;

  Future<void> _bootstrapFonts(
      AppResourceManager manager, AppResourcesManifest manifest) async {
    final spec = manifest.resources[ResourceIds.uiFonts];
    if (spec == null) {
      _ready(ResourceIds.uiFonts);
      return;
    }
    try {
      final files = await manager.ensureResource(spec,
          onProgress: (r, t) => _progress(ResourceIds.uiFonts, r, t));
      await manager.registerFonts(files);
      _ready(ResourceIds.uiFonts);
    } catch (e) {
      _fail(ResourceIds.uiFonts, e);
    }
  }

  Future<void> _bootstrapOcr() async {
    try {
      // 用 build 期捕获的实例，dispose 后不再触碰 ref
      final downloader = _downloader;
      if (downloader == null) return;
      await downloader.ensureLocal(
          onProgress: (r, t) => _progress(ResourceIds.ocrModel, r, t));
      _ready(ResourceIds.ocrModel);
    } catch (e) {
      _fail(ResourceIds.ocrModel, e);
    }
  }

  /// QNN 运行库（local_dream_qnn）：NPU 引擎 dlopen 用的 .so 集合。
  /// Android 专属；ensureResource 内含 sha256 命中判断，
  /// 已就绪时零流量直过。引擎启动只解析本目录，不再走网络。
  Future<void> _bootstrapQnn(
      AppResourceManager manager, AppResourcesManifest manifest) async {
    if (!await _isAndroid()) {
      _ready(ResourceIds.localDreamQnn);
      return;
    }
    final spec = manifest.resources[ResourceIds.localDreamQnn];
    if (spec == null) {
      // 清单未发布：按"各功能按需降级"放行，NPU 启动时报缺库错误
      _ready(ResourceIds.localDreamQnn);
      return;
    }
    try {
      await manager.ensureResource(spec,
          onProgress: (r, t) => _progress(ResourceIds.localDreamQnn, r, t));
      _ready(ResourceIds.localDreamQnn);
    } catch (e) {
      _fail(ResourceIds.localDreamQnn, e);
    }
  }

  /// 跳过：记录标记 + 后台静默补下载。manifest 升版后标记自然失效。
  Future<void> skip() async {
    try {
      final manager = ref.read(appResourceManagerProvider);
      final manifest = await manager.fetchManifest();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefKeyPrefix${manifest.manifestVersion}', true);
    } catch (_) {/* 拿不到 manifest 就不落标记，下次重新引导 */}
    _continueInBackground();
    state = state.copyWith(completed: true);
  }

  /// 失败项后台重试（引导页点"重试"时用）
  Future<void> retryFailed() async {
    final manager = ref.read(appResourceManagerProvider);
    AppResourcesManifest manifest;
    try {
      manifest = await manager.fetchManifest();
    } catch (_) {
      return;
    }
    await Future.wait([
      if (state.items[ResourceIds.uiFonts]?.status != ResourceItemStatus.ready)
        _bootstrapFonts(manager, manifest),
      if (state.items[ResourceIds.ocrModel]?.status != ResourceItemStatus.ready)
        _bootstrapOcr(),
      if (await _isAndroid() &&
          state.items[ResourceIds.localDreamQnn]?.status !=
              ResourceItemStatus.ready)
        _bootstrapQnn(manager, manifest),
    ]);
    final allReady = !state.hasFailure &&
        state.items.values.every((s) => s.status == ResourceItemStatus.ready);
    state = state.copyWith(completed: allReady);
  }

  /// 不改 UI 状态，静默把缺失资源补齐（跳过后调用）。
  /// 独立 Dio，避免占用引导页下载通道。
  void _continueInBackground() {
    // ref.read 只在存活期同步执行；此后 Notifier 随引导页 unmount 被
    // dispose，后台闭包只操作捕获的依赖 + no-op 化的 _update
    final manager = _manager;
    if (manager == null) return;
    _downloadDio ??= Dio();
    unawaited(() async {
      try {
        final manifest = await manager.fetchManifest();
        await Future.wait([
          _bootstrapFonts(manager, manifest),
          _bootstrapOcr(),
          if (await _isAndroid()) _bootstrapQnn(manager, manifest),
        ]);
        LoggerService.instance.i(
          '跳过后台资源补下载完成',
          category: LogCategory.general,
          tags: ['resource', 'bootstrap', 'background_done'],
        );
      } catch (_) {/* 静默失败：下次启动重新校验 */}
    }());
  }

  Future<bool> _isAndroid() async => Platform.isAndroid;
}

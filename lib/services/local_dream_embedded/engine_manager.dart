/// Local Dream 嵌入式引擎进程管理器
///
/// 引擎是"伪装成 .so 的可执行文件"（jniLibs 打包 → nativeLibraryDir），
/// 以子进程形态运行并监听 localhost:8081（/generate /health）。
///
/// 职责：
/// - 探测引擎二进制是否已打包（缺失时给出放置引导）
/// - 解析 QNN 运行库目录（dlopen 语义不受 W^X exec 限制）：下载与
///   sha256 校验由启动资源引导（resource_bootstrap）完成，引擎启动
///   只查本地目录，不触发网络
/// - 启动/停止子进程：参数相同复用运行中的实例，不同则重启切换模型
/// - 启动后轮询 /health 等待模型加载完成（NPU 图加载可达数十秒）
///
/// 生命周期策略：与远程设备模式一致——生成完成后保持运行，App 退出
/// 时随进程组结束（下次启动冷启，代价是重新加载模型）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../app_resource_manager.dart';
import '../logger_service.dart';
import '../image_generation/local_dream_client.dart';
import 'model_pack.dart';

/// 引擎操作/启动失败的异常
class LocalDreamEngineException implements Exception {
  final String message;
  const LocalDreamEngineException(this.message);

  @override
  String toString() => message;
}

/// 引擎运行状态（供测试页/状态卡展示）
@immutable
class LocalDreamEngineStatus {
  final bool running;
  final int? pid;
  final LocalDreamPackType? type;
  final String? modelDir;

  const LocalDreamEngineStatus({
    required this.running,
    this.pid,
    this.type,
    this.modelDir,
  });

  const LocalDreamEngineStatus.stopped()
      : running = false,
        pid = null,
        type = null,
        modelDir = null;

  /// 模型包与运行中实例是否一致（一致则 submit 无需重启引擎）
  bool matches(LocalDreamPackType type, String modelDir) =>
      running && this.type == type && this.modelDir == modelDir;
}

class LocalDreamEngineManager {
  /// 引擎可执行文件名（伪装 .so；Local Dream build.sh 产物）
  static const String executableName = 'libstable_diffusion_core.so';

  /// 引擎监听端口（Local Dream 协议常量）
  static const int port = LocalDreamPorts.generation;

  /// /health 轮询等待模型加载的上限（SDXL NPU 图加载可达数十秒）
  static const Duration startTimeout = Duration(seconds: 120);

  static const MethodChannel _channel =
      MethodChannel('com.example.novel_app/engine');

  final LocalDreamClient _client;
  final AppResourceManager _resources;

  Process? _process;
  LocalDreamEngineStatus _status = const LocalDreamEngineStatus.stopped();
  String? _cachedNativeLibDir;
  bool _stopping = false;

  /// 引擎最近输出的环形缓冲（stdout+stderr 混合，仅本次进程）。
  /// 引擎崩溃的真实原因在 stderr 里，而 LogReporterService 默认只上传
  /// warning+，d 级转发到不了反馈侧（历史反馈只有 code=1 没有原因）。
  /// 意外退出时把缓冲以 warning 级吐出去。
  static const int _engineOutputBufferSize = 60;
  final List<String> _recentEngineOutput = [];

  /// 状态变更广播（启动就绪 / 意外退出 / 主动停止后触发）
  final StreamController<LocalDreamEngineStatus> _statusChanges =
      StreamController<LocalDreamEngineStatus>.broadcast();

  /// 释放资源（关闭状态流；容器销毁时调用）
  void dispose() {
    _statusChanges.close();
  }

  void _setStatus(LocalDreamEngineStatus s) {
    _status = s;
    if (!_statusChanges.isClosed) _statusChanges.add(s);
  }

  /// 引擎操作互斥链：ensureStarted 的"检查-启动"与 stop 串行执行，
  /// 防止并发调用双双 spawn（第二个绑 8081 端口失败）或 stop 误杀
  /// 对方刚 spawn 的进程
  Future<void> _opChain = Future<void>.value();

  /// 进行中的启动任务（单飞去重：相同参数的并发 start 复用同一 Future）
  _ActiveStart? _activeStart;

  LocalDreamEngineManager({LocalDreamClient? client, AppResourceManager? resourceManager})
      : _client = client ?? LocalDreamClient(host: '127.0.0.1'),
        _resources = resourceManager ?? AppResourceManager();

  /// 当前运行状态（同步快照）
  LocalDreamEngineStatus get status => _status;

  /// 构造引擎启动参数（纯函数，便于测试参数矩阵）。
  ///
  /// **不要把可执行文件路径放进参数**：Dart 的 `Process.start(path, args)`
  /// 会自己把 path 作为 argv[0]，重复传入会让引擎的参数解析器先遇到一个
  /// 非选项 token，报 "Invalid argument passed." + 打印 usage 后 exit(1)
  /// （历史事故：预览版一直 code=1，引擎从未成功启动过；Local Dream 用 Java
  /// ProcessBuilder 不传 argv[0] 故正常）。
  ///
  /// 对齐 Local Dream BackendService.startBackend：
  /// `--type <t> --model_dir <dir> --port 8081 [--lib_dir <runtime>]`
  /// `[--use_v_pred] [--lowram]`
  /// （sd15cpu 纯 MNN 不需要 lib_dir；QNN 类型必须提供，缺失抛异常；
  ///  SDXL 默认带 --lowram：分阶段加载/释放模型，手机内存必需）。
  @visibleForTesting
  static List<String> buildEngineArgs({
    required LocalDreamPackType type,
    required String modelDir,
    String? runtimeDir,
    bool useVPred = false,
    bool lowram = false,
  }) {
    if (type.needsQnnLibs && runtimeDir == null) {
      throw const LocalDreamEngineException('QNN 运行库目录缺失，无法启动 NPU 引擎');
    }
    return [
      '--type',
      type.dbName,
      '--model_dir',
      modelDir,
      '--port',
      '$port',
      // 仅 QNN 类型需要 lib_dir（sd15cpu 纯 MNN，即使给了 runtimeDir 也不带）
      if (type.needsQnnLibs && runtimeDir != null)
        ...['--lib_dir', runtimeDir],
      // v-prediction 模型：包目录里有 V_PRED 标记文件时启用
      if (useVPred) '--use_v_pred',
      // SDXL 分阶段加载/释放（Local Dream 默认开启）
      if (lowram) '--lowram',
    ];
  }

  /// 引擎可执行文件是否已打包（jniLibs → nativeLibraryDir）
  Future<bool> isBinaryAvailable() async {
    final dir = await nativeLibDir();
    if (dir == null) return false;
    return File('$dir${Platform.pathSeparator}$executableName')
        .existsSync();
  }

  /// nativeLibraryDir（Android 平台通道；非 Android/通道缺失返回 null）
  Future<String?> nativeLibDir() async {
    if (!Platform.isAndroid) return null;
    if (_cachedNativeLibDir != null) return _cachedNativeLibDir;
    try {
      final dir =
          await _channel.invokeMethod<String>('getNativeLibraryDir');
      _cachedNativeLibDir = dir;
      return dir;
    } on PlatformException catch (e) {
      LoggerService.instance.w('获取 nativeLibraryDir 失败: ${e.message}',
          category: LogCategory.ai,
          tags: ['local_dream_engine', 'channel']);
      return null;
    } on MissingPluginException {
      // 通道缺失（如非 Android 构建/插件未注册）与真"未打包"区分开
      LoggerService.instance.d('引擎通道缺失，nativeLibraryDir 不可用',
          category: LogCategory.ai,
          tags: ['local_dream_engine', 'channel']);
      return null;
    }
  }

  /// QNN 运行库是否已下载就绪（本地检查，不触发网络/下载；
  /// 下载与 sha256 校验由启动资源引导完成）
  Future<bool> isQnnRuntimeReady() => _resources.localDreamQnnReady();

  /// 解析 QNN 运行库目录（纯本地：启动引导已下载校验过，这里只定位）。
  /// sd15cpu 纯 MNN 不需要 → null；NPU 类型缺库时抛错并指向启动引导。
  Future<String?> _resolveQnnRuntimeDir(LocalDreamPackType type) async {
    if (!type.needsQnnLibs) return null;
    if (!await _resources.localDreamQnnReady()) {
      throw const LocalDreamEngineException(
          'QNN 运行库未就绪：请联网重启应用，待启动资源引导完成后再试');
    }
    final dir = await _resources.resourceDir(ResourceIds.localDreamQnn);
    return dir.path;
  }

  /// 确保引擎以 [type] + [modelDir] 运行并健康（模型加载完成）。
  ///
  /// - 未运行 → 启动；
  /// - 运行中且参数一致 → 直接返回（连续出图零开销）；
  /// - 运行中但参数不同 → 停止旧实例后重启（切换模型）。
  ///
  /// 并发安全：操作经互斥链串行执行；相同参数的进行中启动直接复用
  /// 其 Future（单飞），不会重复 spawn，也不会与 stop 交叉执行。
  Future<void> ensureStarted({
    required LocalDreamPackType type,
    required String modelDir,
  }) async {
    // 单飞：相同参数的启动已在进行中 → 复用同一 Future（含异常语义）
    final active = _activeStart;
    if (active != null && active.type == type && active.modelDir == modelDir) {
      return active.future!;
    }
    final pending = _ActiveStart(type, modelDir);
    _activeStart = pending;
    final op = _enqueue(() async {
      try {
        if (_status.matches(type, modelDir) && await _client.health()) {
          return;
        }
        await _stopInternal();
        await _spawn(type: type, modelDir: modelDir);
      } finally {
        // 只清理仍属于自己的记录（期间可能有不同参数的新任务已入队）
        if (identical(_activeStart, pending)) _activeStart = null;
      }
    });
    pending.future = op;
    return op;
  }

  /// 把操作挂到互斥链尾串行执行；链本身吞掉前序操作的错误，
  /// 保证一次失败不阻断后续操作（返回值保留原始异常语义）。
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final run = _opChain.then((_) => action());
    _opChain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _spawn({
    required LocalDreamPackType type,
    required String modelDir,
  }) async {
    final nativeDir = await nativeLibDir();
    final executable = nativeDir == null
        ? null
        : File(
            '$nativeDir${Platform.pathSeparator}$executableName');
    if (executable == null || !executable.existsSync()) {
      throw const LocalDreamEngineException(
          '引擎未打包：缺少 libstable_diffusion_core.so。'
          '请按 docs/local_dream_engine.md 放置 Local Dream 引擎产物后重新构建安装。');
    }

    // QNN 运行库目录（启动引导已下载校验，这里纯本地解析）
    final runtimeDir = await _resolveQnnRuntimeDir(type);

    // 对齐 Local Dream startBackend 的设备相关开关：
    // - v-prediction：包目录有 V_PRED 标记文件时启用
    // - SDXL 默认 --lowram（分阶段加载/释放模型，手机内存必需；
    //   Local Dream 的 sdxl_lowram preference 默认 true）
    final useVPred = File(p.join(modelDir, 'V_PRED')).existsSync();
    final args = buildEngineArgs(
      type: type,
      modelDir: modelDir,
      runtimeDir: runtimeDir,
      useVPred: useVPred,
      lowram: type == LocalDreamPackType.sdxl,
    );
    // 启动日志带完整 argv：传参类问题一眼可见（反馈 #12→#14 的教训）
    LoggerService.instance.i(
        '启动 Local Dream 引擎: type=${type.dbName}, modelDir=$modelDir, '
        'port=$port, libDir=${runtimeDir ?? "无"}, '
        'useVPred=$useVPred, lowram=${type == LocalDreamPackType.sdxl}',
        category: LogCategory.ai,
        tags: ['local_dream_engine', 'start']);

    final process = await Process.start(
      executable.path,
      args,
      // 对齐 Local Dream：LD_LIBRARY_PATH 含系统与 vendor 路径（引擎可能
      // 依赖 GPU/vendor 库），DSP_LIBRARY_PATH 指向 QNN 运行库（DSP 侧），
      // 工作目录设为 nativeLibraryDir。
      workingDirectory: nativeDir,
      environment: {
        if (runtimeDir != null)
          'LD_LIBRARY_PATH': [
            runtimeDir,
            '/system/lib64',
            '/vendor/lib64',
            '/vendor/lib64/egl',
          ].join(':'),
        if (runtimeDir != null) 'DSP_LIBRARY_PATH': runtimeDir,
      },
      // 引擎日志走 stdout/stderr，转发到应用日志便于排障
      mode: ProcessStartMode.normal,
    );
    _process = process;
    _stopping = false;
    _recentEngineOutput.clear();
    _setStatus(LocalDreamEngineStatus(
      running: true,
      pid: process.pid,
      type: type,
      modelDir: modelDir,
    ));

    // 引擎日志转发（不阻塞；onError 兜底避免未处理流错误）
    process.stdout
        .transform(systemEncoding.decoder)
        .listen((line) => _logEngine('stdout', line),
            onError: (Object e) => LoggerService.instance.w(
                '引擎 stdout 流错误: $e',
                category: LogCategory.ai,
                tags: ['local_dream_engine', 'log']));
    process.stderr
        .transform(systemEncoding.decoder)
        .listen((line) => _logEngine('stderr', line),
            onError: (Object e) => LoggerService.instance.w(
                '引擎 stderr 流错误: $e',
                category: LogCategory.ai,
                tags: ['local_dream_engine', 'log']));
    unawaited(process.exitCode.then((code) {
      if (_stopping) return; // 主动停止的退出属预期
      LoggerService.instance.w(
          'Local Dream 引擎意外退出: pid=${process.pid}, code=$code',
          category: LogCategory.ai,
          tags: ['local_dream_engine', 'exit']);
      // 引擎自己打的 stderr/stdout 才有真正原因（缺文件/QNN 加载失败/
      // HTP 架构不匹配等），随反馈上报
      if (_recentEngineOutput.isNotEmpty) {
        LoggerService.instance.w(
          '引擎最近输出（${_recentEngineOutput.length} 行）:\n'
          '${_recentEngineOutput.join('\n')}',
          category: LogCategory.ai,
          tags: ['local_dream_engine', 'exit-output'],
        );
      }
      // 模型目录实况（只看文件名，不读内容）：引擎报 "File not found" 时能
      // 直接对照包里到底有什么
      if (_status.modelDir != null) {
        try {
          final files = Directory(_status.modelDir!)
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .toList()
            ..sort();
          final shown =
              files.take(30).join(', ') + (files.length > 30 ? ' …' : '');
          LoggerService.instance.w(
            '模型目录实况（${files.length} 个文件）: $shown',
            category: LogCategory.ai,
            tags: ['local_dream_engine', 'exit-modeldir'],
          );
        } catch (_) {
          // 目录已删/无权限，忽略
        }
      }
      if (identical(_process, process)) {
        _process = null;
        _setStatus(const LocalDreamEngineStatus.stopped());
      }
    }));

    // 轮询 /health 等待模型加载完成
    final deadline = DateTime.now().add(startTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (identical(_process, process) && await _client.health()) {
        LoggerService.instance.i('Local Dream 引擎就绪: pid=${process.pid}',
            category: LogCategory.ai,
            tags: ['local_dream_engine', 'ready']);
        return;
      }
      if (_process != process) {
        throw const LocalDreamEngineException('引擎进程在启动过程中退出');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // 超时收尾：直接调 _stopInternal，不经 stop() 入队。
    // _spawn 本身运行在 _opChain 当前节点上，stop() 会把 _stopInternal
    // 追加到链尾（链尾要等 _spawn 返回才轮到）→ 循环等待，链永久死锁。
    await _stopInternal();
    throw LocalDreamEngineException(
        '引擎启动超时（>${startTimeout.inSeconds}s 未就绪），请查看日志排查模型加载错误');
  }

  /// 停止引擎进程（未运行则无操作）。
  /// 与启动互斥（经 [_opChain] 串行）：不会杀掉进行中启动刚 spawn 的进程，
  /// 而是等那次启动结束后再停。
  Future<void> stop() => _enqueue(_stopInternal);

  /// 停止引擎的实际逻辑（不经互斥链——由 ensureStarted 在链内复用）
  Future<void> _stopInternal() async {
    final process = _process;
    if (process == null) return;
    _stopping = true;
    process.kill();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      exitCode = await process.exitCode;
    }
    LoggerService.instance.i(
        'Local Dream 引擎已停止: pid=${process.pid}, exit=$exitCode',
        category: LogCategory.ai,
        tags: ['local_dream_engine', 'stop']);
    if (identical(_process, process)) {
      _process = null;
      _setStatus(const LocalDreamEngineStatus.stopped());
    }
  }

  void _logEngine(String source, String chunk) {
    for (final line in chunk.split('\n')) {
      if (line.trim().isEmpty) continue;
      // 环形缓冲保留最近 N 行，退出时随 warning 上报
      _recentEngineOutput.add('[$source] ${line.trim()}');
      if (_recentEngineOutput.length > _engineOutputBufferSize) {
        _recentEngineOutput.removeAt(0);
      }
      LoggerService.instance.d('引擎[$source] ${line.trim()}',
          category: LogCategory.ai,
          tags: ['local_dream_engine', 'log']);
    }
  }
}

/// 进行中的启动任务记录（配合 [_opChain] 实现单飞去重）
class _ActiveStart {
  final LocalDreamPackType type;
  final String modelDir;

  /// 挂起后赋值（ensureStarted 入队后立即回填，无 await 间隙）
  Future<void>? future;

  _ActiveStart(this.type, this.modelDir);
}

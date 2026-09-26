/// Local Dream 嵌入式引擎进程管理器
///
/// 引擎是"伪装成 .so 的可执行文件"（jniLibs 打包 → nativeLibraryDir），
/// 以子进程形态运行并监听 localhost:8081（/generate /health）。
///
/// 职责：
/// - 探测引擎二进制 / QNN 运行库是否已打包（缺失时给出放置引导）
/// - 解压 QNN 运行库（经 Kotlin 通道，rootBundle 无法枚举资产目录）
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

  Process? _process;
  LocalDreamEngineStatus _status = const LocalDreamEngineStatus.stopped();
  String? _cachedNativeLibDir;
  bool _stopping = false;

  /// 引擎操作互斥链：ensureStarted 的"检查-启动"与 stop 串行执行，
  /// 防止并发调用双双 spawn（第二个绑 8081 端口失败）或 stop 误杀
  /// 对方刚 spawn 的进程
  Future<void> _opChain = Future<void>.value();

  /// 进行中的启动任务（单飞去重：相同参数的并发 start 复用同一 Future）
  _ActiveStart? _activeStart;

  LocalDreamEngineManager({LocalDreamClient? client})
      : _client = client ?? LocalDreamClient(host: '127.0.0.1');

  /// 当前运行状态（同步快照）
  LocalDreamEngineStatus get status => _status;

  /// 构造引擎启动命令行（纯函数，便于测试参数矩阵）。
  ///
  /// 对齐 Local Dream BackendService.startBackend：
  /// `<exe> --type <t> --model_dir <dir> --port 8081 [--lib_dir <runtime>]`
  /// （sd15cpu 纯 MNN 不需要 lib_dir；QNN 类型必须提供，缺失抛异常）。
  @visibleForTesting
  static List<String> buildEngineArgs({
    required LocalDreamPackType type,
    required String modelDir,
    required String executablePath,
    String? runtimeDir,
  }) {
    if (type.needsQnnLibs && runtimeDir == null) {
      throw const LocalDreamEngineException('QNN 运行库目录缺失，无法启动 NPU 引擎');
    }
    return [
      executablePath,
      '--type',
      type.dbName,
      '--model_dir',
      modelDir,
      '--port',
      '$port',
      // 仅 QNN 类型需要 lib_dir（sd15cpu 纯 MNN，即使给了 runtimeDir 也不带）
      if (type.needsQnnLibs && runtimeDir != null)
        ...['--lib_dir', runtimeDir],
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

  /// QNN 运行库是否已打包（纯查询：只枚举 assets，不触发解压——
  /// 解压由 [ensureStarted] 内的 prepareQnnLibs 显式完成）
  Future<bool> isQnnAssetsAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasQnnLibsAssets') ?? false;
    } on PlatformException catch (e) {
      // 通道异常 ≠ 未打包（Kotlin 侧打包缺失会正常回 false）：warn 区分排障
      LoggerService.instance.w(
          '查询 QNN 资产失败（通道异常）: ${e.message ?? e.code}',
          category: LogCategory.ai,
          tags: ['local_dream_engine', 'channel']);
      return false;
    } on MissingPluginException {
      LoggerService.instance.d('引擎通道缺失，QNN 资产查询不可用',
          category: LogCategory.ai,
          tags: ['local_dream_engine', 'channel']);
      return false;
    }
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

    String? runtimeDir;
    if (type.needsQnnLibs) {
      try {
        runtimeDir =
            await _channel.invokeMethod<String>('prepareQnnLibs');
      } on PlatformException catch (e) {
        throw LocalDreamEngineException(
            '准备 QNN 运行库失败：${e.message ?? e.code}');
      }
      if (runtimeDir == null || runtimeDir.isEmpty) {
        throw const LocalDreamEngineException(
            'QNN 运行库未打包：assets/local_dream/qnnlibs 为空。'
            '请按 docs/local_dream_engine.md 放置 Local Dream 引擎产物。');
      }
    }

    final args = buildEngineArgs(
      type: type,
      modelDir: modelDir,
      executablePath: executable.path,
      runtimeDir: runtimeDir,
    );

    LoggerService.instance.i(
        '启动 Local Dream 引擎: type=${type.dbName}, modelDir=$modelDir',
        category: LogCategory.ai,
        tags: ['local_dream_engine', 'start']);

    final process = await Process.start(
      executable.path,
      args,
      environment: {
        if (runtimeDir != null) 'LD_LIBRARY_PATH': runtimeDir,
      },
      // 引擎日志走 stdout/stderr，转发到应用日志便于排障
      mode: ProcessStartMode.normal,
    );
    _process = process;
    _stopping = false;
    _status = LocalDreamEngineStatus(
      running: true,
      pid: process.pid,
      type: type,
      modelDir: modelDir,
    );

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
      if (identical(_process, process)) {
        _process = null;
        _status = const LocalDreamEngineStatus.stopped();
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
    await stop();
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
      _status = const LocalDreamEngineStatus.stopped();
    }
  }

  void _logEngine(String source, String chunk) {
    for (final line in chunk.split('\n')) {
      if (line.trim().isEmpty) continue;
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

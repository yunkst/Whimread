/// Local Dream 嵌入式引擎测试页
///
/// 测试体验对齐 Local Dream 生成页：完整参数表单（正向/负向提示词、
/// 步数、CFG、调度器、seed、尺寸）、逐步预览（show_diffusion_process，
/// 采样中每步刷新中间图）、结果图与耗时统计。
///
/// 入口：设置页 AI 分组「Local Dream 引擎（Beta）」。
library;

import 'dart:io' show Platform, ProcessException;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/image_model_providers.dart';
import '../../models/image_model.dart';
import '../../services/image_generation/image_generation_providers.dart';
import '../../services/image_generation/local_dream_client.dart';
import '../../services/local_dream_embedded/engine_manager.dart';
import '../../services/local_dream_embedded/model_pack.dart';
import '../../utils/toast_utils.dart';

class LocalDreamEngineScreen extends ConsumerStatefulWidget {
  const LocalDreamEngineScreen({super.key});

  @override
  ConsumerState<LocalDreamEngineScreen> createState() =>
      _LocalDreamEngineScreenState();
}

class _LocalDreamEngineScreenState
    extends ConsumerState<LocalDreamEngineScreen> {
  late final LocalDreamEngineManager _manager =
      ref.read(localDreamEmbeddedEngineManagerProvider);

  bool? _binaryAvailable;
  bool? _qnnAvailable;
  LocalDreamEngineStatus _status = const LocalDreamEngineStatus.stopped();

  ImageModel? _selectedModel;
  bool _starting = false;
  bool _stopping = false;

  // 生成表单（Local Dream 生成页同款参数；默认值取模型条目）
  final _promptController = TextEditingController();
  final _negativeController = TextEditingController();
  final _stepsController = TextEditingController();
  final _cfgController = TextEditingController();
  final _seedController = TextEditingController();
  String _scheduler = 'dpm';
  // 比例预设（Local Dream 同款快捷项；仅 SDXL 生效，SD1.5 恒为 1:1）
  String _aspectRatio = '1:1';
  static const _aspectPresets = ['1:1', '3:4', '4:3'];

  // 生成状态
  final List<Uint8List> _previewFrames = [];
  Uint8List? _resultBytes;
  int? _resultMs;
  double? _progress; // 0..1
  bool _generating = false;
  bool _showPreview = true;

  static const _schedulers = [
    ('dpm', 'DPM++'),
    ('euler', 'Euler'),
    ('euler_a', 'Euler a'),
    ('lcm', 'LCM'),
  ];

  @override
  void initState() {
    super.initState();
    _refreshChecks();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    _stepsController.dispose();
    _cfgController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _refreshChecks() async {
    final binary = await _manager.isBinaryAvailable();
    final qnn = await _manager.isQnnAssetsAvailable();
    if (!mounted) return;
    setState(() {
      _binaryAvailable = binary;
      _qnnAvailable = qnn;
      _status = _manager.status;
    });
  }

  /// 选中模型后把其默认提示词/参数填入表单（首次选中或切换模型时）。
  /// 只做字段赋值不调 setState：build 路径下本就在重建中（setState 会
  /// 触发 "during build" 断言崩溃）；onChanged 路径由外层 setState 包裹。
  void _applyModelDefaults(ImageModel model) {
    if (identical(_selectedModel, model)) return;
    _selectedModel = model;
    _promptController.text = _modelPromptPreset(model);
    _negativeController.text = model.negativePrompt;
    _stepsController.text = '${model.defaultSteps}';
    _cfgController.text = model.defaultCfg.toString();
    _seedController.clear();
    _aspectRatio = '1:1';
  }

  /// 模型条目的默认正向提示词：目录条目的 prompt 预设按包目录 id 反查
  /// （创建下载行时 description 只放来源与体积，prompt 预设留在目录里）
  String _modelPromptPreset(ImageModel model) {
    final packId = model.filePath.split(Platform.pathSeparator).last;
    final entry = localDreamPackCatalog
        .where((e) => packId.startsWith(e.id))
        .firstOrNull;
    return entry?.defaultPrompt ?? '';
  }

  Future<void> _startEngine() async {
    final model = _selectedModel;
    final type = model == null
        ? null
        : LocalDreamPackType.parse(model.remoteModelId);
    if (model == null || type == null) {
      ToastUtils.showError('请先选择一个已就绪的本机模型包', context: context);
      return;
    }
    setState(() => _starting = true);
    try {
      await _manager.ensureStarted(type: type, modelDir: model.filePath);
      if (!mounted) return;
      ToastUtils.showSuccess('引擎已就绪', context: context);
      setState(() => _status = _manager.status);
    } on LocalDreamEngineException catch (e) {
      if (mounted) ToastUtils.showError(e.message, context: context);
    } on ProcessException catch (e) {
      // Process.start 层面的失败（exec 权限/ABI 不符等）
      if (mounted) {
        ToastUtils.showError('引擎进程启动失败：${e.message}', context: context);
      }
    } catch (e) {
      // 兜底：任何启动异常都给用户反馈，不让异步错误逃逸
      if (mounted) ToastUtils.showError('启动失败：$e', context: context);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopEngine() async {
    setState(() => _stopping = true);
    try {
      await _manager.stop();
    } finally {
      if (mounted) {
        setState(() {
          _stopping = false;
          _status = _manager.status;
        });
      }
    }
  }

  /// 测试生成（Local Dream 生成页同款流程：逐步预览 + 完成图 + 耗时）
  Future<void> _runTestGeneration() async {
    if (_generating) return;
    final model = _selectedModel;
    final type =
        model == null ? null : LocalDreamPackType.parse(model.remoteModelId);
    if (model == null || type == null) {
      ToastUtils.showError('请先选择模型包并启动引擎', context: context);
      return;
    }
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ToastUtils.showError('请输入提示词', context: context);
      return;
    }
    setState(() {
      _generating = true;
      _progress = null;
      _resultBytes = null;
      _resultMs = null;
      _previewFrames.clear();
    });
    final client = LocalDreamClient(host: '127.0.0.1');
    try {
      await _manager.ensureStarted(type: type, modelDir: model.filePath);
      setState(() => _status = _manager.status);

      final size = type.generationSize;
      final sw = Stopwatch()..start();
      // 标签循环：页面销毁时 break 退出 await for 会取消 SSE 订阅，
      // 防后台流继续跑（switch 内裸 break 只跳出 switch，故用标签）
      sseLoop:
      await for (final event in client.generate(LocalDreamGenerateRequest(
        prompt: prompt,
        negativePrompt: _negativeController.text.trim(),
        steps: int.tryParse(_stepsController.text.trim()) ?? 20,
        cfg: double.tryParse(_cfgController.text.trim()) ?? 7.0,
        seed: int.tryParse(_seedController.text.trim()),
        scheduler: _scheduler,
        aspectRatio: _aspectRatio,
        width: size,
        height: size,
        showDiffusionProcess: _showPreview,
      ))) {
        switch (event) {
          case LocalDreamProgressEvent(
              :final step,
              :final totalSteps,
              :final previewBytes,
            ):
            if (!mounted) break sseLoop;
            setState(() {
              if (totalSteps > 0) {
                _progress = (step / totalSteps).clamp(0.0, 1.0);
              }
              if (previewBytes != null) {
                _previewFrames.add(previewBytes);
                if (_previewFrames.length > 8) {
                  _previewFrames.removeAt(0); // 只留最近几帧，控内存
                }
              }
            });
          case LocalDreamCompleteEvent complete:
            sw.stop();
            if (mounted) {
              setState(() {
                _resultBytes = complete.bytes;
                _resultMs = sw.elapsedMilliseconds;
                _progress = 1.0;
              });
            }
          case LocalDreamErrorEvent(:final message):
            if (mounted) ToastUtils.showError('生成失败：$message', context: context);
        }
      }
    } on LocalDreamEngineException catch (e) {
      if (mounted) ToastUtils.showError(e.message, context: context);
    } on LocalDreamException catch (e) {
      // client.generate 的连接拒绝 / SSE 中断 / HTTP 非 200 都归这里
      if (mounted) ToastUtils.showError('生成失败：${e.message}', context: context);
    } catch (e) {
      // 兜底：不让异常逃逸成未处理异步错误（用户点"生成"无反馈）
      if (mounted) ToastUtils.showError('生成失败：$e', context: context);
    } finally {
      client.close();
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readyModels = ref
            .watch(_readyEmbeddedModelsProvider)
            .valueOrNull ??
        const <ImageModel>[];
    if (readyModels.isNotEmpty) {
      // 保持选中项有效；无效时切到第一个
      final current =
          readyModels.where((m) => identical(m, _selectedModel)).firstOrNull ??
              readyModels
                  .where((m) => m.id == _selectedModel?.id)
                  .firstOrNull;
      _applyModelDefaults(current ?? readyModels.first);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Local Dream 引擎（Beta）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(),
          const SizedBox(height: 12),
          if (readyModels.isNotEmpty) ...[
            _modelSelectCard(readyModels),
            const SizedBox(height: 12),
            _generationCard(),
            const SizedBox(height: 12),
          ],
          _deviceCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statusCard() {
    Widget row(String label, bool? ok, String okText, String badText) => Row(
          children: [
            Icon(
              ok == null
                  ? Icons.hourglass_empty
                  : ok
                      ? Icons.check_circle
                      : Icons.cancel,
              size: 18,
              color: ok == null
                  ? null
                  : ok
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(ok == null ? '检查中' : (ok ? okText : badText),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        );

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Text('引擎状态', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _refreshChecks,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          row('引擎二进制（libstable_diffusion_core.so）', _binaryAvailable,
              '已打包', '未打包'),
          const SizedBox(height: 6),
          row('QNN 运行库', _qnnAvailable, '已打包', '未打包'),
          if (_status.running) ...[
            const SizedBox(height: 6),
            row('引擎进程', true, '运行中 (pid ${_status.pid})', ''),
            const SizedBox(height: 4),
            Text('已加载：${_status.type?.label ?? '-'}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_binaryAvailable == false) ...[
            const SizedBox(height: 8),
            Text(
              '引擎未打包：请按 docs/local_dream_engine.md 将 '
              'libstable_diffusion_core.so 放入 jniLibs，'
              'QNN 运行库放入 assets/local_dream/qnnlibs 后重新构建。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _starting ? null : _startEngine,
                  icon: _starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow, size: 18),
                  label: Text(_starting ? '启动中（加载模型）' : '启动引擎'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      !_status.running || _stopping ? null : _stopEngine,
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text(_stopping ? '停止中' : '停止'),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _modelSelectCard(List<ImageModel> models) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('模型包', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<ImageModel>(
            initialValue: _selectedModel,
            items: models
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text('${m.name}（${_typeLabel(m)}）',
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (m) {
              if (m != null) setState(() => _applyModelDefaults(m));
            },
            decoration: const InputDecoration(
              labelText: '选择模型包',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _generationCard() {
    final type = LocalDreamPackType.parse(_selectedModel!.remoteModelId);
    final size = type?.generationSize ?? 512;
    final isSdxl = type == LocalDreamPackType.sdxl;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Text('测试生图', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    const Text('逐步预览'),
                    Switch(
                      value: _showPreview,
                      onChanged: _generating
                          ? null
                          : (v) => setState(() => _showPreview = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          TextField(
            controller: _promptController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '提示词',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _negativeController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '负向提示词',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _numField(_stepsController, '步数', flex: 3),
              const SizedBox(width: 8),
              _cfgField(flex: 3),
              const SizedBox(width: 8),
              _numField(_seedController, 'Seed（可空）', flex: 4),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _scheduler,
                  decoration: const InputDecoration(
                    labelText: '调度器',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _schedulers
                      .map((s) =>
                          DropdownMenuItem(value: s.$1, child: Text(s.$2)))
                      .toList(),
                  onChanged: (v) => setState(() => _scheduler = v ?? 'dpm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: isSdxl
                    ? DropdownButtonFormField<String>(
                        initialValue: _aspectRatio,
                        decoration: const InputDecoration(
                          labelText: '比例',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _aspectPresets
                            .map((r) => DropdownMenuItem(
                                value: r, child: Text(r)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _aspectRatio = v ?? '1:1'),
                      )
                    : InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '画布',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Text('$size × $size（固定）',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _generating ? null : _runTestGeneration,
              icon: const Icon(Icons.image_outlined),
              label: Text(_generating ? '生成中…' : '生成'),
            ),
          ),
          if (_generating && _progress != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _progress!.clamp(0.0, 1.0)),
            const SizedBox(height: 4),
            Text('采样进度 ${(_progress! * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_previewFrames.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('逐步预览（最近一帧）',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _previewFrames.last,
                fit: BoxFit.contain,
                gaplessPlayback: true, // 帧切换不闪
              ),
            ),
          ],
          if (_resultBytes != null) ...[
            const SizedBox(height: 10),
            Text('完成', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_resultBytes!, fit: BoxFit.contain),
            ),
            const SizedBox(height: 4),
            Text('总耗时 $_resultMs ms（含图片传输）',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }

  Widget _numField(
    TextEditingController controller,
    String label, {
    required int flex,
  }) {
    return Expanded(
      flex: flex,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _cfgField({required int flex}) {
    return Expanded(
      flex: flex,
      child: TextField(
        controller: _cfgController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        decoration: const InputDecoration(
          labelText: 'CFG',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _deviceCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: FutureBuilder<AndroidDeviceInfo>(
          future: DeviceInfoPlugin().androidInfo,
          builder: (context, snap) {
            final info = snap.data;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('设备信息', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    info == null
                        ? '读取中…'
                        : '${info.manufacturer} ${info.model}\n'
                            'SoC: ${info.data['socModel'] ?? '未知（API < 31）'}\n'
                            'Android ${info.version.release}'
                            '（SDK ${info.version.sdkInt}）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'NPU 要求：SD1.5 需骁龙 Hexagon V68+；'
                    'SDXL 需骁龙 8 Gen 3+。不满足时可用 sd15cpu 包兜底。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ]);
          },
        ),
      ),
    );
  }

  String _typeLabel(ImageModel model) =>
      LocalDreamPackType.parse(model.remoteModelId)?.label ??
      (model.remoteModelId.isEmpty ? '未知类型' : model.remoteModelId);
}

/// 已就绪（status=ready）的本机引擎模型包
final _readyEmbeddedModelsProvider =
    FutureProvider<List<ImageModel>>((ref) async {
  final repo = ref.watch(imageModelRepositoryProvider);
  final all = await repo.getAll();
  return all
      .where((m) =>
          m.backendType == ImageModelBackendType.localDreamEmbedded &&
          m.status.isReady)
      .toList();
});

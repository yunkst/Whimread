/// 生图测试弹层（模型管理页「测试生图」入口）
///
/// 走 [ImageGenerationService] 门面同步生成（与 Agent 出图同链路）：
/// - 引擎按需自动启动（首次含模型加载，可能数十秒），采样进度经
///   onProgress 透传渲染进度条
/// - 步数 / CFG / 种子 / 负向提示词可在面板上调整（留空 = 模型预设）
/// - 结果是已登记的 mediaId，固定高度预览 + 点击全屏查看
/// - 失败（缺 QNN 运行库/包缺文件/引擎未打包）展示结构化错误文案
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/image_model.dart';
import '../../../services/image_generation/image_generation_providers.dart';
import '../../../services/local_dream_embedded/model_pack.dart';
import '../../../services/logger_service.dart';
import '../../../widgets/media/media_view.dart';

class ImageGenTestSheet extends ConsumerStatefulWidget {
  final ImageModel model;

  const ImageGenTestSheet({super.key, required this.model});

  /// 打开测试弹层
  static Future<void> show(BuildContext context, ImageModel model) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ImageGenTestSheet(model: model),
    );
  }

  @override
  ConsumerState<ImageGenTestSheet> createState() => _ImageGenTestSheetState();
}

class _ImageGenTestSheetState extends ConsumerState<ImageGenTestSheet> {
  final TextEditingController _promptController = TextEditingController();
  late final TextEditingController _negativeController =
      TextEditingController(text: widget.model.negativePrompt);
  final TextEditingController _seedController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 采样步数与 CFG：默认取模型预设（包内 config.json 合并值），可调
  late int _steps = widget.model.defaultSteps;
  late double _cfg = widget.model.defaultCfg;

  bool _generating = false;
  double? _progress; // 0..1 采样进度
  String? _elapsedLabel;
  String? _errorText;
  String? _resultMediaId;

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    _seedController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int? get _seed {
    final text = _seedController.text.trim();
    if (text.isEmpty) return null; // 留空 = 随机
    return int.tryParse(text);
  }

  Future<void> _generate() async {
    if (_generating) return;
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _errorText = '请输入提示词（建议英文）');
      return;
    }
    setState(() {
      _generating = true;
      _progress = null;
      _elapsedLabel = null;
      _errorText = null;
      _resultMediaId = null;
    });

    final sw = Stopwatch()..start();
    final outcome =
        await ref.read(imageGenerationServiceProvider).generate(
              modelName: widget.model.name,
              prompt: prompt,
              negativePrompt:
                  _negativeController.text.trim().isEmpty
                      ? null
                      : _negativeController.text.trim(),
              steps: _steps,
              cfg: _cfg,
              seed: _seed,
              onProgress: (step, total) {
                if (!mounted || total <= 0) return;
                setState(() => _progress = (step / total).clamp(0.0, 1.0));
              },
            );
    sw.stop();
    if (!mounted) return;
    if (!outcome.ok) {
      // 手动测试失败只在 UI 显示一句话，日志无痕迹——反馈上来没法查
      // （engine_not_ready / generation_failed 的根因全在 message 里）
      LoggerService.instance.w(
        '生图测试失败：model=${widget.model.name}，'
        'error=${outcome.errorJson?['error']}，'
        'message=${outcome.errorJson?['message']}，'
        '耗时=${sw.elapsedMilliseconds}ms',
        category: LogCategory.ai,
        tags: const ['image', 'generate', 'manual-failed'],
      );
    }
    setState(() {
      _generating = false;
      _elapsedLabel =
          '耗时 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
      if (outcome.ok) {
        _resultMediaId = outcome.result!.mediaIds.firstOrNull;
        _progress = 1.0;
      } else {
        _errorText = outcome.errorJson?['message']?.toString() ?? '生成失败';
      }
    });
    // 结果在弹层下方，生成完成后滚过去让它立即可见
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// 打开全屏查看
  void _openFullscreen() {
    final mediaId = _resultMediaId;
    if (mediaId == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(
            child: MediaView(mediaId: mediaId, fullscreen: true),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = LocalDreamPackType.parse(widget.model.remoteModelId);
    final size = type?.generationSize ?? 512;
    // 生效比例：模型预设（SDXL 生效；空 = 1:1）
    final ratio = widget.model.defaultAspectRatio.isEmpty
        ? '1:1'
        : widget.model.defaultAspectRatio;
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('测试生图',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              '${widget.model.name} · ${type?.label ?? '未知类型'} · '
              '画布 $size×$size · 比例 $ratio',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _promptController,
              maxLines: 3,
              enabled: !_generating,
              decoration: const InputDecoration(
                labelText: '提示词',
                hintText: '如：1girl, solo, ancient chinese style',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _negativeController,
              maxLines: 2,
              enabled: !_generating,
              decoration: const InputDecoration(
                labelText: '负向提示词（可留空）',
                hintText: '如：lowres, bad anatomy',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            // ===== 出图参数 =====
            _paramRow(
              label: '步数',
              valueLabel: '$_steps',
              child: Slider(
                value: _steps.toDouble(),
                min: 1,
                max: 50,
                divisions: 49,
                label: '$_steps',
                onChanged: _generating
                    ? null
                    : (v) => setState(() => _steps = v.round()),
              ),
            ),
            _paramRow(
              label: 'CFG',
              valueLabel: _cfg.toStringAsFixed(1),
              child: Slider(
                value: _cfg,
                min: 1,
                max: 12,
                divisions: 44,
                label: _cfg.toStringAsFixed(1),
                onChanged: _generating
                    ? null
                    : (v) => setState(() => _cfg = v),
              ),
            ),
            TextField(
              controller: _seedController,
              enabled: !_generating,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '种子（留空 = 随机）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            if (_generating) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                _progress == null
                    ? '正在启动引擎并生成（首次加载模型较慢）…'
                    : '采样进度 ${(_progress! * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall,
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.image_outlined),
                label: const Text('生成'),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(_errorText!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            if (_resultMediaId != null) ...[
              const SizedBox(height: 12),
              // 固定高度预览：滚到即可见，点击全屏查看原图
              GestureDetector(
                onTap: _openFullscreen,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: screenHeight * 0.45,
                    width: double.infinity,
                    child: MediaView(mediaId: _resultMediaId!),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '生成完成 · ${_elapsedLabel ?? ''} · 点击图片全屏查看'
                '（图片已保存，可在缓存管理中删除）',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paramRow({
    required String label,
    required String valueLabel,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
            width: 44,
            child: Text(label,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.right)),
        Expanded(child: child),
        SizedBox(
            width: 52,
            child: Text(valueLabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600))),
      ],
    );
  }
}

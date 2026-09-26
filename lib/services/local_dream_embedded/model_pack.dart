/// Local Dream 嵌入式引擎模型包
///
/// 引擎按 `--type <t> --model_dir <dir>` 加载一个"模型包目录"，
/// 目录内是 Local Dream 转换产物（.mnn/.bin/tokenizer.json）。
///
/// 模型目录**逐条移植自 Local Dream `ModelRepository.kt`（v2.8.1）**：
/// 预转换 ZIP 包托管在 HuggingFace（xororz/sd-qnn / sdxl-qnn / sd-mnn），
/// 下载解压即用，无需 App 内转换。NPU 包的 zip 按 SoC 芯片后缀区分
/// （8gen1/8gen2/min），SDXL 四款仅 8 Gen 3+ SoC 可见——判定逻辑与
/// Local Dream 完全一致。
///
/// anima 类型与 upscaler 模式本期不支持。
library;

import 'dart:io';

/// 引擎模型包类型（值即引擎 `--type` 参数字面量）
enum LocalDreamPackType {
  /// MNN CPU 推理（无 NPU 机型兜底）
  sd15Cpu,

  /// 骁龙 NPU（Hexagon V68+）SD1.5
  sd15Npu,

  /// 骁龙 8 Gen 3+ NPU SDXL（固定 1024 画布）
  sdxl;

  /// 引擎 `--type` 参数值 / 持久化字面量
  String get dbName {
    switch (this) {
      case LocalDreamPackType.sd15Cpu:
        return 'sd15cpu';
      case LocalDreamPackType.sd15Npu:
        return 'sd15npu';
      case LocalDreamPackType.sdxl:
        return 'sdxl';
    }
  }

  String get label {
    switch (this) {
      case LocalDreamPackType.sd15Cpu:
        return 'SD1.5 CPU';
      case LocalDreamPackType.sd15Npu:
        return 'SD1.5 NPU';
      case LocalDreamPackType.sdxl:
        return 'SDXL NPU';
    }
  }

  /// 引擎生成画布（SDXL/NPU 为固定图尺寸）
  int get generationSize =>
      this == LocalDreamPackType.sdxl ? 1024 : 512;

  /// 是否需要 --lib_dir（QNN 运行库目录；sd15cpu 纯 MNN 不需要）
  bool get needsQnnLibs => this != LocalDreamPackType.sd15Cpu;

  /// 该类型必需的模型文件（相对包目录）
  List<String> get requiredFiles {
    switch (this) {
      case LocalDreamPackType.sd15Cpu:
      case LocalDreamPackType.sd15Npu:
        return const [
          'tokenizer.json',
          'clip_v2.mnn',
          'pos_emb.bin',
          'token_emb.bin',
        ];
      case LocalDreamPackType.sdxl:
        return const [
          'tokenizer.json',
          'clip.mnn',
          'pos_emb.bin',
          'token_emb.bin',
          'clip_2.mnn',
          'pos_emb_2.bin',
          'token_emb_2.bin',
          'unet.bin',
          'vae_encoder.bin',
        ];
    }
  }

  static LocalDreamPackType? parse(String? name) {
    switch (name) {
      case 'sd15cpu':
        return LocalDreamPackType.sd15Cpu;
      case 'sd15npu':
        return LocalDreamPackType.sd15Npu;
      case 'sdxl':
        return LocalDreamPackType.sdxl;
      default:
        return null;
    }
  }
}

/// 模型包目录校验/工具
class LocalDreamModelPack {
  /// 目录内缺失的必需文件列表（空 = 齐全）
  static List<String> missingFiles(String dir, LocalDreamPackType type) {
    final missing = <String>[];
    for (final name in type.requiredFiles) {
      final file = File('$dir${Platform.pathSeparator}$name');
      if (!file.existsSync()) missing.add(name);
    }
    return missing;
  }
}

/// 模型包下载 base URL（对齐 Local Dream 的双源切换：国内用镜像）
class LocalDreamBaseUrl {
  static const String huggingface = 'https://huggingface.co/';
  static const String hfMirror = 'https://hf-mirror.com/';

  static const List<(String, String)> choices = [
    (huggingface, 'HuggingFace'),
    (hfMirror, 'HF Mirror（国内镜像）'),
  ];
}

/// 内置模型目录的一条（移植自 Local Dream ModelRepository）
class LocalDreamPackEntry {
  /// Local Dream 的模型 id（= 解压后的包目录名约定）
  final String id;
  final String name;
  final LocalDreamPackType type;
  final String description;

  /// zip 在 HuggingFace 仓库内的相对路径（baseUrl + zipUri = 完整 URL；
  /// 含 `{soc}` 占位时按芯片后缀替换）
  final String zipUri;

  /// 体积展示（Local Dream 同款文案）
  final String approximateSize;
  final String defaultPrompt;
  final String defaultNegativePrompt;

  /// 是否仅 8 Gen 3+ SoC 可见（SDXL）
  final bool sdxlOnly;

  const LocalDreamPackEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.zipUri,
    required this.approximateSize,
    required this.defaultPrompt,
    required this.defaultNegativePrompt,
    this.sdxlOnly = false,
  });

  /// 解析完整下载 URL：[baseUrl] + [zipUri]，`{soc}` 占位按芯片后缀替换。
  /// SoC 无后缀（非骁龙/低端）时 NPU 包返回 null（不可下载）。
  String? resolveZipUrl({required String baseUrl, required String? socSuffix}) {
    if (type != LocalDreamPackType.sd15Cpu && socSuffix == null) return null;
    final uri = zipUri.replaceAll('{soc}', socSuffix ?? 'min');
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return '$base$uri';
  }
}

// ============ 内置目录（逐条对齐 Local Dream ModelRepository.kt v2.8.1）============

const String _commonNegative =
    'lowres, bad anatomy, bad hands, missing fingers, extra fingers, '
    'bad arms, missing legs, missing arms, poorly drawn face, bad face, '
    'fused face, cloned face, three crus, fused feet, fused thigh, '
    'extra crus, ugly fingers, horn, huge eyes, worst face, 2girl, '
    'long fingers, disconnected limbs,';

const List<LocalDreamPackEntry> localDreamPackCatalog = [
  // ===== SDXL NPU（仅 8 Gen 3+）=====
  LocalDreamPackEntry(
    id: 'illustrious_v16',
    name: 'Illustrious v16',
    type: LocalDreamPackType.sdxl,
    description: 'WAI Illustrious SDXL v16',
    zipUri: 'xororz/sdxl-qnn/resolve/main/illustrious_v16_qnn2.28_8gen3.zip',
    approximateSize: '4.2GB',
    defaultPrompt:
        '1girl, solo, blue twintails, very long hair, bangs, blue eyes, '
        'jewelry, necklace, hair bow, off-shoulder white frilled dress, '
        'bare shoulders, collarbone, underwater, floating hair, '
        'reaching towards viewer, air bubbles, blue theme, '
        'blurry foreground, masterpiece',
    defaultNegativePrompt:
        'lowres, bad anatomy, bad hands, missing fingers, extra fingers, '
        'bad arms, missing legs, missing arms, poorly drawn face, bad face, '
        'fused face, cloned face, three crus, fused feet, fused thigh, '
        'extra crus, ugly fingers, horn, realistic photo, huge eyes, '
        'worst face, 2girl, long fingers, disconnected limbs,',
    sdxlOnly: true,
  ),
  LocalDreamPackEntry(
    id: 'illustrious_v16_dmd2',
    name: 'Illustrious v16 DMD2',
    type: LocalDreamPackType.sdxl,
    description: '融合了 DMD2 LoRA',
    zipUri:
        'xororz/sdxl-qnn/resolve/main/illustrious_v16_dmd2_qnn2.28_8gen3.zip',
    approximateSize: '4.2GB',
    // 步数/CFG 由包内 config.json 提供（蒸馏模型），此处只给画面默认值
    defaultPrompt:
        '1girl, solo, blue twintails, very long hair, bangs, blue eyes, '
        'jewelry, necklace, hair bow, off-shoulder white frilled dress, '
        'bare shoulders, collarbone, underwater, floating hair, '
        'reaching towards viewer, air bubbles, blue theme, '
        'blurry foreground, masterpiece',
    defaultNegativePrompt:
        'lowres, bad anatomy, bad hands, missing fingers, extra fingers, '
        'bad arms, missing legs, missing arms, poorly drawn face, bad face, '
        'fused face, cloned face, three crus, fused feet, fused thigh, '
        'extra crus, ugly fingers, horn, realistic photo, huge eyes, '
        'worst face, 2girl, long fingers, disconnected limbs,',
    sdxlOnly: true,
  ),
  LocalDreamPackEntry(
    id: 'cyber_realistic_v10',
    name: 'CyberRealistic v10',
    type: LocalDreamPackType.sdxl,
    description: '现实场景生成模型',
    zipUri:
        'xororz/sdxl-qnn/resolve/main/cyber_realistic_v10_qnn2.28_8gen3.zip',
    approximateSize: '4.2GB',
    defaultPrompt:
        'masterpiece, best quality, a majestic cat sitting on a windowsill '
        'at sunset,',
    defaultNegativePrompt:
        'lowres, bad anatomy, bad hands, text, error, missing fingers, '
        'extra digit, fewer digits, cropped, worst quality, low quality, '
        'normal quality, jpeg artifacts, signature, watermark, username, '
        'blurry,',
    sdxlOnly: true,
  ),
  LocalDreamPackEntry(
    id: 'cyber_realistic_v10_dmd2',
    name: 'CyberRealistic v10 DMD2',
    type: LocalDreamPackType.sdxl,
    description: '融合了 DMD2 LoRA',
    zipUri:
        'xororz/sdxl-qnn/resolve/main/cyber_realistic_v10_dmd2_qnn2.28_8gen3.zip',
    approximateSize: '4.2GB',
    defaultPrompt:
        'masterpiece, best quality, a majestic cat sitting on a windowsill '
        'at sunset,',
    defaultNegativePrompt:
        'lowres, bad anatomy, bad hands, text, error, missing fingers, '
        'extra digit, fewer digits, cropped, worst quality, low quality, '
        'normal quality, jpeg artifacts, signature, watermark, username, '
        'blurry,',
    sdxlOnly: true,
  ),
  // ===== SD1.5 NPU（zip 按芯片后缀区分）=====
  LocalDreamPackEntry(
    id: 'anythingv5',
    name: 'Anything V5.0',
    type: LocalDreamPackType.sd15Npu,
    description: '动漫图像生成模型',
    zipUri: 'xororz/sd-qnn/resolve/main/AnythingV5_qnn2.28_{soc}.zip',
    approximateSize: '1.1GB',
    defaultPrompt: 'masterpiece, best quality, 1girl, solo, cute, white hair,',
    defaultNegativePrompt: _commonNegative,
  ),
  LocalDreamPackEntry(
    id: 'qteamix',
    name: 'QteaMix',
    type: LocalDreamPackType.sd15Npu,
    description: '动漫Q版风格模型',
    zipUri: 'xororz/sd-qnn/resolve/main/QteaMix_qnn2.28_{soc}.zip',
    approximateSize: '1.1GB',
    defaultPrompt: 'chibi, best quality, 1girl, solo, cute, pink hair,',
    defaultNegativePrompt: _commonNegative,
  ),
  LocalDreamPackEntry(
    id: 'cuteyukimix',
    name: 'CuteYukiMix',
    type: LocalDreamPackType.sd15Npu,
    description: '动漫特化可爱风格',
    zipUri: 'xororz/sd-qnn/resolve/main/CuteYukiMix_qnn2.28_{soc}.zip',
    approximateSize: '1.1GB',
    defaultPrompt: 'masterpiece, best quality, 1girl, solo, cute, white hair,',
    defaultNegativePrompt: _commonNegative,
  ),
  LocalDreamPackEntry(
    id: 'absolutereality',
    name: 'Absolute Reality',
    type: LocalDreamPackType.sd15Npu,
    description: '现实场景生成模型',
    zipUri: 'xororz/sd-qnn/resolve/main/AbsoluteReality_qnn2.28_{soc}.zip',
    approximateSize: '1.1GB',
    defaultPrompt:
        'masterpiece, best quality, ultra-detailed, realistic, 8k, '
        'a cat on grass,',
    defaultNegativePrompt:
        'worst quality, low quality, normal quality, poorly drawn, lowres, '
        'low resolution, signature, watermarks, ugly, out of focus, error, '
        'blurry, unclear photo, bad photo, unrealistic, semi realistic, '
        'pixelated, cartoon, anime, cgi, drawing, 2d, 3d, censored, duplicate,',
  ),
  LocalDreamPackEntry(
    id: 'chilloutmix',
    name: 'ChilloutMix',
    type: LocalDreamPackType.sd15Npu,
    description: '人物图像生成模型',
    zipUri: 'xororz/sd-qnn/resolve/main/ChilloutMix_qnn2.28_{soc}.zip',
    approximateSize: '1.1GB',
    defaultPrompt:
        'RAW photo, best quality, realistic, photo-realistic, masterpiece, '
        '1girl, upper body, facing front, portrait, white shirt',
    defaultNegativePrompt:
        'paintings, cartoon, anime, lowres, bad anatomy, bad hands, text, '
        'error, missing fingers, extra digit, cropped, worst quality, '
        'low quality, normal quality, jpeg artifacts, signature, watermark, '
        'username, skin spots, acnes, skin blemishes',
  ),
  // ===== SD1.5 CPU（MNN 兜底，无芯片后缀）=====
  LocalDreamPackEntry(
    id: 'anythingv5cpu',
    name: 'Anything V5.0',
    type: LocalDreamPackType.sd15Cpu,
    description: '动漫图像生成模型',
    zipUri: 'xororz/sd-mnn/resolve/main/AnythingV5.zip',
    approximateSize: '1.2GB',
    defaultPrompt: 'masterpiece, best quality, 1girl, solo, cute, white hair,',
    defaultNegativePrompt: _commonNegative,
  ),
  LocalDreamPackEntry(
    id: 'qteamixcpu',
    name: 'QteaMix',
    type: LocalDreamPackType.sd15Cpu,
    description: '动漫Q版风格模型',
    zipUri: 'xororz/sd-mnn/resolve/main/QteaMix.zip',
    approximateSize: '1.2GB',
    defaultPrompt: 'chibi, best quality, 1girl, solo, cute, pink hair,',
    defaultNegativePrompt: _commonNegative,
  ),
  LocalDreamPackEntry(
    id: 'cuteyukimixcpu',
    name: 'CuteYukiMix',
    type: LocalDreamPackType.sd15Cpu,
    description: '动漫特化可爱风格',
    zipUri: 'xororz/sd-mnn/resolve/main/CuteYukiMix.zip',
    approximateSize: '1.2GB',
    defaultPrompt: 'masterpiece, best quality, 1girl, solo, cute, white hair,',
    defaultNegativePrompt: _commonNegative,
  ),
  LocalDreamPackEntry(
    id: 'absoluterealitycpu',
    name: 'Absolute Reality',
    type: LocalDreamPackType.sd15Cpu,
    description: '现实场景生成模型',
    zipUri: 'xororz/sd-mnn/resolve/main/AbsoluteReality.zip',
    approximateSize: '1.2GB',
    defaultPrompt:
        'masterpiece, best quality, ultra-detailed, realistic, 8k, '
        'a cat on grass,',
    defaultNegativePrompt:
        'worst quality, low quality, normal quality, poorly drawn, lowres, '
        'low resolution, signature, watermarks, ugly, out of focus, error, '
        'blurry, unclear photo, bad photo, unrealistic, semi realistic, '
        'pixelated, cartoon, anime, cgi, drawing, 2d, 3d, censored, duplicate,',
  ),
  LocalDreamPackEntry(
    id: 'chilloutmixcpu',
    name: 'ChilloutMix',
    type: LocalDreamPackType.sd15Cpu,
    description: '人物图像生成模型',
    zipUri: 'xororz/sd-mnn/resolve/main/ChilloutMix.zip',
    approximateSize: '1.2GB',
    defaultPrompt:
        'RAW photo, best quality, realistic, photo-realistic, masterpiece, '
        '1girl, upper body, facing front, portrait, white shirt',
    defaultNegativePrompt:
        'paintings, cartoon, anime, lowres, bad anatomy, bad hands, text, '
        'error, missing fingers, extra digit, cropped, worst quality, '
        'low quality, normal quality, jpeg artifacts, signature, watermark, '
        'username, skin spots, acnes, skin blemishes',
  ),
];

/// SoC → NPU zip 芯片后缀（逐字移植 Local Dream chipsetModelSuffixes +
/// getChipsetSuffix）。null 表示无 NPU（CPU-only 机型）。
String? chipsetSuffixForSoc(String soc) {
  const suffixes = {
    'SM8475': '8gen1',
    'SM8450': '8gen1',
    'SM8550': '8gen2',
    'SM8550P': '8gen2',
    'QCS8550': '8gen2',
    'QCM8550': '8gen2',
    'SM8650': '8gen2',
    'SM8650P': '8gen2',
    'SM8750': '8gen2',
    'SM8750P': '8gen2',
    'SM8850': '8gen2',
    'SM8850P': '8gen2',
    'SM8735': '8gen2',
    'SM8845': '8gen2',
  };
  if (suffixes.containsKey(soc)) return suffixes[soc];
  if (soc.startsWith('SM')) return 'min';
  return null;
}

/// SDXL 可用 SoC 集合（Local Dream isSdxlCapableSoc）
const Set<String> sdxlCapableSocs = {
  'SM8750', 'SM8750P', 'SM8850', 'SM8850P', 'SM8845', 'SM8650',
};

/// 按当前 SoC 过滤内置目录（SDXL 仅 8 Gen 3+ 可见），顺序保持分组
List<LocalDreamPackEntry> catalogForSoc(String? soc) {
  final suffix = soc == null ? null : chipsetSuffixForSoc(soc);
  return localDreamPackCatalog.where((e) {
    if (e.sdxlOnly) return soc != null && sdxlCapableSocs.contains(soc);
    if (e.type == LocalDreamPackType.sd15Npu) return suffix != null;
    return true; // CPU 包任何设备都可用
  }).toList();
}

/// Stable Diffusion checkpoint 架构识别
///
/// 从 safetensors 的张量名集合判断模型架构（SD1.5 / SDXL / 不支持），
/// 决定转换可行性与默认出图宽高。
///
/// 识别依据（Civitai merged checkpoint 的原始 CompVis 命名）：
/// - SD1.x：UNet 前缀 `model.diffusion_model.` + 单 CLIP `cond_stage_model.`
///          + VAE `first_stage_model.`
/// - SDXL：UNet 同上 + 双 CLIP `conditioner.embedders.0.` (CLIP-ViTErgoCLIP)
///          与 `conditioner.embedders.1.` (OpenCLIP-bigG)
/// - Flux：`double_blocks.` / `single_blocks.`（DiT 结构，sd.cpp 虽有支持但
///          端侧不可行，明确拒绝）
/// - Pony/Illustrious/NoobAI 等 SDXL 衍生：张量结构与 SDXL 相同，自动覆盖
library;

/// 支持的架构
enum SdArch {
  sd15,
  sdxl,
  unsupported;

  /// 默认出图宽高（模型训练分辨率）
  int get defaultSize => this == SdArch.sdxl ? 1024 : 512;

  /// 展示名
  String get displayName {
    switch (this) {
      case SdArch.sd15:
        return 'SD 1.x';
      case SdArch.sdxl:
        return 'SDXL';
      case SdArch.unsupported:
        return '不支持';
    }
  }
}

/// 架构识别结果
class ArchDetection {
  final SdArch arch;

  /// 是否 v-prediction 模型（影响采样，阶段 B 生效；转换器只记标志）
  final bool isVPrediction;

  const ArchDetection({required this.arch, this.isVPrediction = false});

  bool get isSupported => arch != SdArch.unsupported;
}

/// 从张量名集合识别架构。
///
/// [tensorNames] 应为 safetensors header 的全部张量名。
/// 注意：v-pred 检测不在此处（张量名无可靠特征）；由转换器层读
/// safetensors.__metadata__['modelspec.predict_key'] 补充
/// （见 model_converter.dart 的 planConversion）。
ArchDetection detectArch(Iterable<String> tensorNames) {
  final names = tensorNames.toSet();

  // ---- 先判不支持的架构（避免被通用前缀误判）----
  if (names.any((n) => n.startsWith('double_blocks.') ||
      n.startsWith('single_blocks.') ||
      n.contains('transformer_blocks.') && !n.contains('diffusion_model'))) {
    return ArchDetection(arch: SdArch.unsupported);
  }
  // PixArt / Hunyuan / Qwen 等其他 DiT 的特征
  if (names.any((n) => n.contains('blocks.') && n.contains('adaln'))) {
    return ArchDetection(arch: SdArch.unsupported);
  }

  // ---- SDXL：双文本编码器 conditioner.embedders.0/1 ----
  final hasSdxlTe = names.any((n) => n.startsWith('conditioner.embedders.0.')) &&
      names.any((n) => n.startsWith('conditioner.embedders.1.'));
  final hasUnet = names.any((n) => n.startsWith('model.diffusion_model.'));
  final hasVae = names.any((n) => n.startsWith('first_stage_model.'));

  if (hasSdxlTe && hasUnet) return const ArchDetection(arch: SdArch.sdxl);

  // ---- SD1.x：单 CLIP cond_stage_model ----
  final hasSd15Te = names.any((n) => n.startsWith('cond_stage_model.'));
  if (hasUnet && hasSd15Te && hasVae) {
    return const ArchDetection(arch: SdArch.sd15);
  }

  // ---- 兜底：只有 VAE（如单独的 vae 文件）或结构不明 ----
  return ArchDetection(arch: SdArch.unsupported);
}

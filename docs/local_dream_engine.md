# Local Dream 嵌入式引擎（方案 A）

把 Local Dream 的推理引擎以"可执行子进程 + localhost HTTP"形态嵌入
Whimread，实现单机离线 NPU 生图。引擎代码/产物经 Local Dream 作者授权
（2026-09）集成，**仅限本项目许可协议约定范围内使用**。

## 架构

```
Whimread (Flutter)
  ├─ LocalDreamEngineManager          进程生命周期（启动/停止/健康轮询）
  │    └─ spawn nativeLibraryDir/libstable_diffusion_core.so
  │         args: --type <t> --model_dir <dir> --port 8081 [--lib_dir <rt>]
  ├─ LocalDreamEmbeddedBackend        ImageGenerationBackend 实现
  │    └─ LocalDreamClient(127.0.0.1) POST /generate（SSE → base64 PNG）
  └─ MediaProxy.upload                出图落库为 mediaId（上层无感）
```

与远程设备模式（local_dream 后端）共用协议客户端；区别是嵌入式没有
控制端口（/select /status 属 Local Dream App 的 Kotlin 层），换模型 =
manager 换参数重启进程。

## 构建期人工步骤（不放置则功能优雅降级为"引擎未打包"）

1. **引擎二进制**：Local Dream 仓库 `build.sh` 产物（或作者提供的
   APK 内 `libstable_diffusion_core.so`，arm64）放入
   `android/app/src/main/jniLibs/arm64-v8a/`。
   - gradle 已设 `jniLibs.useLegacyPackaging = true`：Android 10+ W^X
     禁止 exec 私有目录文件，必须由 installer 解包到 nativeLibraryDir，
     因此该二进制**不能**像 libsds.so 那样动态下载。
2. **QNN 运行库**：Local Dream `build/android/qnnlibs/` 下全部文件放入
   `assets/local_dream/qnnlibs/`。首启由 MainActivity 的
   `engine/prepareQnnLibs` 通道解压到 `filesDir/local_dream_runtime`，
   并以 `LD_LIBRARY_PATH` 传给引擎子进程。
3. **模型源 URL**：`assets/local_dream/catalog.json` 的 files[].url
   填入真实可下载源（HuggingFace 等）。URL 全空的条目在下载页显示
   为禁用态。

## 模型分发（与 Local Dream App 同款目录）

模型清单逐条移植自 Local Dream `ModelRepository.kt`（v2.8.1），全部是
**预转换 ZIP**（无需 App 内转换），托管在 HuggingFace：

- **SDXL NPU**（仅 8 Gen 3+ SoC 可见，约 4.2GB/个）：Illustrious v16、
  Illustrious v16 DMD2、CyberRealistic v10、CyberRealistic v10 DMD2
  （`xororz/sdxl-qnn`）
- **SD1.5 NPU**（约 1.1GB/个，zip 按芯片后缀 8gen1/8gen2/min 区分）：
  Anything V5、QteaMix、CuteYukiMix、Absolute Reality、ChilloutMix
  （`xororz/sd-qnn`）
- **SD1.5 CPU**（MNN 兜底，约 1.2GB/个，任意设备）：
  同名五款（`xororz/sd-mnn`）

下载流程（App 内：生图模型管理 → 下载图标）：zip 下载（.part + Range
断点续传）→ 流式解压到 `<应用文档目录>/local_dream_models/<id>/` →
NPU 类型打 `v3` 版本标记 → 读包内 `config.json` 合并默认
prompt/negative/steps/cfg（DMD2 蒸馏模型的步数在此）→ 必需文件校验 →
置 ready。支持 HF / HF Mirror（国内镜像）源切换。

芯片后缀判定与 SDXL 门控逻辑与 Local Dream 完全一致：
`SM8450/SM8475→8gen1`；`SM8550 系/SM8650 系/SM8750 系/SM8850 系/SM8735/
SM8845→8gen2`；其它 `SM*→min`；非骁龙无 NPU（仅 CPU 包）。SDXL 仅
`SM8650/SM8750/SM8750P/SM8845/SM8850/SM8850P` 可见。

包目录必需文件（校验用）：

| 类型 | 必需文件 | 说明 |
|---|---|---|
| sd15cpu | tokenizer.json, clip_v2.mnn, pos_emb.bin, token_emb.bin | MNN CPU 兜底 |
| sd15npu | 同 sd15cpu | 骁龙 Hexagon V68+ |
| sdxl | tokenizer.json, clip.mnn, pos_emb.bin, token_emb.bin, clip_2.mnn, pos_emb_2.bin, token_emb_2.bin, unet.bin, vae_encoder.bin | 骁龙 8 Gen 3+，固定 1024 画布 |

image_models 行字段复用（无迁移）：`backend_type='local_dream_embedded'`、
`file_path`=包目录、`remote_model_id`=包类型 dbName、`source_url`=zip 直链
（断点续传/重试用）。

## 入口

- 设置 → AI → **Local Dream 引擎（Beta）**：状态自检（二进制/QNN/进程）、
  启动/停止、测试生图（SSE 进度 + 耗时）、SoC 信息。
- 设置 → AI → 生图模型管理 → AppBar 下载图标：**下载模型包**（内置
  目录 / 自定义 manifest URL）与**从目录导入模型包**。

## 已知限制

- 仅 Android arm64 + 骁龙 NPU 机型收益；其他平台走 sd.cpp CPU 或远程设备。
- anima 类型与 upscaler 模式未接入；safetensors 在线转 NPU（cvtbase）未接入。
- 生成期间无前台服务保活（App 切后台过久可能被系统回收进程，重进会冷启）。
- 引擎升级可能要求重新下载模型包（格式与引擎版本耦合）。

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

协议客户端 `local_dream_client.dart` 只保留生成端口能力
（/generate SSE + /health）；换模型 = manager 换参数重启进程。

## 构建期人工步骤（不放置则功能优雅降级为"引擎未打包"）

1. **引擎二进制**（唯一需要进 APK 的产物）：Local Dream 仓库 `build.sh`
   产物（或从其 APK 提取的 `libstable_diffusion_core.so`，arm64）放入
   `android/app/src/main/jniLibs/arm64-v8a/`，**或**构建时自动下载：
   ```
   flutter build apk -PlocalDreamEngineUrl=https://<bucket>/libstable_diffusion_core.so
   ```
   - 它是被 **exec** 的可执行文件：Android 10+ W^X 禁止 exec 私有目录
     文件，必须由 installer 解包到 nativeLibraryDir——因此**不能**像
     libsds.so（dlopen 语义）那样运行时下载，这是平台硬约束。
   - gradle 已设 `useLegacyPackaging = true`（APK 内压缩存储 + 安装时
     解包，APK 体积按压缩后计）。
   - 未放置且未设置 URL 时优雅降级："引擎未打包"引导，其余功能不受影响。

## 产物获取与发布（待办操作手册）

两个产物都从**手机上已安装的 Local Dream APK** 提取（无需 root）：

```bash
# 1. 从 Local Dream APK 提取（手机插 USB + USB 调试）
adb shell pm path io.github.xororz.localdream
adb pull <上一步输出的 base.apk 路径> localdream.apk
unzip localdream.apk "lib/arm64-v8a/libstable_diffusion_core.so" "assets/qnnlibs/*" -d ld_extract

# 2. 引擎 .so 放入工程（本机构建即含引擎）
cp ld_extract/lib/arm64-v8a/libstable_diffusion_core.so   android/app/src/main/jniLibs/arm64-v8a/

# 3. 上传两个产物到资源桶
#    tcb CLI 首次使用需登录一次（浏览器授权；v2 版本凭据存 ~/.cloudbase/auth.json）：
npx -y -p @cloudbase/cli@2.12.10 tcb login
npx -y @cloudbase/cli@2.12.10 storage upload   ld_extract/lib/arm64-v8a/libstable_diffusion_core.so   app-resources/v1/local_dream_engine/libstable_diffusion_core.so   -e whimread-dev-d0gm4oi0z3099082d
for f in ld_extract/assets/qnnlibs/*.so; do
  npx -y @cloudbase/cli@2.12.10 storage upload "$f"     "app-resources/v1/local_dream_qnn/$(basename $f)"     -e whimread-dev-d0gm4oi0z3099082d
done

# 4. 重新生成并上传 manifest（工具会登记 local_dream_qnn 条目 + 引擎 URL）
dart run tool/publish_resources.dart   --sd-so <现有 libsds.so>   --qnn-dir ld_extract/assets/qnnlibs   --ld-engine-so ld_extract/lib/arm64-v8a/libstable_diffusion_core.so   --out tool/app_resources/dist
# 按 dist/UPLOAD_LIST.txt 上传（含更新后的 manifest.json）
```

完成后：构建用 `-PlocalDreamEngineUrl=<第 4 步输出的 URL>`；客户端在启动
资源引导阶段自动下载 QNN 运行库。模型源 URL：内置目录
（`lib/services/local_dream_embedded/model_pack.dart`）已指向 HuggingFace
真实源（`xororz/sd-qnn` 等作者仓库），国内可在下载页切 HF Mirror。
2. **QNN 运行库不打包**：被引擎 dlopen（不受 exec 限制），经
   `app_resource_manager` 统一 manifest（`local_dream_qnn` 条目）在启动
   资源引导阶段下载到 `dynamic_resources/local_dream_qnn/`（引擎启动只
   解析本地目录，不触发网络），sha256 校验 + 断点重试。需要往资源桶
   manifest 里发布该条目
   （文件名 = 原始 so 名，如 libQnnHtp.so）。**未发布前 sd15cpu 包
   （纯 MNN，无 QNN 依赖）可完整使用**。

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

设置 → AI → **生图模型管理（Beta）**，一页完成全部操作：
- **可下载模型包**：内置目录按设备 SoC 过滤展示，点击即下载（卡片内
  进度/失败原因/续传；AppBar 可切 HF / HF Mirror 源）；
- **我的模型**：就绪模型可直接「测试生图」（与 Agent 出图同走统一门面，
  引擎按需自动启动，采样进度条 + 耗时）；AppBar 支持从目录导入模型包；
- 引擎二进制 / QNN 运行库未就绪时页面顶部出现提示条（引擎由生成链路
  按需自动启动，无独立管理页）。

## 已知限制

- 仅 Android arm64 + 骁龙 NPU 机型收益；其他平台无本机生图能力。
- anima 类型与 upscaler 模式未接入。
- 生成期间无前台服务保活（App 切后台过久可能被系统回收进程，重进会冷启）。
- 引擎升级可能要求重新下载模型包（格式与引擎版本耦合）。

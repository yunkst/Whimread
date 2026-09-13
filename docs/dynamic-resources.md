# 动态资源（启动资源引导）

> 2026-09-13 APK 瘦身：把大体积资源从 APK 移出，改为启动时统一校验 + 下载。

## 概览

| 资源 id | 内容 | 原体积 | 托管 | 加载方式 |
|---|---|---|---|---|
| `ui_fonts` | Noto Serif/Sans SC 四个 ttf | ~38MB | 统一 manifest | `FontLoader` 运行时注册 |
| `ocr_model` | PP-OCRv6 inference.onnx + 字典 | ~21MB | 独立 manifest（沿用） | ONNX Session |
| `sd_engine` | libsds.so（arm64-v8a） | ~57MB | 统一 manifest | FFI `DynamicLibrary.open(绝对路径)` |

`libonnxruntime.so`（~19MB）**未**动态化：flutter_onnxruntime 插件在 engine
attach 期就初始化 ORT，缺失会崩，需 fork 插件懒加载，另立任务。

## 客户端链路

- 统一 manifest：`app-resources/v1/manifest.json`（CloudBase 公开读 bucket，
  与 OCR 模型同 bucket）。结构见 `lib/services/app_resource_manager.dart`。
- 启动编排：`lib/core/providers/resource_bootstrap_providers.dart`
  （`ResourceBootstrapNotifier.bootstrap()`），由 `main.dart` 的
  `_ResourceGate` 在 onboarding 完成后触发。
- UI：`lib/screens/resource_bootstrap/resource_bootstrap_screen.dart`，
  可跳过（落 `resource_bootstrap_skipped_<manifest_version>` 标记，
  后台静默补下载）；manifest 升版后标记失效、重新引导。
- 校验：所有文件下载后 sha256 与 manifest 比对 + 原子替换（`.tmp` → rename）。
- 降级：字体缺失回退 `fontFamilyFallback` 系统字体；OCR 缺失走现有
  「模型下载中」提示；libsds.so 缺失走 `engine_not_ready`。

## 发布资源（`tool/publish_resources.dart`）

```bash
# 1. 构建一次 release（CMake 产出 libsds.so 到 intermediates，APK 已排除它）
flutter build apk --release --split-per-abi

# 2. 找到 so：android/app/build/intermediates/cxx/<variant>/<hash>/obj/arm64-v8a/libsds.so
#    （find android/app/build/intermediates/cxx -name libsds.so）
# 3. 生成 manifest + 上传清单
dart run tool/publish_resources.dart \
  --sd-so android/app/build/intermediates/cxx/Debug/debug/arm64-v8a/libsds.so
# 产物: tool/app_resources/dist/manifest.json + UPLOAD_LIST.txt
# 4. 按 UPLOAD_LIST.txt 把文件上传到 bucket 对应路径（控制台或 tcb CLI），
#    manifest.json 最后传（客户端以它为准）
```

注意事项：

- 更新任何资源后**必须重传 manifest.json**，否则客户端按旧 sha256 校验失败。
- `manifest_version` 递增 = 所有用户的「跳过」标记失效，会再看到一次引导页。
- 字体源文件在 `assets/fonts/`（不再打进 APK，但保留供脚本上传）。

## 已知风险

- **targetSdk 36 下从应用可写目录 dlopen so**：官方 W^X 限制明确禁止
  `exec()`，`dlopen` 多数设备可用但存在 ROM 差异。libsds.so 有完整降级
  （`isEngineBinaryAvailable` 探测失败 → engine_not_ready），不会崩，但
  需在目标机型真机验证；若不通过，回退方案是把 libsds.so 重新打回 APK
  （删除 `android/app/build.gradle.kts` 的 packagingOptions excludes）。

# jniLibs：Local Dream 引擎产物放置目录

把 Local Dream 的引擎可执行文件放到本目录：

```
Local Dream 仓库 build.sh 产物（或作者提供的 APK 内提取）：
  libstable_diffusion_core.so   →  本目录（arm64-v8a/）
```

- 该文件是"伪装成 .so 的可执行文件"，运行时从 `nativeLibraryDir` spawn。
- gradle 已设 `jniLibs.useLegacyPackaging = true`（保证解包到磁盘，
  Android 10+ W^X 只允许 exec nativeLibraryDir 下的文件）。
- QNN 运行库放在 `assets/local_dream/qnnlibs/`（见仓库根 assets 目录），
  首启由 `LocalDreamEngineManager` 解压到应用私有目录。
- 未放置产物时 App 功能优雅降级：引擎相关入口显示"引擎未打包"引导。

授权说明：Local Dream 引擎代码/产物经作者授权集成（2026-09），仅限本
项目约定范围内使用，详见 docs/local_dream_engine.md。

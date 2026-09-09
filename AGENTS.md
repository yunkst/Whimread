# Whimread — Flutter 客户端

> AI 原生小说阅读平台「随心阅读」的 Flutter 客户端。
> 模块级详细文档见 [CLAUDE.md](CLAUDE.md)（目录结构 / Riverpod providers /
> SQLite 表 / DSL Engine / 依赖说明）。

## 技术栈

- Flutter 3.35.x（CI 锁定）/ Dart 3.x
- Riverpod（代码生成）状态管理
- SQLite（drift 前身 sqflite 体系）本地书架/章节/角色/大纲
- Headless WebView + 本地 JS 提取脚本（章节获取，支持字体反爬 OCR 还原）
- AI 托管模式：LLM 请求走打包注入的托管后端（`--dart-define=BACKEND_BASE_URL`），
  设备注册领免费额度；不注入则回退用户自配 AI 供应商模式

> 2026-09-09 起后端服务（device-auth/llm-proxy/app-release/feedback + 部署工具链）已迁至私有仓 `D:\myspace\whimread-admin`，本仓仅保留 Flutter 客户端；AI 托管模式的部署与迁移见该仓 README-cloudbase.md。

## 常用命令

```bash
flutter pub get
flutter analyze
flutter test test/unit/ test/bug/
dart run build_runner build --delete-conflicting-outputs   # Riverpod/mock 代码生成
flutter build apk --release --split-per-abi   --dart-define=BACKEND_BASE_URL=https://your-backend.example.com
```

## 目录速览

```
lib/                  # 全部业务代码
  core/               # providers / theme / database / constants
  services/           # API / novel_agent / dsl_engine / device / media …
  screens/ widgets/   # 页面与组件
  models/ repositories/
android/ ios/ web/ windows/ linux/ macos/
assets/               # 字体 / 模型 / 图片
docs/                 # 开发者文档（架构图 / 日志规范 / 计划）
tool/                 # 测试脚本 / 字体子集化
```

> 2026-09-09 起后端服务（device-auth/llm-proxy/app-release/feedback + 部署工具链）已迁至私有仓 `D:\myspace\whimread-admin`，本仓仅保留 Flutter 客户端；AI 托管模式的部署与迁移见该仓 README-cloudbase.md。

## 规则

- 提交遵循 Conventional Commits（中文描述），一仓一事一 commit
- Riverpod provider 新增后跑 build_runner，勿手改 .g.dart
- SQLite 升版必须写 database_migrations.dart 迁移 + 补测试
- UI 文案使用中文；对外品牌名 Whimread /「随心阅读」

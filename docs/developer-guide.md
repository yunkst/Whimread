# Whimread 开发者指南

本指南面向希望为 Whimread 贡献代码或自部署的开发者。涵盖项目架构、开发环境搭建、扩展开发等主题。

## 🏗️ 架构总览

Whimread 采用 monorepo 架构，包含两个主要模块：

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Flutter App   │ ←─→ │   FastAPI 后端  │ ←─→ │   PostgreSQL    │
│   (novel_app)   │     │    (backend)    │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │
        │                       ├── ComfyUI (图片/视频生成)
        │                       └── 客户端本地 AI（DSL Engine + Agent Chat）
        │
        └── SQLite 本地缓存（含 site_scripts / chapter_cache）
```

### 数据流

1. **章节获取** → Flutter App → Headless WebView + 本地 JS 提取脚本 → 写入 `chapter_cache` 表
2. **AI 功能** → Flutter App（DSL Engine 本地执行） → OpenAI 兼容 LLM API
3. **场景插图** → Flutter App → FastAPI → ComfyUI → 图片下载/缓存
4. **数据备份** → 客户端 → FastAPI `/api/backup/upload`

---

## 💻 开发环境搭建

### 前置要求

| 工具 | 版本 | 用途 |
|------|------|------|
| Flutter SDK | 3.0+ | 移动应用开发 |
| Dart SDK | 3.0+ | Flutter 依赖 |
| Python | 3.11+ | 后端开发 |
| Docker | 20.10+ | 容器化部署 |
| Docker Compose | 2.0+ | 多服务编排 |
| PostgreSQL | 15+ | 后端数据库 |
| Git | 2.30+ | 版本控制 |
| Node.js | 18+ | API 代码生成工具 |

### 克隆项目

```bash
git clone https://github.com/yunkst/novel_builder.git
cd novel_builder
git remote add upstream https://github.com/yunkst/novel_builder.git
```

### 后端开发环境

#### 方式 1：Docker Compose（推荐）

```bash
# 启动数据库和后端服务
docker-compose up -d postgres backend

# 查看日志
docker-compose logs -f backend
```

#### 方式 2：本地虚拟环境

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 安装依赖（含开发工具）
pip install -e ".[dev]"

# 启动开发服务器
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

#### 数据库迁移

```bash
cd backend
alembic upgrade head        # 应用所有迁移
alembic revision --autogenerate -m "描述"   # 生成新迁移
```

### 前端开发环境

```bash
cd novel_app
flutter pub get

# 生成 Riverpod Provider 代码
dart run build_runner build --delete-conflicting-outputs

# 运行应用（自动选择连接的设备）
flutter run

# 仅在特定平台运行
flutter run -d android
flutter run -d chrome
```

### OpenAPI 客户端代码生成

后端启动后，运行以下命令重新生成 Dart API 客户端：

```bash
cd novel_app
dart run tool/generate_api.dart
```

---

## 📁 项目结构

### 根目录

```
novel_builder/
├── novel_app/          # Flutter 移动应用
├── backend/            # Python FastAPI 后端
├── docs/               # 项目文档
├── docker-compose.yml  # Docker 编排
├── .github/            # GitHub Actions CI/CD
├── .env.example        # 环境变量模板
├── README.md           # 项目说明
├── CHANGELOG.md        # 变更日志
├── CONTRIBUTING.md     # 贡献指南
├── LICENSE             # MIT 许可证
└── CLAUDE.md           # AI 上下文文档
```

### novel_app/ 详细结构

```
novel_app/
├── lib/
│   ├── main.dart               # 应用入口
│   ├── core/                   # 核心基础设施
│   │   ├── di/                 # 依赖注入
│   │   ├── database/           # SQLite 数据库
│   │   ├── interfaces/         # 抽象接口
│   │   └── providers/          # Riverpod Provider（50+）
│   ├── controllers/            # 控制器层
│   ├── repositories/           # 数据仓库层
│   ├── services/               # 业务服务
│   │   ├── dsl_engine/         # DSL Engine 核心
│   │   ├── novel_agent/        # Agent Chat 引擎
│   │   ├── headless_webview_*.dart  # Headless WebView 提取
│   │   ├── ocr_restore_service.dart # OCR 还原（PP-OCRv6）
│   │   └── api_service_*.dart  # API 客户端
│   ├── screens/                # 页面组件
│   ├── widgets/                # 可复用组件
│   ├── dialogs/                # 对话框
│   ├── models/                 # 数据模型
│   ├── utils/                  # 工具函数
│   ├── mixins/                 # 混入类
│   ├── extensions/             # 扩展方法
│   └── generated/              # OpenAPI 自动生成代码
├── assets/
│   ├── dsl/                    # DSL 工作流定义（YAML）
│   └── images/                 # 应用图标等
├── android/                    # Android 平台
├── ios/                        # iOS 平台
├── test/                       # 测试代码
└── CLAUDE.md                   # 模块文档
```

### backend/ 详细结构

```
backend/
├── app/
│   ├── main.py                 # FastAPI 应用入口
│   ├── config.py               # 配置管理
│   ├── database.py             # 数据库连接
│   ├── exceptions.py           # 自定义异常
│   ├── logging_config.py       # 日志配置
│   ├── constants.py            # 常量定义
│   ├── api/
│   │   └── routes/             # 路由模块
│   │       ├── backup.py       # 备份 API
│   │       ├── novel_sync.py   # 小说同步
│   │       ├── text2img.py     # 文生图（ComfyUI）
│   │       ├── image_to_video.py  # 图生视频（ComfyUI）
│   │       └── logs.py         # 日志查询/上报
│   ├── deps/                   # FastAPI 依赖
│   ├── models/                 # SQLAlchemy 模型
│   ├── schemas/                # Pydantic 模式
│   └── services/               # 业务服务
│       ├── comfyui_*.py        # ComfyUI 客户端
│       ├── backup_*.py         # 备份/恢复
│       └── *.py                # 其他服务
├── alembic/                    # 数据库迁移
├── tests/                      # 测试
└── CLAUDE.md                   # 模块文档
```

---

## 🎨 前端架构

### 状态管理：Riverpod

Novel App 完全采用 [Riverpod](https://riverpod.dev/) 进行状态管理：

```dart
// Service Provider 示例
@Riverpod(keepAlive: true)
ApiServiceWrapper apiServiceWrapper(Ref ref) {
  return ApiServiceWrapper();
}

// State Notifier Provider 示例
@riverpod
class BookshelfState extends _$BookshelfState {
  @override
  Future<List<Bookshelf>> build() async {
    final repo = ref.watch(bookshelfRepositoryProvider);
    return repo.getAll();
  }
}
```

**Provider 分类**：
- **Service Providers** (20+) - 服务层单例
- **Repository Providers** - 数据仓库
- **StateNotifierProviders** (30+) - 业务状态
- **FutureProvider / StreamProvider** - 异步数据流

### Repository 模式

所有数据访问通过 Repository 层：

```dart
class BookshelfRepository extends BaseRepository {
  Future<List<Bookshelf>> getAll();
  Future<void> add(Bookshelf bookshelf);
  Future<void> delete(int id);
}
```

### API 客户端

使用 OpenAPI 自动生成的 Dart 客户端，通过 Riverpod Provider 注入：

```dart
@riverpod
Future<List<Novel>> searchNovels(
  Ref ref,
  String keyword,
  List<String> sites,
) async {
  final api = ref.watch(apiServiceWrapperProvider);
  return api.search(keyword: keyword, sites: sites);
}
```

---

## 🌐 后端架构

### 章节提取（前端本地完成）

Whimread 不再依赖服务端爬虫：章节列表与正文由 **Flutter 端 Headless WebView + 本地 JS 提取脚本**（`lib/services/headless_webview_*.dart` + `site_scripts` 表）直接获取；对字体反爬站点（如番茄）走 OCR 还原（`OcrRestoreService` + 系统 OCR-JS 模板，PP-OCRv6）。

- 客户端实现：见 [lib/services/headless_webview_*.dart](../novel_app/lib/services/)
- 站点脚本：`site_scripts` 表（v39，含 `chapter_list_ocr` / `chapter_content_ocr` 独立列）

### 缓存

仅客户端本地缓存（`chapter_cache` 表），服务端 PostgreSQL 不再缓存章节内容（2026-07-08 已删 `novel_cache_tasks` / `novel_chapters_cache` / `chapter_list_cache` 三表）。

### AI 服务集成

#### ComfyUI 客户端

```python
from app.services.comfyui_client import ComfyUIClient

client = ComfyUIClient(base_url="http://localhost:8188")
result = await client.text_to_image(
    prompt="a beautiful landscape",
    negative_prompt="low quality",
    width=1024,
    height=1024,
)
```

---

## 🤖 AI 功能架构

### DSL Engine（前端本地执行）

Novel App 内置客户端 DSL 工作流引擎（**与 Dify 解耦**，本地 YAML 解析），无需后端协作即可执行 AI 工作流。

**核心组件**：

```
lib/services/dsl_engine/
├── dsl_parser.dart          # YAML DSL 解析
├── graph_engine.dart        # 工作流图执行
├── variable_pool.dart       # 变量管理
├── llm_provider.dart        # LLM 调用
├── dsl_executor.dart        # 统一执行入口
├── dsl_engine_config.dart   # 配置管理
└── workflow_nodes/          # 工作流节点类型
```

**使用示例**：

```dart
final executor = DslExecutor(
  llmConfig: LlmConfig(
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'sk-xxx',
  ),
  defaultModel: 'deepseek-chat',
);

// Streaming 执行
await executor.runStreaming(
  inputs: {'chapter_content': '...'},
  onData: (chunk) => print(chunk),
  onError: (e) => print(e),
  onDone: () => print('完成'),
);
```

**DSL 工作流定义**（`assets/dsl/creater.yml`）：

```yaml
app:
  name: 角色提取
  description: 从小说章节提取角色信息
workflow:
  graph:
    nodes:
      - id: start
        type: start
      - id: extract
        type: llm
        prompt: |
          从以下小说内容中提取角色信息：
          {{chapter_content}}
        model: deepseek-chat
      - id: end
        type: end
    edges:
      - from: start
        to: extract
      - from: extract
        to: end
```

---

## 🗄️ 数据库

### 前端：SQLite

- 数据库文件：`novel_reader.db`
- 版本：v39
- 主要表：bookshelf, chapter_cache, novel_chapters, characters, character_relationships, scene_illustrations, outlines, chat_sessions, chat_scenes, site_scripts, llm_configs, agent_memories
- 通过 Riverpod Provider 访问

### 后端：PostgreSQL

- ORM：SQLAlchemy 2.0+
- 迁移工具：Alembic（head: `20260708_drop_cache_tables`）
- 主要表：text2img_task, image_to_video_task, client_logs, backup_files, novel_sync_data
- 注：缓存类表（`novel_cache_tasks` / `novel_chapters_cache` / `chapter_list_cache`）已于 2026-07-08 删除

---

## 🕷️ 添加新站点提取脚本

Whimread 已不使用服务端爬虫。要支持新站点，**在前端编写 site_script**：

### 步骤 1：在 APP 内通过 Agent Chat 引导创建

1. 打开 APP → Agent Chat
2. 让 Agent 访问目标站点，自动生成 chapter_list / chapter_content 提取脚本
3. Agent 通过 `save_script` 工具落库到 `site_scripts` 表

### 步骤 2：手工编辑（可选）

直接编辑 `site_scripts` 表中对应行的 `chapter_list_script` / `chapter_content_script`（JS 字符串）。

### 步骤 3：OCR 还原（字体反爬站点）

对 PUA 字体反爬站点（如番茄），在 `site_scripts` 表将 `chapter_list_ocr` / `chapter_content_ocr` 置为 1，并创建对应 OCR 提取器（详见根 CLAUDE.md 2026-07-15 OCR 条目）。

### 步骤 4：测试

在 Agent Chat 中调用 `read_chapter_content` / `list_chapters` 工具验证提取结果。

---

## 🔄 数据库变更

### 前端 SQLite

数据库版本由 `lib/core/database/database_version.dart` 管理。修改表结构时：

1. 更新 Bump DB version
2. 实现 `onUpgrade` 迁移逻辑
3. 运行测试验证

### 后端 PostgreSQL

```bash
cd backend

# 修改 SQLAlchemy 模型
# app/models/your_model.py

# 生成迁移
alembic revision --autogenerate -m "添加新字段"

# 检查生成的迁移文件
# alembic/versions/xxxx_add_new_field.py

# 应用迁移
alembic upgrade head

# 回滚（如果需要）
alembic downgrade -1
```

---

## 🧪 代码质量

### Python 后端

```bash
cd backend

# 静态检查
ruff check .
pylint app/
mypy app/

# 格式化
ruff format .
isort .

# 测试
pytest                          # 全部测试
pytest tests/unit/              # 单元测试
pytest -k "test_crawler"        # 匹配名称
pytest --cov=app tests/         # 覆盖率
```

### Flutter 前端

```bash
cd novel_app

# 静态分析
flutter analyze

# 格式化
flutter format lib/

# 代码生成
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs   # 监听模式

# 测试
flutter test                    # 全部测试
flutter test test/unit/         # 单元测试
flutter test --coverage         # 覆盖率
```

### 提交前检查

建议在提交前运行：

```bash
# 后端
cd backend && ruff check . && mypy app/

# 前端
cd novel_app && flutter analyze && flutter test
```

---

## 🚀 CI/CD

项目使用 GitHub Actions 自动化测试和发布。

### Workflow 文件

- `.github/workflows/flutter-ci.yml` - PR/Push 到 main 时运行 CI
- `.github/workflows/flutter-release.yml` - 推送 tag 时构建并发布 APK

### CI 流程（PR/Push）

1. 检出代码
2. 安装 Flutter SDK
3. 安装依赖（`flutter pub get`）
4. 生成 Riverpod 代码
5. 静态分析（`flutter analyze`）
6. 运行单元测试（`flutter test`）

### Release 流程（tag push）

1. 检出代码
2. 安装 Flutter SDK
3. 安装依赖
4. 生成代码
5. 构建 Release APK
6. 上传到 GitHub Releases

### 创建新版本

```bash
# 1. 更新 pubspec.yaml
# version: 1.7.6+55

# 2. 提交
git add novel_app/pubspec.yaml
git commit -m "chore: 发布版本 1.7.6"

# 3. 创建 tag
git tag v1.7.6
git push origin master --tags

# 4. GitHub Actions 自动构建并发布
```

---

## 🔐 环境变量

完整环境变量参考 `.env.example`。核心变量（v2.0.x）：

| 变量名 | 必需 | 用途 |
|--------|------|------|
| `NOVEL_API_TOKEN` | ✅ | API 认证 Token（X-API-TOKEN） |
| `DATABASE_URL` | ✅ | PostgreSQL 连接字符串 |
| `COMFYUI_API_URL` | ⚠️ | ComfyUI 服务（文生图/图生视频） |
| `DEBUG` | ❌ | 调试模式 |
| `CORS_ORIGINS` | ❌ | CORS 允许的源 |
| `HTTP_PROXY` / `HTTPS_PROXY` | ❌ | 网络代理 |

> 注：早期文档提到的 `NOVEL_ENABLED_SITES` / `SECRET_KEY` / `LOG_LEVEL` / `MAX_UPLOAD_SIZE` / `UPLOAD_DIR` / `VIDEO_GENERATION_TIMEOUT` / `HOST` / `PORT` 字段已在 v2.0.x 移除（爬虫功能 2026-07-08 整体下线）。

---

## 📚 更多资源

- **项目主页** - https://github.com/yunkst/novel_builder
- **API 文档** - http://localhost:3800/docs
- **后端模块文档** - [backend/CLAUDE.md](../backend/CLAUDE.md)
- **前端模块文档** - [novel_app/CLAUDE.md](../novel_app/CLAUDE.md)
- **部署指南** - [deployment.md](deployment.md)
- **日志使用指南** - [logging-guidelines.md](logging-guidelines.md)

---

## 🤝 贡献流程

1. **创建分支** - `git checkout -b feature/your-feature`
2. **编写代码** - 遵循代码规范
3. **添加测试** - 确保新功能有测试覆盖
4. **本地验证** - 运行 `flutter analyze` 和 `flutter test`
5. **提交** - 遵循 Conventional Commits
6. **推送并创建 PR** - 详细描述变更内容
7. **代码审查** - 等待维护者审查
8. **合并** - 通过 CI 后合并到 master

详细请参考 [贡献指南](../CONTRIBUTING.md)。

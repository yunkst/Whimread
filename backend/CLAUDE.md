[根目录](../../CLAUDE.md) > **backend**

# Python 后端 API 模块

## 变更记录 (Changelog)

- **2025-11-13**: 模块文档初始化
- **2026-06-11**: 更新为 Scrapling 爬虫引擎，扩展站点，添加 ComfyUI 客户端
- **2026-07-08**: **移除搜索与多站点爬虫功能**。前端已改用 headless WebView + 本地 JS 提取脚本获取章节内容、本地书架搜索，后端爬虫/搜索/章节缓存成为死代码，全部删除。后端现仅保留 AI 文生图/图生视频、数据库备份、模型管理、客户端日志上报。数据库新增 `20260708_drop_cache_tables` 迁移 drop 三张缓存表。

## 模块职责

Python 后端是 Whimread 平台的 AI 与配套服务，提供 FastAPI 驱动的：

- ComfyUI 文生图 / 图生视频任务提交与结果轮询
- ComfyUI 工作流与可用模型列表管理
- ComfyUI 模型文件分块上传
- 客户端数据库备份文件上传 / 列表 / 下载
- 客户端日志上报与持久化
- 统一 RESTful API 接口 + Token 鉴权

> 注：**搜索、多站点爬虫、章节缓存已移除**。章节内容由前端 `headless_webview_content_service.dart` + 本地 `chapter_content_js` 提取脚本获取；搜索为前端本地书架搜索。

## 入口与启动

- **主入口**: `app/main.py`
- **应用类**: `FastAPI`
- **版本**: 0.2.0（FastAPI 实例；详见§版本号不一致说明）
- **端口**: 8000（Docker 映射 3800）

> **版本号不一致说明**（scope 之外，待后续 PR）：仓库存在三处 Python 版本号，分别为 `pyproject.toml` 的 `0.1.0` / `app/main.py` 的 FastAPI `version="0.2.0"` / `app/__init__.py` 的 `__version__="1.0.0"`。本模块文档以 FastAPI 实例 `0.2.0` 为基准；建议统一到单一来源（如 `app.__version__` 单点 + hatch dynamic version）。

### 启动流程

1. FastAPI 实例创建 + CORS 中间件
2. 数据库初始化（SQLAlchemy + Alembic）
3. 文生图 / 图生视频服务实例化
4. 注册路由：`backup`、`logs`、`models` + main.py 内联的 text2img / image-to-video / models 路由
5. 健康检查

## 对外接口

### AI 接口

- `POST /api/text2img/generate` - 提交文生图任务（支持 `negative_prompt`），返回 `task_id`
- `GET /api/text2img/image/{task_id}` - 取文生图结果（202 pending / 200 png / 404 失败）
- `GET /text2img/health` - ComfyUI 服务健康检查
- `POST /api/image-to-video/generate` - 上传图片 + 提示词，提交图生视频任务，返回 `task_id`
- `GET /api/image-to-video/video/{task_id}` - 取视频结果（202 pending / 200 mp4 / 404 失败）
- `GET /api/models` - 可用文生图 / 图生视频工作流列表

### 备份接口（`app/api/routes/backup.py`）

- `POST /api/backup/upload` - 上传 `.db` 备份文件
- `GET /api/backup/list` - 列出已上传备份
- `GET /api/backup/download/{backup_id}` - 下载备份

### 日志接口（`app/api/routes/logs.py`）

- `POST /api/logs/upload` - 上报客户端日志（1-50 条/次）

### 模型文件分块上传（`app/api/routes/models.py`）

- ComfyUI 模型目录浏览 + 分块上传（init / chunk / status / complete）

### 其他

- `GET /health` - 健康检查
- `GET /security-check` - 安全配置检查（仅 DEBUG）
- `GET /` - 服务信息与端点清单

> **已移除**：`/api/app-version/*` 版本管理已迁移到 GitHub Releases（前端 `github_release_service.dart` 直接调 GitHub API），后端相关路由与 schema 已于 2026-07-08 删除。

## 关键依赖与配置

### 项目配置

- 配置文件: `pyproject.toml`
- Python: >=3.11
- 构建系统: Hatchling

### 核心依赖

```python
dependencies = [
    "fastapi>=0.104.0",
    "uvicorn[standard]>=0.24.0",
    "requests>=2.31.0",
    "pydantic>=2.4.0",
    "pydantic-settings>=2.0.0",
    "python-multipart>=0.0.6",
    "sqlalchemy>=2.0.0",
    "psycopg2-binary>=2.9.0",
    "alembic>=1.12.0",
    "packaging>=23.0.0",
]
```

> Scrapling / Playwright / OpenCC / urllib3 / aiofiles 等爬虫专用依赖已随功能移除。

### 环境变量

- `NOVEL_API_TOKEN`: API 访问令牌
- `SECRET_KEY`: 应用密钥
- `DATABASE_URL`: 数据库连接串（默认 SQLite，生产 PostgreSQL）
- `COMFYUI_API_URL`: ComfyUI 服务地址
- `COMFYUI_MODELS_DIR`: ComfyUI 模型目录（容器内路径）
- `DEBUG`: 调试模式
- `CORS_ORIGINS`: 允许的 CORS 源

> `NOVEL_ENABLED_SITES` 已随爬虫功能移除，不再使用。

## 数据模型

### Pydantic 模式（`app/schemas.py`）

- `Text2ImgGenerateRequest` - 文生图请求（prompt / model_name / negative_prompt）
- `WorkflowInfo` / `ModelsResponse` - 工作流与模型列表
- `BackupUploadResponse` / `BackupInfo` / `BackupListResponse` - 备份
- `LogEntrySchema` / `LogUploadRequest` / `LogUploadResponse` - 日志上报
- `ModelDirInfo` / `ModelUploadInit*` / `ModelChunkUploadResponse` / `ModelUploadStatusResponse` / `ModelUploadCompleteResponse` - 模型分块上传

> `Novel` / `Chapter` / `NovelWithChapters` / `ChapterContent` / `SourceSite` 五个爬虫相关 schema 已删除。

### SQLAlchemy 模型（`app/models/`）

- `text2img.py`: `Text2ImgTask`（文生图任务，prompt_id 唯一）、`ImageToVideoTask`（图生视频任务）
- `client_log.py`: `ClientLog`（客户端日志）

> `cache.py`（`ChapterCache` / `CacheTask`）、`chapter_list_cache.py`（`ChapterListCache`）已删除，对应数据库表由 `20260708_drop_cache_tables` 迁移 drop。

## 服务层架构（`app/services/`）

- `comfyui_client.py` - 统一的文生图 / 图生视频 ComfyUI 交互客户端
- `text2img_service.py` - 提交文生图任务 + 按 task_id 取图
- `image_to_video_service.py` - 提交图生视频任务 + 按 task_id 取视频

> `crawler_factory.py` / `search_service.py` / `novel_cache_service.py` / `http_client.py` / `base_crawler.py` / 各 `*_crawler.py` / `scrapling_*` / `cache_*` / `page_response.py` / `session_manager.py` 已全部删除。

### ComfyUI 工作流配置（`app/workflow_config/`）

- 加载 `workflows.yaml`，管理 T2I / I2V 工作流元数据
- `prompt_skill` 字段暴露给前端 LLM Agent（`list_text2img_models` 工具）用于撰写提示词

## 数据库设计

### PostgreSQL（生产）/ SQLite（本地）

- 连接管理: SQLAlchemy 连接池（`app/database.py`）
- 迁移工具: Alembic

### 核心表

1. **text2img_task** - 文生图任务
   - `prompt_id`（ComfyUI prompt_id，唯一索引，对外即 task_id）
   - `prompt` / `negative_prompt`（可选）/ `model_name` / `status` / `filename`
   - 提交即落库，完成后回填 filename
   - `negative_prompt` 由 `ComfyUIClient` 按工作流 JSON 占位符替换注入

2. **image_to_video_task** - 图生视频任务
   - `prompt_id`（唯一索引，对外即 task_id）
   - `prompt` / `model_name` / `image_filename` / `video_filename`

3. **client_logs** - 客户端日志

> `chapter_cache` / `cache_tasks` / `chapter_list_cache` 已 drop。

## 认证与安全

### Token 认证

- Header: `X-API-TOKEN`
- 验证: `app/deps/auth.py`
- 配置: 环境变量 `NOVEL_API_TOKEN`

### 安全措施

- SQL 注入防护: SQLAlchemy ORM
- CORS 配置: `CORS_ORIGINS` 环境变量
- 全局异常处理: `app/exceptions.py`

## ComfyUI 工作流占位符规范

`ComfyUIClient` 在提交任务时，会递归遍历工作流 JSON 并按字符串字面量匹配占位符后原地替换。约定如下：

| 占位符字符串 | 替换为 | 适用范围 |
|---|---|---|
| `提示词在这里替换` | `request.prompt` | 文生图/图生视频 |
| `负向提示词在这里替换` | `request.negative_prompt`（为 None/空时保留原值） | 仅文生图 |
| `在这替换随机数` | 1~999999 随机整数 | 文生图/图生视频 |
| `图片base64在这里替换` | 图生视频上传后的文件名 | 仅图生视频 |

**约束**:

- 工作流 JSON 必须含对应的占位符字符串才会被替换；不存在的字段（如用 `ConditioningZeroOut` 模拟负向的工作流）不影响提交，只是 `negative_prompt` 不会生效。
- 占位符必须作为字符串字面量直接出现在节点 `inputs.text` 等字段值中；若被 `StringConcatenate` / 节点连线引用，需要把字面量放在源头节点（如 `PrimitiveString.value`）上。
- 修改工作流 JSON 后必须重启 backend 才能重新加载（`ComfyUIClient` 在初始化时一次加载）。

**`workflows.yaml` 的 `prompt_skill` 字段**:

- 暴露给前端 LLM Agent（`list_text2img_models` 工具）用于撰写正向/负向提示词。
- 撰写规范：正向 -> 结构 + 示例；负向 -> 常用反向词；注意事项（是否支持负向、模型偏好）。

## 测试与质量

### 测试框架

- pytest + pytest-asyncio + pytest-cov + httpx

### 测试配置

```ini
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
asyncio_mode = "auto"
```

### 代码质量

- 静态检查: ruff / pylint / mypy（strict）
- 格式化: ruff format / black / isort

## 部署与运维

### Docker 部署

- 基础镜像: Python 3.11-slim（多阶段构建，`backend/Dockerfile`）
- 健康检查: `/health` 端点
- 已移除 Playwright / Scrapling 系统库与浏览器安装，镜像显著瘦身（**仅对生产 `Dockerfile` 属实**）

> **Dockerfile 残留提醒**（scope 之外）：`backend/Dockerfile.debug` 仍 `python -m playwright install chromium`，`backend/Dockerfile.test` 仍装 `scrapling[fetchers]` 与 `scrapling[core]`，`backend/Dockerfile.simple` 仍装 `beautifulsoup4 lxml`。根 `docker-compose.yml` 当前引用的就是 `Dockerfile.debug`，构建会失败。修复方式见根 CLAUDE.md「已知问题」节。

### 环境配置

```yaml
services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "3800:8000"
    environment:
      - NOVEL_API_TOKEN=${NOVEL_API_TOKEN}
      - DATABASE_URL=postgresql://...
      - COMFYUI_API_URL=http://host.docker.internal:8188
```

## 错误处理

### 异常分类

- 网络错误: ComfyUI 连接失败 / 超时
- 数据库错误: 连接和查询失败
- 任务错误: 文生图 / 图生视频任务失败

### 错误响应

- 标准格式: HTTP 状态码 + 错误详情（`app/exceptions.py`）
- 日志记录: 详细的错误上下文
- 用户友好: 可理解的错误消息

## 相关文件清单

### 核心文件

- `app/main.py` - FastAPI 应用入口（text2img / image-to-video / models 路由内联）
- `app/config.py` - 配置管理
- `app/database.py` - 数据库连接
- `app/models.py` - 模型 re-export
- `app/schemas.py` - Pydantic 模式
- `app/exceptions.py` - 异常处理

### 服务层

- `app/services/comfyui_client.py` - ComfyUI 客户端
- `app/services/text2img_service.py` - 文生图服务
- `app/services/image_to_video_service.py` - 图生视频服务
- `app/workflow_config/` - 工作流配置

### 路由

- `app/api/routes/backup.py` - 备份
- `app/api/routes/logs.py` - 日志上报
- `app/api/routes/models.py` - 模型分块上传

### 依赖与工具

- `app/deps/auth.py` - Token 鉴权
- `tests/conftest.py` - 测试 fixtures
- `alembic/` - 数据库迁移
- `pyproject.toml` - 项目配置
- `alembic.ini` - 迁移配置
- `Dockerfile` - 容器构建
- `.env.example` - 环境变量模板

## 开发工作流

### API 功能扩展

1. 定义 Pydantic 模式
2. 实现业务逻辑
3. 添加路由和认证
4. 编写集成测试
5. 更新 OpenAPI 文档

### 数据库变更

1. 创建 / 修改 SQLAlchemy 模型
2. 生成 Alembic 迁移（`alembic revision --autogenerate`）
3. 测试迁移脚本
4. 更新依赖注入
5. 验证数据完整性

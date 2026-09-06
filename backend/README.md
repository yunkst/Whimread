# Whimread Backend

FastAPI backend service for **novel AI image/video generation, backup, and model management**.

> 注：搜索与多站点爬虫相关功能已废弃移除，章节内容由前端 headless WebView + 本地 JS 提取脚本获取。
> 后端现在只提供 AI 文生图/图生视频（ComfyUI）、数据库备份、模型管理、客户端日志上报等能力。

## 🚀 Features

- **ComfyUI text-to-image** - 文生图任务提交与结果轮询
- **ComfyUI image-to-video** - 图生视频任务提交与结果轮询
- **Model management** - ComfyUI 工作流与可用模型列表
- **Database backup** - 客户端备份文件上传、列表、下载
- **Client log reporting** - 接收并持久化客户端日志
- **Token-based authentication** - 统一 X-API-TOKEN 鉴权
- **Modern Python project structure** - pyproject.toml + Alembic 迁移

## 📋 Prerequisites

- Python 3.11+
- Docker & Docker Compose (for containerized deployment)
- PostgreSQL 15+ (生产) / SQLite (本地开发)
- Git

## 🛠️ Development Setup

### Local Development

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd novel-builder/backend
   ```

2. **Create virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -e .
   pip install -e ".[dev]"
   ```

4. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

5. **Run pre-commit setup**
   ```bash
   pre-commit install
   ```

6. **Run the development server**
   ```bash
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

### Docker Development

```bash
docker-compose up --build
```

## 🧪 Testing

```bash
pytest                       # 全部测试（179+ 用例）
pytest --cov=app --cov-report=html
pytest tests/test_devices.py tests/test_llm_proxy.py   # 设备/额度/代理模块
```

## 🔍 Code Quality

```bash
ruff check .
pylint app/
mypy app/
ruff format .
black .
isort .
```

## 📁 Project Structure

```
backend/
├── app/
│   ├── api/routes/        # FastAPI 路由（backup, logs, models）
│   ├── models/            # SQLAlchemy 模型（text2img, client_log）
│   ├── schemas.py         # Pydantic 模型
│   ├── services/          # text2img / image_to_video / comfyui_client
│   ├── workflow_config/   # ComfyUI 工作流加载与配置
│   ├── deps/              # 鉴权依赖
│   ├── config.py
│   ├── database.py
│   └── main.py
├── tests/                 # conftest.py（fixtures + pytest 配置）
├── alembic/               # 数据库迁移
├── pyproject.toml
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

## 🔧 Configuration

主要环境变量（详见 `.env.example`）：

- `NOVEL_API_TOKEN`: API 鉴权 token（必需）
- `SECRET_KEY`: 应用密钥
- `DATABASE_URL`: SQLAlchemy 连接串（默认 SQLite；生产 PostgreSQL）
- `COMFYUI_API_URL`: ComfyUI 服务地址
- `COMFYUI_MODELS_DIR`: ComfyUI 模型目录（容器内路径）
- `DEBUG`: 调试模式开关
- `CORS_ORIGINS`: 允许的 CORS 源

## 📚 API Documentation

启动后访问：
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **OpenAPI Schema**: http://localhost:8000/openapi.json

### Authentication

所有受保护接口均需 `X-API-TOKEN` header：
```
X-API-TOKEN: your-api-token-here
```

### Main Endpoints

- `GET /health` - 健康检查
- `POST /api/text2img/generate` - 提交文生图任务
- `GET /api/text2img/image/{task_id}` - 取文生图结果
- `POST /api/image-to-video/generate` - 提交图生视频任务
- `GET /api/image-to-video/video/{task_id}` - 取图生视频结果
- `GET /api/models` - 可用工作流/模型列表
- `POST /api/backup/upload` - 上传数据库备份
- `GET /api/backup/list` - 列出已上传备份
- `GET /api/backup/download/{backup_id}` - 下载备份
- `POST /api/logs/upload` - 上报客户端日志

## 🚀 Deployment

```bash
docker build -t novel-backend .
docker run -p 8000:8000 --env-file .env novel-backend
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and code quality checks
5. Submit a pull request

### Code Style

- PEP 8
- Black / Ruff (line length: 88)
- MyPy (strict)
- PyLint

## 📄 License

MIT License - see LICENSE file for details.

## 🔍 Troubleshooting

- **Import errors**: 确认已激活虚拟环境
- **Permission denied**: 检查 Docker 权限
- **Port already in use**: 修改 docker-compose.yml 端口
- **Tests failing**: 检查环境变量与依赖
- **ComfyUI 图片生成失败**: 确认 ComfyUI 服务运行正常，`COMFYUI_API_URL` 配置正确
- **数据库迁移失败**: 确认 `DATABASE_URL` 指向可达的数据库

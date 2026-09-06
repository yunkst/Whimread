#!/usr/bin/env python3
"""
Pytest configuration and fixtures for Whimread Backend tests.

设计要点:
- 测试不依赖外部服务(ComfyUI / PostgreSQL),所有外部依赖在测试中被替换。
- 数据库隔离: 每个测试用独立的内存 SQLite (StaticPool + :memory:),通过
  `app.dependency_overrides[get_db]` 注入,保证零状态泄漏。
- Token 鉴权: 通过环境变量 `NOVEL_API_TOKEN` 在 Settings 单例初始化前注入,
  fixture 暴露正确 / 错误 token 与 header dict,供测试按需使用。
- 客户端: `TestClient` 同步包裹 FastAPI 异步端点,无需 pytest-asyncio 即可运行。
- 文件系统隔离: backup / models upload 路径通过 monkeypatch 重定向到 tmp。
"""

from __future__ import annotations

import os
import sys
import tempfile
from collections.abc import Generator, Iterator
from pathlib import Path

# ---- 环境变量引导 ---------------------------------------------------------
# 必须在 import app.* 之前设置,以便 Settings 单例与 database.engine 能正确初始化。
# - NOVEL_API_TOKEN: 给端点鉴权一个已知 token,测试 fixture 复用同一值。
# - DATABASE_URL: 指向临时文件 sqlite (内存库不支持 database.py 的 pool 参数);
#   实际测试通过 dependency_overrides 注入内存库,这里只是为了 import 不爆。
# - DEBUG: 关闭,避免 dev 模式下 "无 token 也放行" 改变鉴权契约。
_TOKEN = "test_token_123"
os.environ.setdefault("NOVEL_API_TOKEN", _TOKEN)
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-tests-only")
os.environ.setdefault("DEBUG", "false")
os.environ.setdefault("CORS_ORIGINS", "http://localhost")
# ComfyUI 不应在测试中被真实调用;测试用例会 mock 掉客户端。
os.environ.setdefault("COMFYUI_API_URL", "http://comfyui.test.invalid:8188")
# 临时文件 DB 路径,仅用于 import app.database 时 create_engine 不抛错。
_TEMP_DB_DIR = tempfile.mkdtemp(prefix="novel_test_import_")
os.environ.setdefault(
    "DATABASE_URL", f"sqlite:///{Path(_TEMP_DB_DIR) / 'import_only.db'}"
)

# 让 tests/ 能 import app.*
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402

# 触发模型注册(确保 Base.metadata 知道这些表)
import app.models.text2img as _t2i_models  # noqa: E402, F401
import app.models.client_log as _client_log_models  # noqa: E402, F401

# 模型供测试直接引用
Text2ImgTask = _t2i_models.Text2ImgTask  # noqa: E402
ImageToVideoTask = _t2i_models.ImageToVideoTask  # noqa: E402
ClientLog = _client_log_models.ClientLog  # noqa: E402


# ---- pytest 标记 ---------------------------------------------------------
def pytest_configure(config):
    """注册自定义 marker。"""
    config.addinivalue_line("markers", "auth: 涉及 X-API-TOKEN 鉴权的测试")
    config.addinivalue_line("markers", "integration: 跨层端到端集成测试")


# ---- 数据库 fixtures -----------------------------------------------------
def _make_memory_session() -> sessionmaker:
    """构造一次性内存 SQLite session 工厂 (StaticPool 保证同连接共享内存)。"""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


@pytest.fixture
def db_session() -> Iterator:
    """提供一个事务级隔离的内存 DB Session。

    每个 test 拿到全新的内存库 + session,结束后关闭,无跨用例状态。
    """
    session_local = _make_memory_session()
    session = session_local()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture(autouse=True)
def _override_get_db(db_session) -> Iterator[None]:
    """把 FastAPI 的 get_db 依赖替换为内存 session。

    autouse=True 让所有 client 触发的端点默认走内存库,无需各测试手动 override。
    """
    def _override():
        try:
            yield db_session
        finally:
            pass  # session 由 db_session fixture 关闭

    app.dependency_overrides[get_db] = _override
    try:
        yield
    finally:
        app.dependency_overrides.pop(get_db, None)


# ---- 客户端 fixtures -----------------------------------------------------
@pytest.fixture
def client() -> Iterator[TestClient]:
    """同步 TestClient (内部自动管理异步事件循环)。

    注: lifespan startup 会触发 init_db(),使用临时文件 DB;
    真实测试数据通过 dependency_overrides 注入,与此文件 DB 互不影响。
    """
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def app_instance():
    """暴露 FastAPI app 实例,供需要直接操作 dependency_overrides 的测试使用。"""
    return app


# ---- 鉴权 fixtures -------------------------------------------------------
@pytest.fixture
def valid_token() -> str:
    """与导入时 NOVEL_API_TOKEN 一致的 token。"""
    return _TOKEN


@pytest.fixture
def invalid_token() -> str:
    """明显错误的 token,用于断言 401。"""
    return "definitely-not-the-real-token"


@pytest.fixture
def auth_headers(valid_token) -> dict[str, str]:
    """正确鉴权 header dict。"""
    return {"X-API-TOKEN": valid_token}


@pytest.fixture
def bad_headers(invalid_token) -> dict[str, str]:
    """错误鉴权 header dict。"""
    return {"X-API-TOKEN": invalid_token}


# ---- 文件系统隔离 fixtures ----------------------------------------------
@pytest.fixture
def backup_dir(tmp_path, monkeypatch) -> Path:
    """把 backup 模块的 BACKUP_DIR 重定向到 tmp 目录。

    backup.py 在 import 时执行 `BACKUP_DIR = Path("backups")` (模块级常量),
    所以这里通过 setattr 改模块属性,而非 monkeypatch env。
    """
    from app.api.routes import backup as backup_module

    new_dir = tmp_path / "backups"
    new_dir.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(backup_module, "BACKUP_DIR", new_dir)
    return new_dir


@pytest.fixture
def models_root(tmp_path, monkeypatch) -> Path:
    """把 models upload 的 _models_root() (走 settings.comfyui_models_dir)
    重定向到 tmp 目录,创建 .tmp 子目录占位。
    """
    new_root = tmp_path / "models_root"
    new_root.mkdir(parents=True, exist_ok=True)
    (new_root / ".tmp").mkdir(parents=True, exist_ok=True)
    # settings 是 pydantic 实例,直接改属性即可
    from app.config import settings

    monkeypatch.setattr(settings, "comfyui_models_dir", str(new_root))
    return new_root

#!/usr/bin/env python3
"""
Database configuration and session management.

This module provides database connectivity, session management,
and initialization utilities for the application.
"""

import logging

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import settings

logger = logging.getLogger(__name__)

# 创建数据库引擎
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,  # 连接池预检，确保连接有效
    pool_size=20,  # 增加连接池大小
    max_overflow=30,  # 增加溢出连接数
    pool_recycle=3600,  # 1小时回收连接，防止连接泄漏
    pool_timeout=60,  # 增加获取连接的超时时间
    echo=False,
)

# 创建会话工厂 - 使用 UPPER_CASE 常量命名
SESSION_LOCAL = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """ORM 基类（SQLAlchemy 2.0 DeclarativeBase，兼容 Column 与 Mapped 两种声明）"""


def get_db():
    """获取数据库会话（用于依赖注入）"""
    db = SESSION_LOCAL()
    try:
        yield db
    finally:
        db.close()


class DatabaseSession:
    """数据库会话上下文管理器"""

    def __init__(self):
        """初始化数据库会话管理器。"""
        self.db = None

    def __enter__(self):
        self.db = SESSION_LOCAL()
        return self.db

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type:
            self.db.rollback()
        else:
            self.db.commit()
        self.db.close()


def init_db():
    """初始化数据库（创建所有表）

    使用 Base.metadata.create_all 创建表,适用于本地开发快速启动。
    生产环境应使用 ``alembic upgrade head`` 进行迁移,以保留 schema 演进历史。
    """
    try:
        # 导入所有模型以确保它们被注册
        import app.models  # noqa: F401

        logger.warning(
            "init_db 使用 Base.metadata.create_all 创建表;生产环境应使用 "
            "'alembic upgrade head' 进行迁移,以保留 schema 演进历史。"
        )
        # 创建所有表
        Base.metadata.create_all(bind=engine)
        logger.info("数据库表创建成功")
    except Exception as e:
        logger.exception(f"数据库初始化失败: {e}")
        raise

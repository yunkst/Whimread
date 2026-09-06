#!/usr/bin/env python3
"""
日志配置模块

提供统一的日志配置和管理，支持结构化日志输出和不同级别的日志控制。
"""

import logging
import logging.handlers
import sys
from pathlib import Path

from .config import settings


def setup_logging(
    log_level: str | None = None,
    log_file: str | None = None,
    enable_console: bool = True,
    enable_file: bool = True,
) -> logging.Logger:
    """
    设置应用程序日志配置。

    Args:
        log_level: 日志级别 (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_file: 日志文件路径
        enable_console: 是否启用控制台输出
        enable_file: 是否启用文件输出

    Returns:
        logging.Logger: 配置好的根logger
    """
    # 确定日志级别（显式解析为 int，避免 getattr 的 str 默认值类型污染）
    level_name = str(log_level or ("DEBUG" if settings.debug else "INFO")).upper()
    resolved_level = logging.getLevelName(level_name)
    effective_level: int = (
        resolved_level if isinstance(resolved_level, int) else logging.INFO
    )

    # 创建根logger
    root_logger = logging.getLogger()
    root_logger.setLevel(effective_level)

    # 清除现有的处理器
    root_logger.handlers.clear()

    # 定义日志格式
    formatter = logging.Formatter(
        fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # 控制台处理器
    if enable_console:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(effective_level)
        console_handler.setFormatter(formatter)
        root_logger.addHandler(console_handler)

    # 文件处理器
    if enable_file:
        # 确保日志目录存在
        log_path = Path(log_file or "novel_builder.log")
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # 使用轮转文件处理器，避免日志文件过大
        file_handler = logging.handlers.RotatingFileHandler(
            filename=log_path,
            maxBytes=10 * 1024 * 1024,  # 10MB
            backupCount=5,
            encoding="utf-8",
        )
        file_handler.setLevel(effective_level)
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)

    # 设置第三方库的日志级别
    logging.getLogger("uvicorn").setLevel(logging.INFO)
    logging.getLogger("fastapi").setLevel(logging.INFO)
    logging.getLogger("sqlalchemy").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)

    # 记录配置信息
    root_logger.info(
        f"日志系统初始化完成 - 级别: {level_name}, "
        f"控制台: {enable_console}, 文件: {enable_file}"
    )

    return root_logger


def get_logger(name: str) -> logging.Logger:
    """
    获取指定名称的logger。

    Args:
        name: logger名称，通常使用 __name__

    Returns:
        logging.Logger: 命名logger
    """
    return logging.getLogger(name)


class LoggerMixin:
    """
    Logger混入类，为类提供日志功能。

    使用方法:
        class MyClass(LoggerMixin):
            def __init__(self):
                super().__init__()
                self.logger.info("初始化完成")
    """

    @property
    def logger(self) -> logging.Logger:
        """获取当前类的logger"""
        return get_logger(self.__class__.__module__ + "." + self.__class__.__name__)


def log_function_call(func):
    """
    装饰器：记录函数调用信息。

    使用方法:
        @log_function_call
        def my_function(arg1, arg2):
            return arg1 + arg2
    """
    import functools
    import inspect

    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        logger = get_logger(func.__module__)
        func_name = func.__name__

        # 获取函数签名
        sig = inspect.signature(func)
        bound_args = sig.bind(*args, **kwargs)
        bound_args.apply_defaults()

        # 记录函数调用
        logger.debug(f"调用函数 {func_name} 参数: {bound_args.arguments}")

        try:
            result = func(*args, **kwargs)
            logger.debug(f"函数 {func_name} 执行成功")
            return result
        except Exception as e:
            logger.error(f"函数 {func_name} 执行失败: {e}")
            raise

    return wrapper


# 初始化默认日志配置
if not logging.getLogger().handlers:
    setup_logging()

#!/usr/bin/env python3
"""
Whimread Backend Application

A FastAPI-based web service for novel content crawling and caching.
"""

try:
    from importlib.metadata import PackageNotFoundError
    from importlib.metadata import version as _pkg_version
except ImportError:  # pragma: no cover - Python < 3.8 fallback
    from importlib_metadata import PackageNotFoundError  # type: ignore
    from importlib_metadata import version as _pkg_version

try:
    # 唯一来源:pyproject.toml [project].version
    __version__ = _pkg_version("novel-builder-backend")
except PackageNotFoundError:
    # 包未安装(如直接 PYTHONPATH=backend 运行 dev 模式),回退到字面量。
    # 此字面量仅作 dev fallback,正式发布以 pyproject.toml 为准。
    __version__ = "0.2.0"

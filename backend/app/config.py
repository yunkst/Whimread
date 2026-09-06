#!/usr/bin/env python3
"""
Configuration settings for the Whimread Backend.

This module contains application configuration using Pydantic BaseSettings
for environment variable management.
"""

import os
import secrets

from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """
    Application settings class.

    Manages configuration through environment variables with secure defaults.
    """

    model_config = {"populate_by_name": True}

    token_header: str = "X-API-TOKEN"

    # 安全配置
    api_token: str = Field(default="", alias="NOVEL_API_TOKEN")
    secret_key: str = ""
    # 标记 secret_key 是否由用户主动设置(True)或由 Settings 自动生成(False)。
    # 程序自身生成的随机 secret_key 不应被视为"已配置"。
    has_custom_secret_key: bool = False

    # 开发环境配置
    debug: bool = False

    # Database settings for caching functionality
    database_url: str = "sqlite:///novel_cache.db"

    # ComfyUI服务配置
    comfyui_api_url: str = "http://host.docker.internal:8188"
    # ComfyUI 模型目录（容器内路径），用于模型文件上传落地
    comfyui_models_dir: str = Field(default="/app/models", alias="COMFYUI_MODELS_DIR")

    # 图生视频相关配置
    video_generation_timeout: int = 600  # 10分钟

    # 安全配置
    cors_origins: str = "http://localhost:3154"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        # secret_key 处理:仅当用户通过环境变量/参数显式提供非空值时,
        # 才视为已自定义;否则生成一次性随机值(进程重启即变,不应被视为安全配置)。
        env_secret = os.getenv("SECRET_KEY", "").strip()
        explicit_secret = (self.secret_key or "").strip()
        if explicit_secret and explicit_secret == env_secret:
            self.has_custom_secret_key = True
            self.secret_key = explicit_secret
        elif env_secret:
            self.has_custom_secret_key = True
            self.secret_key = env_secret
        else:
            # 未配置:生成临时随机值,后续 is_secure() 会返回 False
            self.has_custom_secret_key = False
            self.secret_key = secrets.token_urlsafe(32)

        # 开发环境警告
        if self.debug:
            if not self.api_token:
                print("⚠️  警告: 开发环境下未设置API_TOKEN，所有请求将被允许")
            if not self.has_custom_secret_key:
                print(
                    f"⚠️  警告: 未设置 SECRET_KEY,使用自动生成的临时值: "
                    f"{self.secret_key[:8]}..."
                )

    def is_secure(self) -> bool:
        """检查是否为安全的生产配置"""
        return (
            self.api_token != ""
            and self.api_token != "your-api-token-here"
            and self.has_custom_secret_key
            and self.secret_key != "your-secret-key-here"
            and not self.debug
        )


settings = Settings()

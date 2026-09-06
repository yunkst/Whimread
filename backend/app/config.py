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

    # ===== 设备注册与免费额度 =====
    # 新设备注册发放的免费额度（点数）
    device_free_quota: int = Field(default=500, alias="DEVICE_FREE_QUOTA")
    # 是否强制 Android Key Attestation（生产必须 true；本地联调可关）
    attestation_required: bool = Field(default=True, alias="ATTESTATION_REQUIRED")
    # 官方 release APK 签名证书的 SHA-256（attestation 里必须匹配）
    expected_apk_signature_sha256: str = Field(
        default="", alias="EXPECTED_APK_SIGNATURE_SHA256"
    )
    # 设备 token 有效期（天）
    jwt_expire_days: int = Field(default=30, alias="JWT_EXPIRE_DAYS")
    # 同一 IP 每小时最多注册的设备数（IP 聚类风控第一道闸）
    device_register_rate_limit_per_hour: int = Field(
        default=5, alias="DEVICE_REGISTER_RATE_LIMIT_PER_HOUR"
    )

    # ===== LLM 上游代理 =====
    # OpenAI 兼容上游（如 DeepSeek）。三者任一为空视为上游未配置，代理端点返回 503。
    llm_upstream_base_url: str = Field(default="", alias="LLM_UPSTREAM_BASE_URL")
    llm_upstream_api_key: str = Field(default="", alias="LLM_UPSTREAM_API_KEY")
    # 服务端强制覆写的模型名（客户端传什么都会被替换，模型选择权在服务端）
    llm_upstream_model: str = Field(default="", alias="LLM_UPSTREAM_MODEL")

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

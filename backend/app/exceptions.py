#!/usr/bin/env python3
"""
自定义异常类模块

定义应用程序中使用的各种自定义异常，提供更好的错误分类和处理。
每个异常类携带 status_code 属性,供全局异常处理器映射到正确的 HTTP 状态码。
"""

from typing import Any


class NovelBuilderException(Exception):
    """基础异常类，所有自定义异常的基类"""

    # 默认状态码,子类按语义覆盖
    status_code: int = 500

    def __init__(
        self,
        message: str,
        error_code: str | None = None,
        details: dict[str, Any] | None = None,
    ):
        super().__init__(message)
        self.message = message
        self.error_code = error_code or self.__class__.__name__
        self.details = details or {}

    def to_dict(self) -> dict[str, Any]:
        """转换为字典格式，便于API响应"""
        return {
            "error": self.error_code,
            "message": self.message,
            "details": self.details,
        }


class AuthenticationError(NovelBuilderException):
    """认证相关错误"""

    status_code = 401

    def __init__(
        self, message: str = "认证失败", error_code: str | None = None, **kwargs
    ):
        # 允许调用方细化 error_code（如 DEVICE_TOKEN_EXPIRED / ATTESTATION_*
        # / CHALLENGE_INVALID），客户端据此区分处理；未指定时保持默认
        super().__init__(message, error_code or "AUTH_ERROR", **kwargs)


class ConfigurationError(NovelBuilderException):
    """配置相关错误"""

    status_code = 500

    def __init__(self, message: str = "配置错误", **kwargs):
        super().__init__(message, "CONFIG_ERROR", **kwargs)


class DatabaseError(NovelBuilderException):
    """数据库相关错误"""

    status_code = 500

    def __init__(
        self,
        message: str = "数据库操作失败",
        operation: str | None = None,
        table: str | None = None,
        **kwargs,
    ):
        details = kwargs.get("details", {})
        if operation:
            details["operation"] = operation
        if table:
            details["table"] = table
        kwargs["details"] = details

        super().__init__(message, "DATABASE_ERROR", **kwargs)


class ValidationError(NovelBuilderException):
    """数据验证错误"""

    status_code = 400

    def __init__(
        self,
        message: str = "数据验证失败",
        field: str | None = None,
        value: Any | None = None,
        error_code: str | None = None,
        **kwargs,
    ):
        details = kwargs.get("details", {})
        if field:
            details["field"] = field
        if value is not None:
            details["value"] = str(value)
        kwargs["details"] = details

        super().__init__(message, error_code or "VALIDATION_ERROR", **kwargs)


class ContentNotFoundError(NovelBuilderException):
    """内容未找到错误"""

    status_code = 404

    def __init__(
        self,
        message: str = "请求的内容不存在",
        content_type: str | None = None,
        identifier: str | None = None,
        error_code: str | None = None,
        **kwargs,
    ):
        details = kwargs.get("details", {})
        if content_type:
            details["content_type"] = content_type
        if identifier:
            details["identifier"] = identifier
        kwargs["details"] = details

        super().__init__(message, error_code or "NOT_FOUND", **kwargs)


class RateLimitError(NovelBuilderException):
    """频率限制错误"""

    status_code = 429

    def __init__(
        self,
        message: str = "请求频率过高",
        retry_after: int | None = None,
        limit: int | None = None,
        error_code: str | None = None,
        **kwargs,
    ):
        details = kwargs.get("details", {})
        if retry_after:
            details["retry_after"] = retry_after
        if limit:
            details["limit"] = limit
        kwargs["details"] = details

        super().__init__(message, error_code or "RATE_LIMIT", **kwargs)


class ExternalServiceError(NovelBuilderException):
    """外部服务错误(如 ComfyUI 调用失败)"""

    # 默认 502(Bad Gateway);特定场景(如服务不可用)可由调用方覆盖实例的 status_code
    status_code = 502

    def __init__(
        self,
        message: str = "外部服务调用失败",
        service_name: str | None = None,
        service_url: str | None = None,
        error_code: str | None = None,
        **kwargs,
    ):
        details = kwargs.get("details", {})
        if service_name:
            details["service_name"] = service_name
        if service_url:
            details["service_url"] = service_url
        kwargs["details"] = details

        super().__init__(message, error_code or "EXTERNAL_SERVICE_ERROR", **kwargs)


def handle_exception(exc: Exception, logger=None) -> NovelBuilderException:
    """
    将标准异常转换为自定义异常。

    Args:
        exc: 原始异常
        logger: 日志记录器

    Returns:
        NovelBuilderException: 转换后的自定义异常
    """
    if logger:
        logger.exception(f"处理异常: {exc}")

    # 已经是自定义异常，直接返回(保留其 status_code)
    if isinstance(exc, NovelBuilderException):
        return exc

    # 根据异常类型进行转换
    if isinstance(exc, ConnectionError):
        return ExternalServiceError(f"网络连接错误: {exc}")
    elif isinstance(exc, TimeoutError):
        return ExternalServiceError(f"请求超时: {exc}")
    elif isinstance(exc, ValueError):
        return ValidationError(f"数据验证错误: {exc}")
    elif isinstance(exc, KeyError):
        return ValidationError(f"缺少必需字段: {exc}")
    elif isinstance(exc, AttributeError):
        # 不再伪装为 ParseError(已删);AttributeError 通常是真实 bug,
        # 用通用 NovelBuilderException 抛出,保留原始类型信息便于排查。
        return NovelBuilderException(f"属性访问错误: {exc}", "ATTRIBUTE_ERROR")
    else:
        return NovelBuilderException(f"未知错误: {exc}", "UNKNOWN_ERROR")

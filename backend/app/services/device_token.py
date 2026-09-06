#!/usr/bin/env python3
"""
Device token（JWT）签发与校验。

设备通过 challenge/register 换取 30 天期 JWT（sub=device_id），
此后调用 /v1/chat/completions 时以 Authorization: Bearer 携带。
"""

import logging
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt

from ..config import settings
from ..exceptions import AuthenticationError

logger = logging.getLogger(__name__)


def issue_device_token(device_id: int) -> str:
    """为设备签发 JWT（HS256，sub=device_id，含 iat/exp/jti）。"""
    now = datetime.now(UTC)
    payload = {
        "sub": str(device_id),
        "iat": now,
        "exp": now + timedelta(days=settings.jwt_expire_days),
        "typ": "device",
    }
    return jwt.encode(payload, settings.secret_key, algorithm=settings.jwt_algorithm)


def verify_device_token(token: str) -> int:
    """校验设备 JWT，返回 device_id。

    Raises:
        AuthenticationError: 过期/签名无效/类型不符
    """
    try:
        payload: dict[str, Any] = jwt.decode(
            token, settings.secret_key, algorithms=[settings.jwt_algorithm]
        )
    except jwt.ExpiredSignatureError as e:
        raise AuthenticationError(
            "设备凭证已过期，请重新注册", error_code="DEVICE_TOKEN_EXPIRED"
        ) from e
    except jwt.InvalidTokenError as e:
        raise AuthenticationError(
            "设备凭证无效", error_code="DEVICE_TOKEN_INVALID"
        ) from e

    if payload.get("typ") != "device" or payload.get("sub") is None:
        raise AuthenticationError("设备凭证类型错误", error_code="DEVICE_TOKEN_INVALID")
    try:
        return int(payload["sub"])
    except (TypeError, ValueError) as e:
        raise AuthenticationError(
            "设备凭证载荷错误", error_code="DEVICE_TOKEN_INVALID"
        ) from e

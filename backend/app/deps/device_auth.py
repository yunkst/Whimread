#!/usr/bin/env python3
"""
设备 JWT 的 FastAPI 依赖：从 Authorization: Bearer 解析并校验设备身份。
"""

import logging

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from ..database import get_db
from ..exceptions import AuthenticationError
from ..models import Device
from ..services.device_token import verify_device_token

logger = logging.getLogger(__name__)


def _extract_bearer_token(request: Request) -> str:
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        raise AuthenticationError(
            "缺少设备凭证（Authorization: Bearer）",
            error_code="DEVICE_TOKEN_MISSING",
        )
    return auth[7:].strip()


def verify_device(
    request: Request,
    db: Session = Depends(get_db),
) -> Device:
    """校验设备 JWT 并返回 Device（status 必须为 active）。"""
    token = _extract_bearer_token(request)
    device_id = verify_device_token(token)
    device = db.get(Device, device_id)
    if device is None:
        raise AuthenticationError("设备不存在", error_code="DEVICE_NOT_FOUND")
    if device.status != "active":
        raise AuthenticationError("设备已被禁用", error_code="DEVICE_BLOCKED")
    return device

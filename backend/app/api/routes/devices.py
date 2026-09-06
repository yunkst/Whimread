#!/usr/bin/env python3
"""
设备注册路由：/api/v1/devices/challenge 与 /api/v1/devices/register。

注册成功即建立匿名设备账户并发放免费额度，返回设备 JWT。
"""

import hashlib
import logging

from fastapi import APIRouter, Depends, Header, Request
from fastapi.security.utils import get_authorization_scheme_param
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ...config import settings
from ...database import get_db
from ...exceptions import AuthenticationError
from ...models import Device
from ...services.challenge_store import challenge_store
from ...services.device_attestation import verify_key_attestation
from ...services.device_token import issue_device_token
from ...services.quota import grant_quota

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/devices", tags=["devices"])


class ChallengeResponse(BaseModel):
    nonce: str
    attestation_required: bool


class DeviceRegisterRequest(BaseModel):
    android_id: str = Field(min_length=8, max_length=64)
    platform: str = Field(default="android", max_length=20)
    app_version: str = Field(default="", max_length=32)
    challenge: str
    # Key Attestation 证书链，顺序 [叶子, ..., 根]
    certificate_chain_pem: list[str] = Field(default_factory=list)


class DeviceRegisterResponse(BaseModel):
    device_id: int
    token: str
    quota_balance: int
    attestation_verified: bool


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client is None:
        return "unknown"
    return request.client.host


def _android_id_hash(android_id: str) -> str:
    # 服务端侧加盐哈希，杜绝原文入库
    salt = settings.secret_key
    return hashlib.sha256(f"{salt}:{android_id}".encode()).hexdigest()


@router.post("/challenge", response_model=ChallengeResponse)
def create_challenge(request: Request) -> ChallengeResponse:
    """签发一次性注册 challenge（60-120 秒有效，仅可使用一次）。"""
    nonce = challenge_store.issue(_client_ip(request))
    return ChallengeResponse(
        nonce=nonce, attestation_required=settings.attestation_required
    )


@router.post("/register", response_model=DeviceRegisterResponse)
def register_device(
    payload: DeviceRegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> DeviceRegisterResponse:
    """注册设备：验证 attestation → 去重发额度 → 签发设备 JWT。"""
    if not challenge_store.consume(payload.challenge):
        raise AuthenticationError(
            "challenge 无效或已过期", error_code="CHALLENGE_INVALID"
        )

    attested = False
    security_level: str | None = None
    if settings.attestation_required:
        result = verify_key_attestation(
            certificate_chain_pem=payload.certificate_chain_pem,
            expected_challenge=payload.challenge,
        )
        attested = result.verified
        security_level = result.security_level
    else:
        logger.info("Attestation disabled (dev mode), device registered unattested")

    android_id_hash = _android_id_hash(payload.android_id)
    device = db.query(Device).filter(Device.android_id_hash == android_id_hash).first()

    if device is None:
        device = Device(
            android_id_hash=android_id_hash,
            platform=payload.platform,
            app_version=payload.app_version,
            attestation_verified=attested,
            attestation_security_level=security_level,
            quota_balance=0,
        )
        db.add(device)
        db.flush()
        grant_quota(
            db,
            device,
            settings.device_free_quota,
            reason="free_grant",
            ref=f"register:{device.id}",
        )
        logger.info(
            "New device registered: id=%s platform=%s attested=%s(%s) quota=%s",
            device.id,
            payload.platform,
            attested,
            security_level,
            settings.device_free_quota,
        )
    else:
        # 卸载重装：同一 android_id 不重复发额度，只补发 token
        if attested and not device.attestation_verified:
            device.attestation_verified = True
            device.attestation_security_level = security_level
        if device.status != "active":
            raise AuthenticationError("设备已被禁用", error_code="DEVICE_BLOCKED")
        logger.info("Existing device re-registered: id=%s", device.id)

    device.last_active_at = _utc_now()
    db.commit()

    return DeviceRegisterResponse(
        device_id=device.id,
        token=issue_device_token(device.id),
        quota_balance=device.quota_balance,
        attestation_verified=attested,
    )


@router.get("/me")
def device_me(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict:
    """设备自查：余额与状态（Bearer JWT 鉴权，供 APP 额度页展示）。"""
    scheme, token = get_authorization_scheme_param(authorization or "")
    if scheme.lower() != "bearer" or not token:
        raise AuthenticationError("缺少设备凭证", error_code="DEVICE_TOKEN_MISSING")
    from ...services.device_token import verify_device_token

    device_id = verify_device_token(token)
    device = db.get(Device, device_id)
    if device is None or device.status != "active":
        raise AuthenticationError("设备不可用", error_code="DEVICE_BLOCKED")
    return {
        "device_id": device.id,
        "quota_balance": device.quota_balance,
        "attestation_verified": device.attestation_verified,
        "status": device.status,
    }


def _utc_now():
    from datetime import UTC, datetime

    return datetime.now(UTC)

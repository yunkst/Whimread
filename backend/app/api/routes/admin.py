#!/usr/bin/env python3
"""
管理端审计查询：沿用静态 X-API-TOKEN 鉴权（verify_token），供运维对账。

- GET /api/admin/usage/{device_id}：设备用量明细 + 额度流水
"""

import logging

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...database import get_db
from ...deps.auth import verify_token
from ...exceptions import ContentNotFoundError
from ...models import Device, QuotaTransaction, UsageLog

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/admin", tags=["admin"], dependencies=[Depends(verify_token)]
)


@router.get("/usage/{device_id}")
def get_device_usage(device_id: int, db: Session = Depends(get_db)) -> dict:
    """按设备查用量审计与额度流水（最近 500 条）。"""
    device = db.get(Device, device_id)
    if device is None:
        raise ContentNotFoundError(f"设备不存在: {device_id}")

    usage_rows = (
        db.execute(
            select(UsageLog)
            .where(UsageLog.device_id == device_id)
            .order_by(UsageLog.created_at.desc())
            .limit(500)
        )
        .scalars()
        .all()
    )
    tx_rows = (
        db.execute(
            select(QuotaTransaction)
            .where(QuotaTransaction.device_id == device_id)
            .order_by(QuotaTransaction.created_at.desc())
            .limit(500)
        )
        .scalars()
        .all()
    )

    return {
        "device": {
            "id": device.id,
            "platform": device.platform,
            "app_version": device.app_version,
            "attestation_verified": device.attestation_verified,
            "attestation_security_level": device.attestation_security_level,
            "quota_balance": device.quota_balance,
            "status": device.status,
            "created_at": device.created_at.isoformat() if device.created_at else None,
        },
        "usage": [
            {
                "id": u.id,
                "model": u.model,
                "status": u.status,
                "quota_cost": u.quota_cost,
                "prompt_tokens": u.prompt_tokens,
                "completion_tokens": u.completion_tokens,
                "error": u.error,
                "latency_ms": u.latency_ms,
                "created_at": u.created_at.isoformat() if u.created_at else None,
            }
            for u in usage_rows
        ],
        "quota_transactions": [
            {
                "id": t.id,
                "delta": t.delta,
                "reason": t.reason,
                "balance_after": t.balance_after,
                "ref": t.ref,
                "created_at": t.created_at.isoformat() if t.created_at else None,
            }
            for t in tx_rows
        ],
    }

#!/usr/bin/env python3
"""
额度服务：发放 / 扣减 / 审计记录。

约束：quota_balance 的每次变动必须与 QuotaTransaction 流水同事务写入；
扣减用「条件 UPDATE（balance >= cost）+ 行级受影响数判断」实现乐观并发控制，
天然防双扣，不依赖 SELECT ... FOR UPDATE（SQLite/PG 双方言兼容）。
"""

import logging
import time
from typing import Any

from sqlalchemy import update
from sqlalchemy.engine import CursorResult
from sqlalchemy.orm import Session

from ..models import Device, QuotaTransaction, UsageLog

logger = logging.getLogger(__name__)


def grant_quota(
    session: Session, device: Device, amount: int, reason: str, ref: str | None = None
) -> None:
    """发放额度（注册赠送/管理员调整），必须正数。"""
    if amount <= 0:
        raise ValueError("发放额度必须为正数")
    device.quota_balance += amount
    session.add(
        QuotaTransaction(
            device_id=device.id,
            delta=amount,
            reason=reason,
            balance_after=device.quota_balance,
            ref=ref,
        )
    )


def deduct_quota(
    session: Session, device_id: int, cost: int, ref: str | None = None
) -> bool:
    """原子扣减额度；余额不足返回 False（不扣不减不写流水）。

    条件 UPDATE 保证并发下不会扣成负数：受影响行数=0 即余额不足或设备不存在。
    """
    if cost <= 0:
        return True
    result = session.execute(
        update(Device)
        .where(Device.id == device_id, Device.quota_balance >= cost)
        .values(quota_balance=Device.quota_balance - cost)
    )
    assert isinstance(result, CursorResult)
    if result.rowcount == 0:
        return False
    device = session.get(Device, device_id)
    assert device is not None, "条件 UPDATE 命中后设备必然存在"
    session.add(
        QuotaTransaction(
            device_id=device_id,
            delta=-cost,
            reason="usage",
            balance_after=device.quota_balance,
            ref=ref,
        )
    )
    return True


def record_usage(
    session: Session,
    device_id: int,
    *,
    model: str,
    status: str,
    quota_cost: int = 0,
    prompt_tokens: int | None = None,
    completion_tokens: int | None = None,
    error: str | None = None,
    latency_ms: int | None = None,
    endpoint: str = "/v1/chat/completions",
) -> UsageLog:
    """落一条用量审计记录（成败都记）。"""
    log = UsageLog(
        device_id=device_id,
        endpoint=endpoint,
        model=model,
        status=status,
        quota_cost=quota_cost,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        error=(error or "")[:512] or None,
        latency_ms=latency_ms,
    )
    session.add(log)
    return log


def touch_device(session: Session, device_id: int) -> None:
    """更新设备活跃时间（限频：60 秒内不重复写，避免高频代理请求打写库）。"""
    device = session.get(Device, device_id)
    if device is None:
        return
    now = time.time()
    last = device.last_active_at
    last_ts = last.timestamp() if last is not None else 0
    if now - last_ts >= 60:
        device.last_active_at = _utc_now()


def _utc_now() -> Any:
    from datetime import UTC, datetime

    return datetime.now(UTC)

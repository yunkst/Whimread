#!/usr/bin/env python3
"""
Device model for anonymous device accounts.

每台安装了 Whimread 的设备通过 Key Attestation 注册为一个匿名账户，
免费额度挂在设备上；登录账号体系（未来）可将 account 挂到 device。
"""

from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..database import Base


class Device(Base):
    """设备账户表：匿名档免费额度的载体"""

    __tablename__ = "devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # Android ID 的 SHA-256（服务端不存原文，最小化敏感数据）；同签名重装不变，
    # 用于防止卸载重装重复领取免费额度
    android_id_hash: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True
    )
    platform: Mapped[str] = mapped_column(String(20), nullable=False, default="android")
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)

    # Key Attestation 结果
    attestation_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    # TrustedEnvironment(硬件) / Software / None
    attestation_security_level: Mapped[str | None] = mapped_column(
        String(32), nullable=True
    )

    # 额度余额（点数）。只允许通过 quota_service 扣减/充值，每次变动必须写流水
    quota_balance: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="active", index=True
    )  # active / blocked

    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=lambda: datetime.now(UTC)
    )
    last_active_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=lambda: datetime.now(UTC)
    )

    __table_args__ = (Index("idx_devices_status_created", "status", "created_at"),)

    def __repr__(self):
        return (
            f"<Device(id={self.id}, android_id_hash={self.android_id_hash[:8]}..., "
            f"quota_balance={self.quota_balance}, status={self.status})>"
        )
